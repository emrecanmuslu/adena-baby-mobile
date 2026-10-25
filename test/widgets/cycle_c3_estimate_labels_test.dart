import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/features/cycle/cycle_calendar_screen.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

class _TitlePlugin implements FlutterLocalNotificationsPlugin {
  final Map<int, String?> titles = {};
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
  Future<void> cancel({required int id, String? tag}) async => titles.remove(id);
  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    titles[id] = title;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('TitlePlugin: ${invocation.memberName}');
}

/// ADET-INCELEME C3: tüm tahmin tarihleri ve takvim etiketleri "tahmini".
void main() {
  CycleSettings s(int anchor) =>
      CycleSettings(firstPeriodDate: dayOffset(anchor), breastfeeding: Breastfeeding.none);

  testWidgets('takvim (ovülasyon günü seçili): "Tahmini yumurtlama günü" + lejant',
      (t) async {
    await pumpCycleScreen(t, const CycleCalendarScreen(),
        settings: s(-98), entries: periodEntries([-98, -70, -42, -14]));
    expect(textHas('Tahmini yumurtlama günü'), findsOneWidget);
    expect(textHas('en yüksek doğurganlık'), findsNothing);
    expect(textHas('Yumurtlama (tahmini)'), findsOneWidget);
    expect(textHas('Doğurganlık (tahmini)'), findsOneWidget);
  });

  testWidgets('takvim (pencere günü seçili): "Tahmini doğurgan gün"', (t) async {
    await pumpCycleScreen(t, const CycleCalendarScreen(),
        settings: s(-94), entries: periodEntries([-94, -66, -38, -10]));
    expect(textHas('Tahmini doğurgan gün'), findsOneWidget);
  });

  testWidgets('bugün: ovülasyon halkası + sonraki âdet "tahmini"', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: s(-98), entries: periodEntries([-98, -70, -42, -14]));
    expect(textHas('TAHMİNİ YUMURTLAMA'), findsOneWidget); // halka etiketi büyük harf
  });

  testWidgets('bugün: geri sayımda "Sonraki âdet (tahmini)"', (t) async {
    // 28 günlük döngü, bugün 24. gün → 4 gün kaldı.
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: s(-107), entries: periodEntries([-107, -79, -51, -23]));
    expect(textHas('Sonraki âdet (tahmini)'), findsWidgets);
  });

  test('bildirim başlıkları "tahmini"', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    final p = _TitlePlugin();
    await NotificationService.withPlugin(p).syncCycle(
      reminders: const {
        'period': {'on': true},
        'fertile': {'on': true},
      },
      nextPeriod: DateTime.now().add(const Duration(days: 20)),
      fertileStart: DateTime.now().add(const Duration(days: 5)),
    );
    expect(p.titles[600000], contains('tahmini'));
    expect(p.titles[600001], contains('Tahmini'));
  });
}
