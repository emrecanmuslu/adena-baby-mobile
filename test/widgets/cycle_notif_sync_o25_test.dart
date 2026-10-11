import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/cycle/cycle_notif_sync.dart';
import 'package:adena_baby/models/cycle.dart';

class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final Map<int, PendingNotificationRequest> scheduled = {};
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlugin: ${invocation.memberName}');
}

/// O25 — adet hatırlatıcıları merkezi eşitleyiciyle: ayar/kayıt değişince
/// "adetin yaklaşıyor" yeni tahmine kurulur; mod kayıp/postpartum'a geçince ya da
/// hatırlatıcı kapanınca iptal edilir (eskiden yalnız Ayarlar ekranı planlıyordu).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlugin plugin;
  late StreamController<CycleSettings> settingsCtrl;
  late StreamController<List<CycleEntry>> entriesCtrl;

  setUp(() {
    plugin = _FakePlugin();
    settingsCtrl = StreamController<CycleSettings>.broadcast();
    entriesCtrl = StreamController<List<CycleEntry>>.broadcast();
  });

  tearDown(() async {
    await settingsCtrl.close();
    await entriesCtrl.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationServiceProvider
            .overrideWithValue(NotificationService.withPlugin(plugin)),
        cycleSettingsProvider.overrideWith((ref) => settingsCtrl.stream),
        cycleEntriesProvider.overrideWith((ref) => entriesCtrl.stream),
        // B1: eşitleyici "döngüm uzundu" cevaplarını da (hesap kapsamlı) okur.
        activeAccountIdProvider.overrideWithValue('acct-o25'),
      ],
      child: const MaterialApp(home: Offstage(child: CycleNotifSync())),
    ));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
  }

  testWidgets('yeni adet loglanınca hatırlatıcı yeni tahmine kurulur; kapatınca iptal',
      (tester) async {
    final today = DateTime.now();
    final anchor = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 10));
    final settings = CycleSettings(
      firstPeriodDate: anchor,
      expectedCycleLength: 28,
      reminders: const {'period': {'on': true}},
    );
    await pump(tester);
    settingsCtrl.add(settings);
    entriesCtrl.add(const []);
    await settle(tester);
    expect(plugin.ids, contains(600000), reason: '"adetin yaklaşıyor" kuruldu');

    // Hatırlatıcı kapatıldı → iptal (tahmin değişmese de).
    settingsCtrl.add(settings.copyWith(reminders: const {'period': {'on': false}}));
    await settle(tester);
    expect(plugin.ids, isNot(contains(600000)));

    // Tekrar açıldı ama mod kayıp (tahmin gizli) → kurulmaz.
    settingsCtrl.add(settings.copyWith(
        lifecycleMode: CycleLifecycleMode.loss, predictionsHidden: true));
    await settle(tester);
    expect(plugin.ids, isNot(contains(600000)));
  });
}
