import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/models/reminder.dart';

/// Sahte bildirim eklentisi: zamanlanan id'leri bellekte tutar. Yalnız
/// `NotificationService.sync` yolunun dokunduğu üyeler uygulanmıştır; başka bir
/// üyeye erişim testi açıkça düşürür (sessizce başarılı görünmesin).
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

  // Testte platform yok → null (servis izin/exact-alarm adımlarını atlar).
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
  Future<void> periodicallyShowWithDuration({
    required int id,
    required Duration repeatDurationInterval,
    required NotificationDetails notificationDetails,
    String? title,
    String? body,
    AndroidScheduleMode androidScheduleMode = AndroidScheduleMode.exact,
    String? payload,
  }) async {
    scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlugin: ${invocation.memberName}');
}

Reminder _daily(int id, {bool enabled = true, String time = '09:00'}) =>
    Reminder(
      id: id,
      type: 'custom',
      schedule: {'repeat': 'daily', 'time': time, 'title': 'T$id'},
      enabled: enabled,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlugin plugin;
  late NotificationService svc;

  setUp(() {
    plugin = _FakePlugin();
    svc = NotificationService.withPlugin(plugin);
  });

  // K1 (BULGULAR.md): sync(list) tek bebeğin listesini alıyor; mutabakat ise
  // 600000 altındaki TÜM bekleyenleri bu listeye göre iptal ediyordu → A'dan
  // sonra B senkronlanınca A'nın özel/randevu hatırlatıcıları siliniyordu.
  group('K1 — çok-bebek mutabakatı', () {
    test('B bebeği senkronlanınca A bebeğinin hatırlatıcıları kalır', () async {
      final aList = [_daily(1), _daily(2, time: '21:00')];
      final bList = [_daily(3)];
      final all = {1, 2, 3};

      await svc.sync(aList, allActiveIds: () async => all);
      expect(plugin.ids, {1, 2});

      await svc.sync(bList, allActiveIds: () async => all);
      expect(plugin.ids, {1, 2, 3},
          reason: "B'nin sync'i A'nın bildirimlerini iptal etmemeli");

      // A tekrar senkronlanınca B'ninki de kalmalı (simetri).
      await svc.sync(aList, allActiveIds: () async => all);
      expect(plugin.ids, {1, 2, 3});
    });

    test('hiçbir bebeğe ait olmayan (yetim) bekleyen bildirim iptal edilir',
        () async {
      plugin.scheduled[7] = const PendingNotificationRequest(7, 'yetim', null, null);
      await svc.sync([_daily(1)], allActiveIds: () async => {1});
      expect(plugin.ids, {1});
    });

    test('600000 ve üstü (feed/sayaç/sağlık) id\'lere dokunulmaz', () async {
      plugin.scheduled[800003] =
          const PendingNotificationRequest(800003, 'feed', null, null);
      plugin.scheduled[610000] =
          const PendingNotificationRequest(610000, 'vaccine', null, null);
      await svc.sync([_daily(1)], allActiveIds: () async => {1});
      expect(plugin.ids, {1, 610000, 800003});
    });
  });

  group('iptal etme bozulmadı', () {
    test('hatırlatıcı KAPATILINCA bildirimi iptal edilir', () async {
      await svc.sync([_daily(1), _daily(2)], allActiveIds: () async => {1, 2});
      expect(plugin.ids, {1, 2});

      await svc.sync([_daily(1, enabled: false), _daily(2)],
          allActiveIds: () async => {2});
      expect(plugin.ids, {2}, reason: 'kapatılan 1 iptal edilmeli');
    });

    test('hatırlatıcı SİLİNİNCE (listeden düşünce) bildirimi iptal edilir',
        () async {
      await svc.sync([_daily(1), _daily(2)], allActiveIds: () async => {1, 2});
      await svc.sync([_daily(2)], allActiveIds: () async => {2});
      expect(plugin.ids, {2});
    });

    test('aktif id kaynağı okunamazsa yalnız bu listenin kapalıları iptal edilir',
        () async {
      // Başka bebeğe ait 9 bekliyor; kaynak patlayınca ona dokunulmamalı,
      // ama bu listedeki kapalı 1 yine de iptal edilmeli.
      plugin.scheduled[9] = const PendingNotificationRequest(9, 'B', null, null);
      plugin.scheduled[1] = const PendingNotificationRequest(1, 'A', null, null);
      await svc.sync([_daily(1, enabled: false), _daily(2)],
          allActiveIds: () async => throw StateError('db'));
      expect(plugin.ids, {2, 9});
    });
  });
}
