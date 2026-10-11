import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/data/cycle_long_answers.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/cycle/cycle_notif_sync.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

class _CapturePlugin implements FlutterLocalNotificationsPlugin {
  final Map<int, tz.TZDateTime> at = {};
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
      const [];
  @override
  Future<void> cancel({required int id, String? tag}) async => at.remove(id);
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
    at[id] = scheduledDate;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('CapturePlugin: ${invocation.memberName}');
}

/// ADET-INCELEME B1 — unutulan ay: bugün ekranı bir kez sorar; "döngüm uzundu"
/// cevabı kalıcı saklanır ve hesaba katılır; "adetin yaklaşıyor" bildirimi
/// uç değer dışlanmış tahmine (28 gün) kurulur.
void main() {
  // Unutulan ay: 28 + 56, bugün yeni döngünün 21. günü.
  final settings = CycleSettings(
      firstPeriodDate: dayOffset(-104), breastfeeding: Breastfeeding.none);
  final entries = periodEntries([-104, -76, -20]);

  testWidgets('bugün: soru kartı görünür; "Hayır, döngüm uzundu" kalıcı', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: settings, entries: entries);
    expect(textHas('Bu dönemde bir adet kaydını unutmuş olabilir misin?'),
        findsOneWidget);
    expect(textHas('56 günlük döngü'), findsOneWidget);
    await t.tap(find.text('Hayır, döngüm uzundu'));
    await t.pump(const Duration(milliseconds: 50));
    expect(textHas('unutmuş olabilir misin?'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cycle_long_answers_acct-test'),
        contains(CycleLongAnswers.keyOf(dayOffset(-76))));
  });

  testWidgets('kaydedilmiş cevap varsa soru tekrar sorulmaz', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: settings,
        entries: entries,
        prefs: {
          'cycle_long_answers_acct-test':
              '{"${CycleLongAnswers.keyOf(dayOffset(-76))}":"asked"}'
        });
    expect(textHas('unutmuş olabilir misin?'), findsNothing);
  });

  testWidgets('bildirim: "adetin yaklaşıyor" medyan (28) tahminine kurulur',
      (t) async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
    SharedPreferences.setMockInitialValues({});
    final plugin = _CapturePlugin();
    final s = settings.copyWith(reminders: const {'period': {'on': true}});
    await t.pumpWidget(ProviderScope(
      overrides: [
        notificationServiceProvider
            .overrideWithValue(NotificationService.withPlugin(plugin)),
        cycleSettingsProvider.overrideWith((ref) => Stream.value(s)),
        cycleEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        activeAccountIdProvider.overrideWithValue('acct-test'),
      ],
      child: const MaterialApp(home: Offstage(child: CycleNotifSync())),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    final when = plugin.at[600000];
    expect(when, isNotNull);
    // Sonraki adet = son başlangıç (−20) + 28 = +8; bildirim 3 gün önce 09:00.
    final want = dayOffset(5);
    expect(DateTime(when!.year, when.month, when.day), want);
  });
}
