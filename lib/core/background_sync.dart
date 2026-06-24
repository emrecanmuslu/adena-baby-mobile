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
import '../models/feed_reminder.dart';
import '../models/record.dart';
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
  final container = ProviderContainer();
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
  } finally {
    container.dispose();
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
  final cfg = snap == null
      ? const FeedReminderConfig()
      : FeedReminderConfig(
          enabled: snap.enabled,
          intervalMin: snap.intervalMin,
          baseType: snap.baseType,
          preMin: snap.preMin,
          soundEnabled: snap.sound,
        );
  // nextFeedEstimate hatırlatıcı kapalıyken de varsayılan aralıkla widget için
  // hesaplar (ana sayfa kartı/_WidgetSync ile aynı mantık).
  final next = nextFeedEstimate(cfg.enabled ? cfg : const FeedReminderConfig(), recs);
  // Yalnız per-baby anahtarları yaz (publishOne); kullanıcının aktif-bebek seçimini
  // (active_id/baby_name/next_feed_ms) EZME — onu yalnız ön plan publishAll yönetir.
  await WidgetService.publishOne(
      babyId: b.id, babyName: b.name, nextFeed: next, intervalMin: cfg.intervalMin);
  // Bildirim yalnız hatırlatıcı açıksa yeniden planlanır (scheduleFeedReminder
  // aynı id'yi iptal edip yeniden kurar → çift olmaz, idempotent).
  if (snap != null && snap.enabled) {
    await NotificationService.instance.scheduleFeedReminder(
      enabled: true,
      nextTime: next,
      preMin: snap.preMin,
      slot: snap.slot,
      babyName: b.name,
      sound: snap.sound,
      quiet: snap.quiet,
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
