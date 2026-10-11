import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification_service.dart';
import '../../data/cycle_long_answers.dart';
import '../../data/cycle_repository.dart';
import '../babies/notification_sync.dart' show settledListOrNull, settledOrNull;
import 'cycle_engine.dart';

/// Test enjeksiyonu için (prod: tekil örnek).
final notificationServiceProvider =
    Provider<NotificationService>((_) => NotificationService.instance);

/// Adet hatırlatıcılarını (adet yaklaşıyor / doğurganlık / PMS / log) döngü
/// tahminine göre MERKEZİ olarak eşitler (O25). Eskiden yalnız Ayarlar ekranı
/// `syncCycle` çağırıyordu: yeni adet loglanınca "adetin yaklaşıyor" eski
/// günde kalıyor, kayıp/postpartum'a geçince doğurganlık bildirimi iptal
/// edilmiyordu. Görünmez; her zaman ağaçta (bkz. main.dart). Yalnız oturmuş
/// (settled) veriyle çalışır; `syncCycle` idempotent (iptal + yeniden kur).
class CycleNotifSync extends ConsumerWidget {
  const CycleNotifSync({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = settledOrNull(ref.watch(cycleSettingsProvider));
    final entries = settledListOrNull(ref.watch(cycleEntriesProvider));
    if (settings == null || entries == null) return const SizedBox.shrink();
    // B1: bildirimler de uç değer dışlanmış (medyan) tahmine dayanır.
    final status = computeStatus(settings, entries,
        confirmedLongStarts: ref.watch(cycleLongAnswersProvider).confirmedLong);
    ref.read(notificationServiceProvider).syncCycle(
          // Modül kapalıysa hiç hatırlatıcı kalmaz.
          reminders: settings.enabled ? settings.reminders : const {},
          nextPeriod: status.nextPeriod,
          fertileStart: status.upcomingFertileStart,
        );
    return const SizedBox.shrink();
  }
}
