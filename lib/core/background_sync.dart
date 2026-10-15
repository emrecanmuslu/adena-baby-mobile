import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'i18n_warm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../data/feed_reminder_cache.dart';
import '../data/health_repository.dart';
import '../data/local_session.dart';
import '../data/record_repository.dart';
import '../data/sync_gate.dart';
import '../features/auth/auth_controller.dart';
import '../data/baby_repository.dart';
import '../features/babies/family_settings.dart';
import '../features/health/med_scheduler_sync.dart';
import '../features/records/record_controller.dart' show syncServiceProvider;
import 'db_owner_gate.dart';
import 'medication/med_scheduler.dart';
import '../models/baby.dart';
import '../models/record.dart';
import 'db_watchdog.dart';
import 'providers.dart';
import 'notification_service.dart';
import 'widget_service.dart';

/// Periyodik arka plan görev kimliği — iOS Info.plist
/// `BGTaskSchedulerPermittedIdentifiers` + AppDelegate kaydıyla BİREBİR aynı olmalı.
const bgSyncTaskId = 'com.adenababy.bgSync';

/// workmanager arka plan giriş noktası (TOP-LEVEL + vm:entry-point şart).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await runBackgroundSync();
      return true;
    } catch (_) {
      return false; // başarısız → sistem ileride tekrar dener
    }
  });
}

/// Arka plan turu zaman aşımları (O36) — giriş noktasına/platforma göre.
/// `Future.timeout` işi İPTAL ETMEZ: aşımda tur "zaman aşımı" ile biter ve
/// container dispose edilir; süren bir `repo.sync` kapalı DB'ye düşüp hata alır
/// (yutulur). Kayıt senkronunda sayfa yazımı + cursor TEK transaction'da olduğu
/// için kesinti "cursor ilerledi, kayıt yazılmadı" kaybı doğurmaz.
/// Android workmanager: sistem sınırı 10 dk → 4 dk.
const bgSyncTimeoutAndroid = Duration(minutes: 4);
/// iOS BGAppRefreshTask: sistem ~30 sn verir → 25 sn.
const bgSyncTimeoutIos = Duration(seconds: 25);
/// FCM arka plan işleyicisi (sync_nudge): her iki platformda ~30 sn → 20 sn.
const bgPushTimeout = Duration(seconds: 20);

/// Watchdog damgaları (bkz. DbWatchdog.markBackgroundSync).
const bgOutcomeDone = 'bitti';
const bgOutcomeError = 'hata';
const bgOutcomeTimeout = 'zaman aşımı';
/// Refresh reddi → token silindi; ön plan öne gelişte zorunlu çıkışı uygular (O1).
const bgOutcomeNoSession = 'oturum yok';
/// Tur aynı süreçteki canlı ön plan isolate'ine devredildi (DbOwnerGate).
const bgOutcomeDelegated = 'ön plana devredildi';

/// DbOwnerGate iş kodları: periyodik tur (yalnız paylaşımlı bebekler) / push
/// kaynaklı tek-bebek turu.
const bgOpPeriodic = 'periodic';
const bgOpPush = 'push';

