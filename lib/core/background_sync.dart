import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../data/record_repository.dart';
import '../data/sync_gate.dart';
import '../features/auth/auth_controller.dart';
import '../features/babies/baby_controller.dart';

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
    }
  } catch (_) {
    // Auth/baby çözülemedi → sessiz; bir sonraki turda tekrar denenir.
  } finally {
    container.dispose();
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
