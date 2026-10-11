import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/notification_service.dart';

/// Android 14+: kesin alarm izni yok → plugin `exact` kurulumda fırlatır
/// (FLN `checkCanScheduleExactAlarms`).
class _FakeAndroid implements AndroidFlutterLocalNotificationsPlugin {
  final bool canExact;
  _FakeAndroid(this.canExact);
  @override
  Future<bool?> canScheduleExactNotifications() async => canExact;
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('FakeAndroid: ${i.memberName}');
}

class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final _FakeAndroid android;
  final bool alwaysThrow;
  _FakePlugin(this.android, {this.alwaysThrow = false});
  AndroidScheduleMode? scheduledMode;
  int? scheduledId;

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
    if (alwaysThrow) throw PlatformException(code: 'boom');
    final exact = androidScheduleMode == AndroidScheduleMode.exact ||
        androidScheduleMode == AndroidScheduleMode.exactAllowWhileIdle;
    if (exact && !android.canExact) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    scheduledMode = androidScheduleMode;
    scheduledId = id;
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('FakePlugin: ${i.memberName}');
}

/// INCELEME-2 J4 (O16 regresyonu) — arka plan "Ertele 10 dk" eylemi kesin alarmla
/// sabit kuruluyordu; Android 14+'ta izin varsayılan ret → plugin fırlatır,
/// erteleme sessizce kaybolurdu. Artık ön planla aynı kural (`alarmModeFor`):
/// izin yoksa inexact; kurulum hatası yutulup loglanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fp = (sound: true, slot: 2, babyName: 'Ada');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('izin yok → inexact ile kurulur, fırlatmaz', () async {
    final plugin = _FakePlugin(_FakeAndroid(false));
    await debugSnoozeFeedInBackground(fp, plugin: plugin);
    expect(plugin.scheduledMode, AndroidScheduleMode.inexactAllowWhileIdle);
    expect(plugin.scheduledId, NotificationService.feedMainIdFor(2));
  });

  test('izin var → exact ile kurulur', () async {
    final plugin = _FakePlugin(_FakeAndroid(true));
    await debugSnoozeFeedInBackground(fp, plugin: plugin);
    expect(plugin.scheduledMode, AndroidScheduleMode.exactAllowWhileIdle);
  });

  test('kurulum hatası isolate\'i düşürmez (yutulur, loglanır)', () async {
    final plugin = _FakePlugin(_FakeAndroid(true), alwaysThrow: true);
    await expectLater(debugSnoozeFeedInBackground(fp, plugin: plugin), completes);
  });

  test('alarmModeFor: Android izin yok → inexact; izin var / iOS → exact', () async {
    expect(await NotificationService.alarmModeFor(_FakePlugin(_FakeAndroid(false))),
        AndroidScheduleMode.inexactAllowWhileIdle);
    expect(await NotificationService.alarmModeFor(_FakePlugin(_FakeAndroid(true))),
        AndroidScheduleMode.exactAllowWhileIdle);
  });
}
