import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/models/reminder.dart';

/// O14/O15 — periyodik bildirimler her sync'te sıfırlanmasın; bebek silinince/
/// erişim kalkınca o bebeğin TÜM planlı bildirimleri iptal edilsin.
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final Map<int, PendingNotificationRequest> scheduled = {};
  int periodicCalls = 0;
  int cancelCalls = 0;
  final List<Duration> intervals = [];

  Set<int> get ids => scheduled.keys.toSet();

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
          T extends FlutterLocalNotificationsPlatform>() =>
      null;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      scheduled.values.toList();

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelCalls++;
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();

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
  }) async {
    scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  }

  @override
  Future<void> periodicallyShowWithDuration({
    required int id,
    required Duration repeatDurationInterval,
    required NotificationDetails notificationDetails,
    String? title,
    String? body,
    AndroidScheduleMode androidScheduleMode = AndroidScheduleMode.exact,
    String? payload,
  }) async {
    periodicCalls++;
    intervals.add(repeatDurationInterval);
    scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlugin: ${invocation.memberName}');
}

Reminder _interval(int id, int everyMin, {bool enabled = true}) => Reminder(
      id: id,
      type: 'custom',
      schedule: {'repeat': 'interval', 'every_min': everyMin, 'title': 'T$id'},
      enabled: enabled,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlugin plugin;
  late NotificationService svc;

  setUp(() {
    SharedPreferences.setMockInitialValues({}); // M3: aralık kalıcılığı prefs'te
    plugin = _FakePlugin();
    svc = NotificationService.withPlugin(plugin);
  });

  group('O14 — periyodik dürtmeler rebuild\'de sıfırlanmaz', () {
    test('syncMilestoneCheckReminder: ikinci çağrı mevcut planı korur (yeniden kurmaz)',
        () async {
      await svc.syncMilestoneCheckReminder(enabled: true, slot: 1);
      expect(plugin.periodicCalls, 1);
      await svc.syncMilestoneCheckReminder(enabled: true, slot: 1);
      await svc.syncMilestoneCheckReminder(enabled: true, slot: 1);
      expect(plugin.periodicCalls, 1, reason: '14 günlük sayaç sıfırlanmamalı');
      expect(plugin.ids, {650001});
      await svc.syncMilestoneCheckReminder(enabled: false, slot: 1);
      expect(plugin.ids, isEmpty);
    });

    test('syncToothCheckReminder: aynı', () async {
      await svc.syncToothCheckReminder(enabled: true, slot: 0);
      await svc.syncToothCheckReminder(enabled: true, slot: 0);
      expect(plugin.periodicCalls, 1);
      expect(plugin.ids, {660000});
    });

    test('özel "her X dk" hatırlatıcı: tekrar sync kurulu planı korur; aralık değişince yeniden kurulur',
        () async {
      final list = [_interval(7, 15)];
      await svc.sync(list, allActiveIds: () async => {7});
      await svc.sync(list, allActiveIds: () async => {7});
      expect(plugin.periodicCalls, 1);
      expect(plugin.intervals.single, const Duration(minutes: 15));

      await svc.sync([_interval(7, 30)], allActiveIds: () async => {7});
      expect(plugin.periodicCalls, 2);
      expect(plugin.intervals.last, const Duration(minutes: 30));

      await svc.sync([_interval(7, 30, enabled: false)], allActiveIds: () async => {});
      expect(plugin.ids, isEmpty);
    });
  });

  group('O15 — bebeğin tüm planlı bildirimleri', () {
    // İlaç v2 (A4): ilaç bildirimleri artık bebek bazında planlayıcı defterinden
    // iptal edilir (MedicationScheduler.cancelBaby — med_scheduler_test.dart);
    // eski plan-id aralığı (670000+) planlayıcının tek seferlik göç temizliğinde.
    test('cancelBabyScheduled: slot bazlı tüm id aralıkları', () async {
      await svc.syncMilestoneCheckReminder(enabled: true, slot: 2);
      await svc.syncToothCheckReminder(enabled: true, slot: 2);
      await svc.syncMilestoneCheckReminder(enabled: true, slot: 3); // başka bebek
      // Diğer aralıklara elle bekleyen koy (aşı/atak/büyüme/gebelik/feed/sayaç/ilaç).
      for (final id in [
        610002, 620002, 630002, 640002, // sağlık (slot 2)
        800002, 810002, 820002, 900002, 910002, // beslenme + sayaçlar (slot 2)
        610003, // başka bebek aşı
      ]) {
        plugin.scheduled[id] = PendingNotificationRequest(id, null, null, null);
      }

      await svc.cancelBabyScheduled(slot: 2);

      expect(plugin.ids, {650003, 610003},
          reason: 'yalnız diğer bebeğin (slot 3) bildirimleri kalmalı');
    });
  });
}
