import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/ad_service.dart';
import '../../core/analytics_service.dart';
import '../../data/record_repository.dart';
import '../../data/subscription_repository.dart';
import '../../data/sync_gate.dart';
import '../../models/quiet_hours.dart';
import '../../models/record.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';

const _uuid = Uuid();

/// Çevrimiçi/çevrimdışı durumu (üst bar sync rozeti için).
final onlineProvider = StreamProvider<bool>(
  (ref) => Connectivity()
      .onConnectivityChanged
      .map((r) => !r.contains(ConnectivityResult.none)),
);

/// Bir bebeğin TÜM kayıtları (grafik agregasyonları için). Büyük olabilir.
final recordsProvider = StreamProvider.family<List<Record>, String>(
  (ref, babyId) => ref.watch(recordRepositoryProvider).watch(babyId),
);

/// Ana sayfa "son kayıtlar" — yalnız son N (tümünü çekmez).
final recentRecordsProvider = StreamProvider.family<List<Record>, String>(
  (ref, babyId) => ref.watch(recordRepositoryProvider).watchRecent(babyId),
);

/// Ana sayfa "Son Aktivite" — her tipin en son kaydı (son-15 penceresine
/// takılmaz; seyrek tipler de doğru görünür).
final latestByTypeProvider =
    StreamProvider.family<Map<RecordType, Record>, String>(
  (ref, babyId) =>
      ref.watch(recordRepositoryProvider).watchLatestByType(babyId),
);

/// Bugünün kayıtları (gece yarısından beri) — "Bugün" özeti için.
final todayRecordsProvider = StreamProvider.family<List<Record>, String>(
  (ref, babyId) {
    final now = DateTime.now();
    return ref
        .watch(recordRepositoryProvider)
        .watchSince(babyId, DateTime(now.year, now.month, now.day));
  },
);

/// Timeline tek-gün görünümü — seçili günün kayıtları (gün değişince autoDispose).
typedef DayKey = ({String babyId, DateTime day});
final dayRecordsProvider = StreamProvider.autoDispose.family<List<Record>, DayKey>(
  (ref, key) => ref.watch(recordRepositoryProvider).watchDay(key.babyId, key.day),
);

/// Akış için sayfalı kayıt (infinite scroll). Anahtar: bebek + limit + tip.
/// autoDispose: limit artınca eski limit'in drift stream'i kapanır (birikmez).
typedef PageKey = ({String babyId, int limit, RecordType? type});
final pagedRecordsProvider = StreamProvider.autoDispose.family<List<Record>, PageKey>(
  (ref, key) => ref
      .watch(recordRepositoryProvider)
      .watchPaged(key.babyId, limit: key.limit, type: key.type),
);

/// Akış filtresinde gösterilecek tipler (kaydı olanlar).
final presentTypesProvider = FutureProvider.family<Set<RecordType>, String>(
  (ref, babyId) => ref.watch(recordRepositoryProvider).presentTypes(babyId),
);

/// Aktif (bitmemiş) uyku — son uyku kaydından (ucuz stream).
final _ongoingSleepStream = StreamProvider.family<Record?, String>(
  (ref, babyId) => ref.watch(recordRepositoryProvider).watchOngoingSleep(babyId),
);
final ongoingSleepProvider = Provider.family<Record?, String>(
  (ref, babyId) => ref.watch(_ongoingSleepStream(babyId)).asData?.value,
);

/// Aktif (bitmemiş) emzirme sayacı.
final _ongoingBreastStream = StreamProvider.family<Record?, String>(
  (ref, babyId) => ref.watch(recordRepositoryProvider).watchOngoingBreast(babyId),
);
final ongoingBreastProvider = Provider.family<Record?, String>(
  (ref, babyId) => ref.watch(_ongoingBreastStream(babyId)).asData?.value,
);

/// Soket YOK — bunun yerine yoklama (polling) ile yakın-gerçek-zamanlı sync.
/// Delta-sync şu durumlarda tetiklenir: çevrimiçi olunca, oturum/bebek hazır
/// olunca, uygulama öne gelince ve **dakikada bir**. Her turda bekleyen yerel
/// değişiklikler gönderilir + sunucudaki (diğer aile üyelerinin) değişiklikleri
/// çekilir. Arka planda pili korumak için yoklama durdurulur.
class SyncService with WidgetsBindingObserver {
  final Ref _ref;
  StreamSubscription? _sub;
  Timer? _poll;
  Timer? _debounce; // push tetikli sync'i coalesce et
  bool _running = false; // çakışan eşitleme turlarını önle
  bool _pending = false; // tur sürerken gelen istek → tur bitince bir kez daha çalış
  // GDPR "yerel verileri sil" sırasında sync re-insert etmesin (wipe yarışı).
  static bool wiping = false;

