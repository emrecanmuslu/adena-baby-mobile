import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/medication/med_scheduler.dart';
import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/models/medication_plan.dart';

class _FakeAndroid implements AndroidFlutterLocalNotificationsPlugin {
  final bool canExact;
  _FakeAndroid(this.canExact);
  @override
  Future<bool?> canScheduleExactNotifications() async => canExact;
  @override
  Future<bool?> requestNotificationsPermission() async => true;
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('FakeAndroid: ${i.memberName}');
}

class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final _FakeAndroid android;
  _FakePlugin(this.android);
  final List<AndroidScheduleMode> modes = [];
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;
  @override
  T? resolvePlatformSpecificImplementation<
      T extends FlutterLocalNotificationsPlatform>() {
    if (T == AndroidFlutterLocalNotificationsPlugin) return android as T;
    return null;
  }
  @override
  Future<void> cancel({required int id, String? tag}) async {}
  @override
  Future<void> zonedSchedule({
    required int id,
    required TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async =>
      modes.add(androidScheduleMode);
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('FakePlugin: ${i.memberName}');
}

/// INCELEME-2 J6 — ilaç dozları `_scheduleDaily` ile koşulsuz inexact kuruluyordu;
/// M4 diyaloğu "ilaç … tam saatinde" diye izin istiyordu ama izin verilse de
/// doz bildirimi exact olmuyordu. Artık `_alarmMode()`: izin varsa exact.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // İlaç v2 (A4): günlük tekrar yerine doz başına tek seferlik bildirim
  // (MedicationScheduler); kip kuralı aynı — izin varsa exact.
  Future<List<AndroidScheduleMode>> modesFor(bool canExact) async {
    final plugin = _FakePlugin(_FakeAndroid(canExact));
    final svc = NotificationService.withPlugin(plugin);
    final sched = MedicationScheduler.forTest(svc, now: () => DateTime(2026, 1, 10, 8));
    await sched.rebuild(() async => MedSchedInput(missedOn: false, babies: [
          MedSchedBaby(id: 'b', name: '', records: const [], plans: [
            MedicationPlan(
                id: 1, uuid: 'u1', name: 'D vitamini', dose: '', times: const ['09:00', '21:00'],
                active: true, createdAt: DateTime(2026, 1, 1), startDate: DateTime(2026, 1, 1)),
          ]),
        ]));
    return plugin.modes;
  }

  test('izin var → ilaç dozları exact', () async {
    final modes = await modesFor(true);
    expect(modes, hasLength(15)); // 7 gün × 2 doz + pencere sonu uyarısı
    expect(modes.toSet(), {AndroidScheduleMode.exactAllowWhileIdle});
  });

  test('izin yok → inexact (bildirim kaybolmaz)', () async {
    final modes = await modesFor(false);
    expect(modes, hasLength(15));
    expect(modes.toSet(), {AndroidScheduleMode.inexactAllowWhileIdle});
  });
}
