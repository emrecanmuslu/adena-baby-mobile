import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/slot_registry.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/models/baby.dart';

class _MockBabyRepo extends Mock implements BabyRepository {}

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
  final Set<int> canceled = {};
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
  Future<void> cancel({required int id, String? tag}) async => canceled.add(id);
  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('FakePlugin: ${i.memberName}');
}

Baby _baby(String id) =>
    Baby(id: id, name: 'B', status: BabyStatus.born, myRole: 'owner');

/// INCELEME-2 J5 — `_cancelBabyNotifications` slotu `state.asData` üzerinden
/// alıyordu; riverpod 3'te `asData` AsyncLoading'de null → sessiz `return`,
/// hiçbir bildirim iptal edilmezdi (bebek değiştirici / misafir göçü sonrası
/// `invalidate` ile loading iken silme). Slot `SlotRegistry`'den alınır.
/// J10 — I5 entegrasyonu uçtan uca: `deleteBaby` özel/randevu hatırlatıcı
/// id'lerini de iptal kümesine sokar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _MockBabyRepo repo;
  late _FakePlugin plugin;

  setUpAll(() => registerFallbackValue(_baby('x')));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalSession.setActiveAccount('u1');
    db = AppDatabase(NativeDatabase.memory());
    repo = _MockBabyRepo();
    when(() => repo.delete(any())).thenAnswer((_) async {});
    when(() => repo.watchAll(accountId: any(named: 'accountId')))
        .thenAnswer((_) => StreamController<List<Baby>>.broadcast().stream);
    plugin = _FakePlugin();
    NotificationService.instance = NotificationService.withPlugin(plugin);
  });
  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(ApiClient(_FakeTokens())),
      babyRepositoryProvider.overrideWithValue(repo),
      loggedInProvider.overrideWithValue(false),
      cloudSyncEnabledProvider.overrideWithValue(false),
      healthCatalogProvider.overrideWith((_) async => const HealthCatalog([], [], [])),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  test('J5: liste yüklenirken (AsyncLoading) silme → bildirimler yine iptal edilir',
      () async {
    when(() => repo.getAll(accountId: any(named: 'accountId')))
        .thenAnswer((_) => Completer<List<Baby>>().future); // hiç çözülmez
    final c = container();
    final ctrl = c.read(babyControllerProvider.notifier);
    expect(c.read(babyControllerProvider).isLoading, isTrue);

    await ctrl.deleteBaby('b1');

    final slot = SlotRegistry.instance.slotFor('b1');
    expect(plugin.canceled, contains(NotificationService.feedMainIdFor(slot)),
        reason: 'loading durumunda da O15 iptali çalışmalı');
    verify(() => repo.delete('b1')).called(1);
  });
}