  static const _pollInterval = Duration(minutes: 1);

  /// Push (family_activity / sync_nudge) tetiklediğinde çağrılır: ~1.2 sn pencerede
  /// gelen ardışık nudge'ları TEK syncAll'a indirger (X hızlı ardışık düzenleme
  /// yaparsa Y'de tekrar tekrar sync olmasın).
  void requestSyncSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1200), () => syncAll());
  }

  SyncService(this._ref) {
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) syncAll();
    });
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  void _startPolling() {
    _poll?.cancel();
    // Periyodik tur YALNIZ paylaşımlı bebekleri çeker: tek kullanıcıda başka yazan
    // olmadığından periyodik pull gereksizdir (yükleme zaten yazınca olur). Böylece
    // tek kullanıcı için arka planda hiç ağ isteği gitmez.
    _poll = Timer.periodic(_pollInterval, (_) => syncAll(sharedOnly: true));
  }

  /// Öne gelince hemen eşitle + yoklamayı sürdür; arka plana inince yoklamayı
  /// durdur (pil/veri tasarrufu — gelince zaten taze çekilecek).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      syncAll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// [sharedOnly] true ise yalnız paylaşımlı (member_count>1) bebekler senkronlanır
  /// — periyodik turda kullanılır. Açılış/yazma/bağlantı olaylarında false: tüm
  /// bebekler bir kez senkronlanır (tek kullanıcı verisi de yüklenip çekilsin).
  Future<void> syncAll({bool sharedOnly = false}) async {
    if (wiping) return; // yerel veri siliniyor → re-insert etme (wipe yarışı)
    // Oturum yoksa hiç senkron yok (saf local-first).
    if (!_ref.read(loggedInProvider)) return;
    if (_running) {
      _pending = true; // tur sürüyor → isteği yut yerine kuyruğa al (push nudge kaybolmasın)
      return;
    }
    _running = true;
    try {
      final babies = _ref.read(babyControllerProvider).asData?.value ?? [];
      final repo = _ref.read(recordRepositoryProvider);
      for (final b in babies) {
        if (sharedOnly && !b.isShared) continue; // tek kullanıcı → periyodik atla
        // Per-baby gating (Seçenek 2): paylaşılan bebek sahibin bulutunda → kendi
        // premium'umdan bağımsız senkronla; kendi bebeğim için kendi premium'um gerekir.
        // Free kullanıcının KENDİ bebeklerinin kaydı yalnız yerelde kalır (ağa gitmez).
        if (!_ref.read(babyCloudSyncedProvider(b.id))) continue;
        try {
          await repo.sync(b.id);
        } on DioException catch (e) {
          if (e.response?.statusCode == 403) {
            // Paylaşılan bebeğin bulutu artık yazılamıyor (sahip premium bitti) ya da
            // erişimim kaldırıldı. Bu oturumda bu bebeği "salt-okunur" işaretle (403
            // spam'i dursun, yerel veri korunsun) + bebek listesini tazele: erişim
            // gerçekten kalktıysa pull bebeği düşürüp yerel verisini temizler.
            _ref.read(cloudReadonlyBabiesProvider.notifier).add(b.id);
            unawaited(_ref.read(babyControllerProvider.notifier).refresh());
          }
          // 403 dışı (çevrimdışı/5xx) → yerel korunur, sonra tekrar denenir.
        } catch (_) {
          // Çevrimdışı/sunucu hatası — yerel veri korunur, sonra tekrar denenir.
        }
      }
    } finally {
      _running = false;
    }
    // Tur sırasında istek geldiyse bir kez daha (tam) çek → kaçan değişiklik kalmasın.
    if (_pending) {
      _pending = false;
      await syncAll(sharedOnly: false);
    }
  }

  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(ref);
  ref.onDispose(s.dispose);
  // Bebek listesi gelince (giriş/açılış) ilk eşitleme.
  ref.listen(babyControllerProvider, (_, next) {
    if (next.asData?.value.isNotEmpty ?? false) s.syncAll();
  });
  return s;
});