/// Uygulama KAPALI/ölü iken bile paylaşımlı bebekleri senkronlar — push düşmese
/// de yarım saatte bir yerel veri (drift) tazelensin (kullanıcı açınca güncel olsun).
///
/// Yalnız PAYLAŞIMLI bebekler (member_count>1): tek kullanıcıda başka yazan
/// olmadığından periyodik pull gereksiz. Sync ucu erişimi zaten zorlar (free üye /
/// grace → 403 yutulur). `SyncService` KULLANILMAZ (ctor'u WidgetsBinding + Timer
/// kurar; arka plan isolate'ta uygun değil) — bunun yerine standalone
/// `ProviderContainer` ile repo.sync doğrudan sürülür.
Future<void> runBackgroundSync() async {
  WidgetsFlutterBinding.ensureInitialized();
  await warmI18nFromCache(); // M7: bg turunun kurduğu hatırlatıcı metinleri
  // Turun başladığını KALICI olarak işaretle: bu isolate ön planla bellek
  // paylaşmadığı için, ön plandaki [DbWatchdog] raporuna "son BGTask turu ne
  // zaman/nasıl bitti" bilgisini ancak böyle taşıyabiliyoruz. Tur ortada
  // kalırsa değer 'başladı' olarak kalır → arıza ile turun bağı görünür.
  await DbWatchdog.markBackgroundSync('başladı');
  // Tek yazar: ön plan isolate'i bu süreçte canlıysa (iOS'ta uygulama arka
  // planda askıdayken BGTask) işi ona devret — ikinci bir sqlite bağlantısı
  // AÇMA (SQLITE_BUSY_SNAPSHOT 517 kökü; bkz. DbOwnerGate).
  final delegated = await DbOwnerGate.delegate(bgOpPeriodic,
      timeout: (Platform.isIOS ? bgSyncTimeoutIos : bgSyncTimeoutAndroid) -
          DbOwnerGate.pingTimeout);
  if (delegated != DelegateResult.noOwner) {
    await DbWatchdog.markBackgroundSync('$bgOutcomeDelegated (${delegated.name})');
    return;
  }
  // K9: yerel oturum bayrakları (misafir, import/premiumSynced kümeleri) bu
  // isolate'te de yüklü olsun — activeAccountId kapsamı ve LocalSession
  // yazımları yüklenmemiş bellekle çalışmasın. Zaman aşımlı (Keychain göçü
  // takılırsa tur yine sürer; O35 yazımları zaten diskle birleştirir).
  await ensureLocalSessionForBackground();
  // NOT: Bu isolate'in AppDatabase'i KENDİ sqlite bağlantısını açar
  // (shareAcrossIsolates kapalı) → container.dispose() → db.close() ön plandaki
  // bağlantıya ARTIK dokunmaz. Bkz. AppDatabase._open.
  final container = ProviderContainer(overrides: [
    runningInBackgroundProvider.overrideWithValue(true),
  ]);
  final outcome = await runBackgroundSyncWith(container,
      timeout: Platform.isIOS ? bgSyncTimeoutIos : bgSyncTimeoutAndroid);
  // Damga yalnız tüm iş bittikten (ya da zaman aşımından) SONRA.
  await DbWatchdog.markBackgroundSync(outcome);
}

/// Tur gövdesi — test edilebilir (container dışarıdan). [onlyBabyId] verilirse
/// (FCM sync_nudge) yalnız o bebek; verilmezse tüm PAYLAŞIMLI bebekler.
///
/// O36: BabyController HİÇ kurulmaz (build'i `_pull`'u — GET /babies, erişim
/// doğrulama GET'leri, `cloudSyncEnabledProvider` üzerinden GET
/// /auth/me/subscription, child purge — unawaited başlatıyordu); bebek listesi
/// yerel DB'den (`babyRepository.getAll`) okunur, paylaşım ayrımı yerel
/// `member_count`/`my_role` kolonlarıyla yapılır. Geriye izlenecek unawaited iş
/// kalmaz; `container.dispose()` her durumda EN SONDA. Döner: watchdog damgası.
Future<String> runBackgroundSyncWith(
  ProviderContainer container, {
  required Duration timeout,
  String? onlyBabyId,
}) async {
  var outcome = bgOutcomeDone;
  try {
    final sessionLost =
        await _syncBabies(container, onlyBabyId: onlyBabyId).timeout(timeout);
    if (sessionLost) outcome = bgOutcomeNoSession;
  } on TimeoutException {
    outcome = bgOutcomeTimeout;
  } catch (_) {
    // Auth/bebek çözülemedi → sessiz; bir sonraki turda tekrar denenir.
    outcome = bgOutcomeError;
  } finally {
    container.dispose();
  }
  return outcome;
}

/// Döner: oturum sunucu tarafından reddedildi mi (401 → refresh reddi, token
/// silindi). Bg'de başka iş yapılmaz; ön plan öne gelişte `verifySession` ile
/// zorunlu çıkışı uygular.
/// İlaç v2 (M6) — bg turunun ilaç adımı. Test kancası: [bgMedHook].
class BgMedHook {
  /// Bir bebeğin ilaç planlarını sunucuyla eşitler.
  final Future<void> Function(ProviderContainer c, String babyId) syncPlans;
  /// İlaç bildirimlerini (TÜM doğmuş bebekler) DB'den yeniden kurar.
  final Future<void> Function(ProviderContainer c, List<Baby> babies) rebuild;
  const BgMedHook({required this.syncPlans, required this.rebuild});
}

