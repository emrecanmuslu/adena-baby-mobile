import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/models/reminder.dart';

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'a';
  @override
  Future<String?> get refreshToken async => 'r';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

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
  }) async =>
      scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('FakePlugin: ${i.memberName}');
}

Reminder _daily(int id) => Reminder(
    id: id,
    type: 'custom',
    schedule: const {'repeat': 'daily', 'time': '09:00'},
    enabled: true,
    createdAt: DateTime(2026, 1, 1));

/// I5 (INCELEME.md) — bebek silinince özel/randevu hatırlatıcıları:
/// `cancelBabyScheduled(reminderIds)` onları iptal eder; `activeReminderIds`
/// tombstone bebeğin hatırlatıcılarını dışlar → K1 mutabakatı yetim görür.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late HealthRepository repo;
  late _FakePlugin plugin;
  late NotificationService svc;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = HealthRepository(db, ApiClient(_FakeTokens()),
        () async => const HealthCatalog([], [], []), (_) => false);
    plugin = _FakePlugin();
    svc = NotificationService.withPlugin(plugin);
    for (final id in ['A', 'B']) {
      await db.into(db.babies).insert(BabiesCompanion.insert(id: id, name: id));
    }
  });
  tearDown(() => db.close());

  test('activeReminderIds: silinmiş (tombstone) bebeğin hatırlatıcıları dışlanır', () async {
    final a = await repo.createReminder('A', type: 'custom', schedule: const {'repeat': 'daily'});
    final b = await repo.createReminder('B', type: 'custom', schedule: const {'repeat': 'daily'});
    expect(await repo.activeReminderIds(), {a.id, b.id});
    expect(await repo.reminderIdsForBaby('A'), [a.id]);

    await (db.update(db.babies)..where((x) => x.id.equals('A')))
        .write(const BabiesCompanion(isDeleted: Value(true)));
    expect(await repo.activeReminderIds(), {b.id});
  });

  test('cancelBabyScheduled(reminderIds) yalnız o bebeğin hatırlatıcılarını iptal eder', () async {
    await svc.sync([_daily(11)], allActiveIds: () async => {11, 22});
    await svc.sync([_daily(22)], allActiveIds: () async => {11, 22});
    expect(plugin.ids, {11, 22});

    await svc.cancelBabyScheduled(slot: 0, reminderIds: [11]);
    expect(plugin.ids, {22});
  });

  test('iki bebek, A silinir: K1 mutabakatı (B sync) A\'nın hatırlatıcısını yetim görür',
      () async {
    final a = await repo.createReminder('A', type: 'custom', schedule: const {'repeat': 'daily', 'time': '09:00'});
    final b = await repo.createReminder('B', type: 'custom', schedule: const {'repeat': 'daily', 'time': '09:00'});
    await svc.sync([_daily(a.id)], allActiveIds: repo.activeReminderIds);
    await svc.sync([_daily(b.id)], allActiveIds: repo.activeReminderIds);
    expect(plugin.ids, {a.id, b.id});

    // A tombstone (deleteBaby → repo.delete); satırlar purge'e kadar kalır.
    await (db.update(db.babies)..where((x) => x.id.equals('A')))
        .write(const BabiesCompanion(isDeleted: Value(true)));
    await svc.sync([_daily(b.id)], allActiveIds: repo.activeReminderIds);
    expect(plugin.ids, {b.id}, reason: 'silinmiş bebeğin hatırlatıcısı pending\'de kalmamalı');
  });
}