/// Kayıt ekleme/silme aksiyonları — yerele yaz, sonra arka planda sync.
class RecordActions {
  final Ref _ref;
  RecordActions(this._ref);

  RecordRepository get _repo => _ref.read(recordRepositoryProvider);

  /// [ad] = tamamlanmış kullanıcı kaydı (reklam tetikleyebilir). Süren-sayaç
  /// mutasyonları (başlat/duraklat/meme değiştir) false bırakır.
  Future<void> _saveAndSync(Record r, {bool ad = false}) async {
    await _repo.upsertLocal(r);
    _ref.invalidate(presentTypesProvider(r.baby)); // yeni tip → filtre tazelensin
    unawaited(_ref.read(syncServiceProvider).syncAll());
    if (ad) {
      unawaited(AdService.instance.onRecordSaved(
        isPremium: _ref.read(isPremiumProvider),
        suppress: _suppressAd(r),
      ));
      // İçeriksiz analitik: yalnız kayıt türü (bebek adı/değer/tarih GÖNDERME).
      unawaited(AnalyticsService.instance.log('record_added', {
        'record_type': r.type.name,
      }));
    }
  }

  /// Reklamı uygunsuz anlarda sustur: sessiz saat penceresi ya da SÜREN bir
  /// uyku/emzirme sayacı varken. Az önce durdurulan kayıt (aynı id) sayaç
  /// sayılmaz — drift stream'i henüz "ongoing=null" yaymamış olabilir.
  bool _suppressAd(Record r) {
    final sleep = _ref.read(ongoingSleepProvider(r.baby));
    final breast = _ref.read(ongoingBreastProvider(r.baby));
    final timerBusy =
        (sleep != null && sleep.id != r.id) || (breast != null && breast.id != r.id);
    return timerBusy || _inQuietHours(_ref.read(quietHoursProvider(r.baby)));
  }

  bool _inQuietHours(QuietHours q) {
    if (!q.enabled) return false;
    final now = DateTime.now();
    final mins = now.hour * 60 + now.minute;
    final s = q.startMin, e = q.endMin;
    if (s == e) return false;
    // Gece yarısını saran aralığı da destekle (ör. 22:00–07:00).
    return s < e ? (mins >= s && mins < e) : (mins >= s || mins < e);
  }

  /// Genel oluştur/güncelle — form tabanlı kayıtlar bunu kullanır
  /// (id korunursa düzenleme, yeni id ise ekleme).
  Future<void> upsert(Record r) => _saveAndSync(r, ad: true);

  Future<void> addDiaper(String babyId, String sub) => _saveAndSync(
        Record(
          id: _uuid.v4(),
          baby: babyId,
          type: RecordType.diaper,
          ts: DateTime.now(),
          data: {'sub': sub},
        ),
        ad: true,
      );

  Future<void> addFeed(String babyId, Map<String, dynamic> data) =>
      _saveAndSync(
        Record(
          id: _uuid.v4(),
          baby: babyId,
          type: RecordType.feed,
          ts: DateTime.now(),
          data: data,
        ),
        ad: true,
      );

  Future<void> startSleep(String babyId) {
    final now = DateTime.now();
    return _saveAndSync(Record(
      id: _uuid.v4(),
      baby: babyId,
      type: RecordType.sleep,
      ts: now,
      data: {'start_ts': now.toUtc().toIso8601String(), 'end_ts': null},
    ));
  }

  Future<void> stopSleep(Record sleep) {
    final now = DateTime.now();
    final start =
        DateTime.tryParse(sleep.data['start_ts'] as String? ?? '')?.toLocal() ??
            sleep.ts;
    return _saveAndSync(
        sleep.copyWith(data: {
          ...sleep.data,
          'end_ts': now.toUtc().toIso8601String(),
          'duration': now.difference(start).inMinutes,
        }),
        ad: true);
  }

  /// Uykuyu elle girilen başlangıç/bitişle tamamla (kaydetmeden önce süre düzenleme).
  Future<void> stopSleepWithTimes(Record sleep, DateTime start, DateTime end) {
    return _saveAndSync(
        sleep.copyWith(ts: start, data: {
          ...sleep.data,
          'start_ts': start.toUtc().toIso8601String(),
          'end_ts': end.toUtc().toIso8601String(),
          'duration': end.difference(start).inMinutes,
        }),
        ad: true);
  }