@visibleForTesting
BgMedHook? bgMedHook;

final _defaultBgMed = BgMedHook(
  syncPlans: (c, id) async {
    await c.read(healthRepositoryProvider).syncMedicationPlans(id);
  },
  rebuild: (c, list) => MedicationScheduler.instance.rebuild(
    medSchedLoader(
      babies: () async => list,
      health: c.read(healthRepositoryProvider),
      records: c.read(recordRepositoryProvider),
    ),
    reason: 'bg',
  ),
);

Future<bool> _syncBabies(ProviderContainer container,
    {String? onlyBabyId}) async {
  var sessionLost = false;
  // Oturum çözülene kadar bekle; yoksa hiç senkron yok (saf local-first).
  await container.read(authControllerProvider.future);
  if (!container.read(loggedInProvider)) return false;
  final acct = container.read(activeAccountIdProvider);
  final babies =
      await container.read(babyRepositoryProvider).getAll(accountId: acct);
  final repo = container.read(recordRepositoryProvider);
  final med = bgMedHook ?? _defaultBgMed;
  for (final b in babies) {
    if (onlyBabyId != null) {
      if (b.id != onlyBabyId) continue;
    } else if (!b.isShared) {
      continue; // periyodik tur: yalnız paylaşımlı bebek
    }
    if (b.isExpecting) continue; // bekleme modunda kayıt/beslenme işi yok
    // İlaç v2 (M6): başka üyenin plan değişikliği (sil/duraklat/saat) uygulama
    // açılmadan da bu cihaza insin. Hata turu düşürmez (yerel planlarla kurulur).
    try {
      await med.syncPlans(container, b.id);
    } catch (_) {}
    try {
      await repo.sync(b.id);
    } on DioException catch (e) {
      // 401 = refresh reddi sonrası (token silindi) → oturum yok damgası.
      // 403 (erişim/grace) / çevrimdışı / 5xx → yerel korunur, sonraki tur
      // tekrar. Bg'de purge/salt-okunur işareti YAZILMAZ (ön plan pull'u karar verir).
      if (e.response?.statusCode == 401) sessionLost = true;
    } catch (_) {}
  }
  await _refreshAfterSync(container, babies, onlyBabyId: onlyBabyId);
  return sessionLost;
}

/// Senkron sonrası (push düşse bile) widget'ı + sonraki-beslenme bildirimini
/// taze veriyle yeniden kur: başka cihazın eklediği kayda göre HER İKİ
/// platformda en geç bu turda (≈30 dk) doğru zamana kayar. Sync hata verse de
/// yereldeki veriyle çalışır (zararsız, idempotent). Ardından ilaç bildirimleri.
Future<void> _refreshAfterSync(ProviderContainer container, List<Baby> babies,
    {String? onlyBabyId}) async {
  final repo = container.read(recordRepositoryProvider);
  for (final b in babies) {
    if (onlyBabyId != null) {
      if (b.id != onlyBabyId) continue;
    } else if (!b.isShared) {
      continue;
    }
    if (b.isExpecting) continue;
    await _refreshFeedState(repo, b);
  }
  // İlaç v2 (M1/M6): senkronla gelen kayıt ve plan değişikliklerine göre ilaç
  // bildirimlerini (TÜM doğmuş bebekler — pencere de kayar) yeniden kur.
  try {
    await (bgMedHook ?? _defaultBgMed)
        .rebuild(container, [for (final b in babies) if (!b.isExpecting) b]);
  } catch (_) {}
}

