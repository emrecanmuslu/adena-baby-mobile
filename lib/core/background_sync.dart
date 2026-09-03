import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../data/feed_reminder_cache.dart';
import '../data/record_repository.dart';
import '../data/sync_gate.dart';
import '../features/auth/auth_controller.dart';
import '../features/babies/baby_controller.dart';
import '../features/babies/family_settings.dart';
import '../models/baby.dart';
import 'fw_trace.dart'; // 🧹 TANI-GEÇİCİ (sorun çözülünce kaldır)
import '../models/record.dart';
import 'db_watchdog.dart';
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
  // Turun başladığını KALICI olarak işaretle: bu isolate ön planla bellek
  // paylaşmadığı için, ön plandaki [DbWatchdog] raporuna "son BGTask turu ne
  // zaman/nasıl bitti" bilgisini ancak böyle taşıyabiliyoruz. Tur ortada
  // kalırsa değer 'başladı' olarak kalır → arıza ile turun bağı görünür.
  await DbWatchdog.markBackgroundSync('başladı');
  // NOT: Bu isolate'in AppDatabase'i KENDİ sqlite bağlantısını açar
  // (shareAcrossIsolates kapalı) → aşağıdaki container.dispose() → db.close()
  // ön plandaki bağlantıya ARTIK dokunmaz. Bkz. AppDatabase._open.
  final container = ProviderContainer();
  var outcome = 'bitti';
  try {
    // Oturum çözülene kadar bekle; yoksa hiç senkron yok (saf local-first).
    await container.read(authControllerProvider.future);
    if (!container.read(loggedInProvider)) return;
    final babies = await container.read(babyControllerProvider.future);
    final repo = container.read(recordRepositoryProvider);
    for (final b in babies) {
      if (!b.isShared) continue; // yalnız paylaşımlı bebek
      try {
        await repo.sync(b.id);
      } catch (_) {
        // 403 (erişim/grace) / çevrimdışı / 5xx → yerel korunur, sonraki tur tekrar.
      }
      // Senkron sonrası (push düşse bile) widget'ı + sonraki-beslenme bildirimini
      // taze veriyle yeniden kur: başka cihazın eklediği kayda göre HER İKİ
      // platformda en geç bu turda (≈30 dk) doğru zamana kayar. Sync hata verse
      // de yereldeki veriyle çalışır (zararsız, idempotent).
      if (!b.isExpecting) await _refreshFeedState(repo, b);
    }
  } catch (_) {
    // Auth/baby çözülemedi → sessiz; bir sonraki turda tekrar denenir.
    outcome = 'hata';
  } finally {
    container.dispose();
    await DbWatchdog.markBackgroundSync(outcome);
  }
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
  if (snap == null) {
    // 🧹 TANI-GEÇİCİ (kaldırılacak): bu tur widget'a dokunmadı → değer bayat kalır.
    await FwTrace.add(source: 'bgsync', action: 'skip_nosnap', babyId: b.id);
    return;
  }
  // Ön planla (_WidgetSync / ana sayfa kartı) BİREBİR aynı kural: hatırlatıcı
  // kapalıysa tahmin varsayılana düşer. nextFeedEstimate/lastFeedAt zaten baz
  // türü filtresini uygular (son MAMA / son anne sütü çapası).
  final cfg = snap.toConfig().effectiveForEstimate;
  final next = nextFeedEstimate(cfg, recs);
  final last = lastFeedAt(cfg, recs);
  // 🧹 TANI-GEÇİCİ (kaldırılacak): bu turun KULLANDIĞI efektif ayar. interval=120 +
  // enabled=false satırı, "3 saatlik ayar 2 saate düştü"nün doğrudan kanıtıdır.
  await FwTrace.add(
      source: 'bgsync',
      action: next == null ? 'skip_nolast' : 'write',
      babyId: b.id,
      enabled: snap.enabled,
      interval: cfg.intervalMin,
      base: cfg.baseType,
      last: last,
      next: next);
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