  // ── Emzirme kronometresi (uyku gibi kalıcı "süren kayıt") ──────────────

  /// Geçen segmenti aktif memenin toplamına ekler ve segment başlangıcını
  /// şimdiye çeker. Sol/sağ geçişinde ve durdurmada kullanılır.
  Map<String, dynamic> _accrueBreast(Map<String, dynamic> data) {
    final now = DateTime.now();
    final d = Map<String, dynamic>.from(data);
    // seg_start_ts null ise (duraklatılmış) eklenecek süre yok.
    final segStart = DateTime.tryParse(data['seg_start_ts'] as String? ?? '')?.toLocal();
    if (segStart != null) {
      final addMs = now.difference(segStart).inMilliseconds.clamp(0, 24 * 3600 * 1000);
      final side = data['side'] == 'right' ? 'right' : 'left';
      final key = side == 'right' ? 'right_ms' : 'left_ms';
      d[key] = ((data[key] as num?) ?? 0) + addMs;
    }
    d['seg_start_ts'] = now.toUtc().toIso8601String();
    return d;
  }

  /// Emzirmeyi başlat — seçilen memeyle süren kayıt oluşturur.
  Future<void> startBreast(String babyId, String side) {
    final now = DateTime.now();
    final s = side == 'right' ? 'right' : 'left';
    return _saveAndSync(Record(
      id: _uuid.v4(),
      baby: babyId,
      type: RecordType.feed,
      ts: now,
      data: {
        'sub': 'breast',
        'start_ts': now.toUtc().toIso8601String(),
        'end_ts': null,
        'side': s,
        'seg_start_ts': now.toUtc().toIso8601String(),
        'left_ms': 0,
        'right_ms': 0,
      },
    ));
  }

  /// Aktif memeyi değiştir (geçen süre eski memeye yazılır).
  Future<void> switchBreastSide(Record r, String side) {
    final s = side == 'right' ? 'right' : 'left';
    if (r.data['side'] == s) return Future.value();
    final d = _accrueBreast(r.data);
    d['side'] = s;
    return _saveAndSync(r.copyWith(data: d));
  }

  /// Sayacı duraklat (süre eski memeye yazılır, seg sıfırlanır). Kayıt açık kalır.
  Future<void> pauseBreast(Record r) {
    if (r.data['paused'] == true) return Future.value();
    final d = _accrueBreast(r.data);
    d['seg_start_ts'] = null; // duraklatıldı → sayma dursun
    d['paused'] = true;
    return _saveAndSync(r.copyWith(data: d));
  }

  /// Duraklatılmış sayaca devam et.
  Future<void> resumeBreast(Record r) {
    if (r.data['paused'] != true) return Future.value();
    final d = Map<String, dynamic>.from(r.data);
    d['paused'] = false;
    d['seg_start_ts'] = DateTime.now().toUtc().toIso8601String();
    return _saveAndSync(r.copyWith(data: d));
  }

  /// Emzirmeyi durdur — süreleri dakikaya çevirip kaydı tamamlar.
  Future<void> stopBreast(Record r) {
    final now = DateTime.now();
    final d = _accrueBreast(r.data);
    d['end_ts'] = now.toUtc().toIso8601String();
    d.remove('paused');
    d['left_min'] = (((d['left_ms'] as num?) ?? 0) / 60000).round();
    d['right_min'] = (((d['right_ms'] as num?) ?? 0) / 60000).round();
    return _saveAndSync(r.copyWith(data: d), ad: true);
  }

  /// Emzirmeyi elle girilen dakikalarla tamamla (kaydetmeden önce süre düzenleme).
  Future<void> stopBreastWithMinutes(Record r, num leftMin, num rightMin) {
    final now = DateTime.now();
    final d = Map<String, dynamic>.from(r.data);
    d['end_ts'] = now.toUtc().toIso8601String();
    d['seg_start_ts'] = null;
    d.remove('paused');
    d['left_min'] = leftMin;
    d['right_min'] = rightMin;
    d['left_ms'] = (leftMin * 60000).round();
    d['right_ms'] = (rightMin * 60000).round();
    return _saveAndSync(r.copyWith(data: d), ad: true);
  }

  Future<void> delete(String id) async {
    await _repo.softDeleteLocal(id);
    unawaited(_ref.read(syncServiceProvider).syncAll());
  }
}

final recordActionsProvider = Provider<RecordActions>((ref) => RecordActions(ref));