/// Ön plan tarafı (DbOwnerGate işleyicisi): arka plan girişinin devrettiği turu
/// ön planın KENDİ (tek) DB bağlantısıyla yapar. Senkronu [SyncService]
/// üstlenir (çakışan tur koruması + "Senkron sorunu" durumu dahil); ardından
/// arka plan turunun yaptığı widget / hatırlatıcı / ilaç tazelemesi.
Future<void> runDelegatedSync(ProviderContainer container, String op,
    {String? babyId}) async {
  final onlyBabyId = op == bgOpPush ? babyId : null;
  await container.read(syncServiceProvider).syncAll(sharedOnly: onlyBabyId == null);
  if (!container.read(loggedInProvider)) return;
  final babies = await container
      .read(babyRepositoryProvider)
      .getAll(accountId: container.read(activeAccountIdProvider));
  await _refreshAfterSync(container, babies, onlyBabyId: onlyBabyId);
}

/// Bir bebeğin sonraki-beslenme widget'ını + yerel beslenme hatırlatıcısını
/// arka plan isolate'ında taze drift verisiyle yeniden kurar (foreground'daki
/// _WidgetSync + _syncFeed ile aynı sonuç). Riverpod/drift'e erişim olmadığından
/// hatırlatıcı parametreleri ön planda yazılan [FeedReminderCache] snapshot'ından
/// alınır (widget'ın push'tan güncellenmesiyle birebir aynı desen).
Future<void> _refreshFeedState(RecordRepository repo, Baby b) async {
  List<Record> recs;
  try {
    recs = await repo.watchRecent(b.id).first;
  } catch (_) {
    return; // yerel kayıt okunamadı → bu turda dokunma
  }
  final snap = await FeedReminderCache().read(b.id);
  // Snapshot okunamadıysa kullanıcının aralığını/baz türünü BİLMİYORUZ. Eskiden
  // burada varsayılana (her 2 saat · tüm beslenmeler) düşülüyor ve bu değer hem
  // widget'a hem App Group'a (`feed_interval_default`) yazılıyordu → 3 saatlik
  // ayarı olan kullanıcıda widget sessizce 2 saate kayıyordu. Artık dokunmuyoruz:
  // widget ön planda yazılan son (doğru) değerinde kalır.
  if (snap == null) return;
  // Ön planla (_WidgetSync / ana sayfa kartı) BİREBİR aynı kural: hatırlatıcı
  // kapalıysa tahmin varsayılana düşer. nextFeedEstimate/lastFeedAt zaten baz
  // türü filtresini uygular (son MAMA / son anne sütü çapası).
  final cfg = snap.toConfig().effectiveForEstimate;
  final next = nextFeedEstimate(cfg, recs);
  final last = lastFeedAt(cfg, recs);
  // Yalnız per-baby anahtarları yaz (publishOne); kullanıcının aktif-bebek seçimini
  // (active_id/baby_name/next_feed_ms) EZME — onu yalnız ön plan publishAll yönetir.
  await WidgetService.publishOne(
      babyId: b.id,
      babyName: b.name,
      nextFeed: next,
      lastFeed: last,
      intervalMin: cfg.intervalMin);
  // Bildirim yalnız hatırlatıcı açıksa yeniden planlanır (scheduleFeedReminder
  // aynı id'yi iptal edip yeniden kurar → çift olmaz, idempotent).
  if (snap.enabled) {
    await NotificationService.instance.scheduleFeedReminder(
      enabled: true,
      nextTime: next,
      preMin: snap.preMin,
      slot: snap.slot,
      babyName: b.name,
      sound: snap.sound,
      quiet: snap.quiet,
      // Eskiden geçilmiyordu → varsayılan `true` ile, kullanıcı "Kaydı unuttun mu?"
      // dürtmesini KAPATMIŞ olsa bile her bg turunda yeniden kuruluyordu.
      forgot: snap.forgot,
    );
  }
}

/// V5: `access_removed` push'undan sonra (arka plan) ilaç bildirimlerini yerel
/// DB'den — erişimi kalkan bebek planlayıcıda atlanarak — yeniden kurar; ağ yok.
/// Bayat önbellekle kaçan girdileri planlayıcının yetim temizliği yakalar.
/// V24: [revokedBabyId] verilirse önce o bebeğin özel/randevu hatırlatıcıları
/// (yerel `localReminders` id'leri) iptal edilir — veri temizliği ön planda kalır.
Future<void> rebuildMedicationFromPush({String? revokedBabyId}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureLocalSessionForBackground(); // K9
  final container = ProviderContainer(overrides: [
    runningInBackgroundProvider.overrideWithValue(true),
  ]);
  await rebuildMedicationFromPushWith(container, revokedBabyId: revokedBabyId);
}

