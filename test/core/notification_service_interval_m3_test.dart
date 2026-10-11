import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/models/reminder.dart';

class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final Map<int, PendingNotificationRequest> scheduled = {};
  final List<Duration> intervals = [];

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
  Future<void> cancel({required int id, String? tag}) async => scheduled.remove(id);

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
  }) async =>
      scheduled[id] = PendingNotificationRequest(id, title, body, payload);

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
    intervals.add(repeatDurationInterval);
    scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlugin: ${invocation.memberName}');
}

Reminder _interval(int id, int everyMin) => Reminder(
      id: id,
      type: 'custom',
      schedule: {'repeat': 'interval', 'every_min': everyMin, 'title': 'T$id'},
      enabled: true,
      createdAt: DateTime(2026, 1, 1),
    );

/// M3 — periyodik özel hatırlatıcının aralığı KALICI: süreç yeniden başlayıp
/// (yeni NotificationService) bekleyen plan dururken aralık değiştiyse yeniden
/// kurulur; değişmediyse tetik zamanı korunur (yeniden kurulmaz).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('aralık değişmedi + yeni süreç → yeniden kurulmaz', () async {
    final plugin = _FakePlugin();
    await NotificationService.withPlugin(plugin).sync([_interval(7, 15)], allActiveIds: () async => {7});
    expect(plugin.intervals, hasLength(1));
    // "Süreç yeniden başladı": yeni servis örneği, OS'teki bekleyen plan duruyor.
    await NotificationService.withPlugin(plugin).sync([_interval(7, 15)], allActiveIds: () async => {7});
    expect(plugin.intervals, hasLength(1), reason: 'tetik zamanı korunmalı');
  });

  test('aralık değişti + yeni süreç → yeni aralıkla yeniden kurulur', () async {
    final plugin = _FakePlugin();
    await NotificationService.withPlugin(plugin).sync([_interval(7, 15)], allActiveIds: () async => {7});
    await NotificationService.withPlugin(plugin).sync([_interval(7, 30)], allActiveIds: () async => {7});
    expect(plugin.intervals, hasLength(2));
    expect(plugin.intervals.last, const Duration(minutes: 30));
  });
}
