import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/medication/med_scheduler.dart';
import '../../core/notification_service.dart';
import '../../data/health_repository.dart';
import '../../data/notification_prefs.dart';
import '../../data/record_repository.dart';
import '../../models/baby.dart';
import '../babies/baby_controller.dart';
import '../babies/notification_sync.dart'
    show refreshTimezoneAndBump, settledListOrNull, timezoneEpochProvider;
import '../records/record_controller.dart';
import '../settings/notification_prefs_controller.dart';

/// İlaç v2 planlayıcı girdisi — DB'den TAZE (provider önbelleğinden değil):
/// bebekler + her bebeğin planları + son 2 günün kayıtları + tercihler. Ön plan
/// ve arka plan isolate (A5) aynı yükleyiciyi kullanır.
MedSchedLoader medSchedLoader({
  required Future<List<Baby>> Function() babies,
  required HealthRepository health,
  required RecordRepository records,
}) =>
    () async {
      final now = DateTime.now();
      final since = DateTime(now.year, now.month, now.day - 2);
      final out = <MedSchedBaby>[];
      for (final b in await babies()) {
        final plans = await health.medicationPlans(b.id);
        if (plans.isEmpty) continue;
        out.add(MedSchedBaby(
          id: b.id,
          name: b.name,
          expecting: b.isExpecting,
          plans: plans,
          records: await records.watchSince(b.id, since).first,
          recordsSyncedAt: await MedicationScheduler.recordsSyncedAt(b.id),
        ));
      }
      final prefs = NotificationPrefs.instance;
      return MedSchedInput(
        babies: out,
        enabled: await prefs.enabled(NotificationPrefs.medication),
        missedOn: await prefs.enabled(NotificationPrefs.medicationMissed),
      );
    };

/// Ön plan: bebek listesi, planlar, bugün/dün kayıtları ya da tercihler
/// değişince (ve öne gelişte) ilaç bildirimlerini yeniden kurar — kısa
/// gecikmeyle birleştirilmiş tek tur. Görünmez; [FamilyNotificationSync] içinde.
class MedSchedulerSync extends ConsumerStatefulWidget {
  const MedSchedulerSync({super.key});
  @override
  ConsumerState<MedSchedulerSync> createState() => _MedSchedulerSyncState();
}

class _MedSchedulerSyncState extends ConsumerState<MedSchedulerSync> {
  Timer? _debounce;
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: _onResume);

  @override
  void initState() {
    super.initState();
    _life; // dinleyiciyi kur
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _life.dispose();
    super.dispose();
  }

  Future<void> _onResume() async {
    // M17: seyahatte saat dilimi değiştiyse tz.local güncellenir; dozlar zaten
    // cihazın yerel saatinden üretildiği için yeniden kurma doğru saate taşır.
    // V23: değiştiyse diğer günlük hatırlatıcı senkronları da yeniden kurulur.
    await refreshTimezoneAndBump(NotificationService.instance.refreshTimezone,
        () => ref.read(timezoneEpochProvider.notifier).bump());
    if (!mounted) return;
    _request('resume');
  }

  void _request(String reason) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final babies = ref.read(babyControllerProvider).asData?.value;
      if (babies == null) return;
      MedicationScheduler.instance.rebuild(
        medSchedLoader(
          babies: () async => babies,
          health: ref.read(healthRepositoryProvider),
          records: ref.read(recordRepositoryProvider),
        ),
        reason: reason,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final babies = ref.watch(babyControllerProvider).asData?.value ?? const <Baby>[];
    ref.watch(notifPrefProvider(NotificationPrefs.medication));
    ref.watch(notifPrefProvider(NotificationPrefs.medicationMissed));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    var settled = true;
    for (final b in babies) {
      if (settledListOrNull(ref.watch(medicationPlansProvider(b.id))) == null) settled = false;
      // Kayıt değişimi (yerel işaret / senkron) → çözülen dozun bildirimi kalksın.
      for (final d in [today, yesterday]) {
        ref.watch(dayRecordsProvider((babyId: b.id, day: d)));
      }
    }
    // Yalnız oturmuş veriyle (yenileme sırasında bayat liste değil — K5).
    if (settled) _request('change');
    return const SizedBox.shrink();
  }
}
