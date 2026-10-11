import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/health_repository.dart';
import 'baby_controller.dart';
import 'family_settings.dart';

/// J12 (INCELEME-2): kesin alarm izni SONRADAN verilince (M4 diyaloğu /
/// Bildirimler ayarı) o ana dek inexact kurulmuş planlar yeniden kurulsun:
/// - beslenme hatırlatıcısı: yerel ayar aynı değerle YENİ örnek olarak yazılır →
///   `_BabyNotifSync` (`feedReminderProvider`) yeniden kurar (artık exact);
/// - ilaç dozları: `medicationPlansProvider` yenilenir → `_MedNotifSync`
///   `syncMedicationPlans` ile planları iptal edip yeniden kurar.
/// [babyId] verilmezse listedeki tüm bebekler.
Future<void> resyncAfterExactAlarmGranted(WidgetRef ref, {String? babyId}) async {
  final ids = babyId != null
      ? [babyId]
      : (ref.read(babyControllerProvider).asData?.value.map((b) => b.id).toList() ??
          const <String>[]);
  final store = ref.read(feedReminderStoreProvider.notifier);
  for (final id in ids) {
    final cfg = ref.read(feedReminderStoreProvider)[id];
    if (cfg != null) await store.set(id, cfg.copyWith());
    ref.invalidate(medicationPlansProvider(id));
  }
}