/// [rebuildMedicationFromPush] gövdesi — test edilebilir (container dışarıdan);
/// container'ı her durumda kapatır.
@visibleForTesting
Future<void> rebuildMedicationFromPushWith(ProviderContainer container,
    {String? revokedBabyId}) async {
  try {
    if (revokedBabyId != null) {
      try {
        final ids =
            await container.read(healthRepositoryProvider).reminderIdsForBaby(revokedBabyId);
        for (final id in ids) {
          await NotificationService.instance.cancelId(id);
        }
      } catch (_) {}
    }
    await container.read(authControllerProvider.future);
    if (!container.read(loggedInProvider)) return;
    final acct = container.read(activeAccountIdProvider);
    final babies =
        await container.read(babyRepositoryProvider).getAll(accountId: acct);
    await (bgMedHook ?? _defaultBgMed)
        .rebuild(container, [for (final b in babies) if (!b.isExpecting) b])
        .timeout(bgPushTimeout);
  } catch (_) {
  } finally {
    container.dispose();
  }
}

/// 'sync_nudge' push'u geldiğinde (başka üye kaydı GÜNCELLEDİ/SİLDİ) uygulama
/// arka plandayken/kapalıyken TEK bebeği hemen senkronlar + widget/hatırlatıcıyı
/// tazeler — 30 dk'lık periyodik turu beklemeden. `runBackgroundSync` ile AYNI
/// güvenli desen: push payload'ındaki zamanlamaya GÜVENMEZ (sync_nudge'da zaten
/// yok), yerelde TAZE senkronladıktan sonra drift'ten yeniden hesaplar — "yanlış
/// kayda göre hatırlatıcı kurulur" riski olmaz. `push_service.dart`'ın FCM arka
/// plan işleyicisinden çağrılır; ön plandayken çağrılmaz (orada canlı Riverpod
/// ağacı zaten `requestSyncSoon()` ile aynı işi yapıyor, bkz. main.dart).
Future<void> refreshBabyFeedStateFromPush(String babyId) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tek yazar: aynı süreçte canlı ön plan varsa ona devret (bkz. DbOwnerGate).
  // FCM işleyicisi ön plan isolate'inde çalışıyorsa port kendine gider — yine
  // tek bağlantı kullanılır.
  final delegated = await DbOwnerGate.delegate(bgOpPush,
      babyId: babyId, timeout: bgPushTimeout - DbOwnerGate.pingTimeout);
  if (delegated != DelegateResult.noOwner) return;
  await ensureLocalSessionForBackground(); // K9
  final container = ProviderContainer(overrides: [
    runningInBackgroundProvider.overrideWithValue(true),
  ]);
  // O36: aynı gövde, tek bebek, FCM süresine uygun zaman aşımı; dispose en sonda.
  await runBackgroundSyncWith(container,
      timeout: bgPushTimeout, onlyBabyId: babyId);
}

/// Arka plan isolate'i için [LocalSession.ensureLoaded] — zaman aşımlı ve
/// hatasız (K9). Ön planın main()'deki `_step` sarmalayıcısına denk.
Future<void> ensureLocalSessionForBackground(
    {Duration timeout = const Duration(seconds: 5)}) async {
  if (LocalSession.loaded) return;
  try {
    await LocalSession.ensureLoaded().timeout(timeout);
  } catch (_) {
    // Yükleme takıldı → tur varsayılanlarla sürer (yazımlar diskle birleşir).
  }
}

/// Periyodik arka plan sync'i kaydeder (idempotent). main()'de bir kez çağrılır.
/// Android: 30 dk (min 15). iOS: sistem zamanlamayı kendi yönetir (fırsatçı);
/// sıklık AppDelegate'te tanımlı, burada yalnız tetiklenir.
Future<void> registerBackgroundSync() async {
  try {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      bgSyncTaskId,
      bgSyncTaskId,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // Platform desteklemiyor / kayıt hatası → uygulama yine çalışır.
  }
}
