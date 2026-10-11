import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/core/sync_telemetry.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_prefs.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/migration_service.dart';
import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/features/records/record_controller.dart';
import 'package:adena_baby/models/baby.dart';

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

class _MockCycle extends Mock implements CycleRepository {}

class _Babies extends BabyController {
  static List<Baby> list = const [];
  @override
  Future<List<Baby>> build() async => list;
}

Baby _baby(String id, {String role = 'owner'}) => Baby(
    id: id,
    name: 'T',
    gender: BabyGender.unknown,
    status: BabyStatus.born,
    birthDate: DateTime(2026, 1, 1),
    myRole: role);

const _catalog = HealthCatalog(
  [VaccineCatalogItem('BCG', 2, 'BCG'), VaccineCatalogItem('Hepatit B', 0, 'Hepatit B')],
  [MilestoneCatalogItem('roll', 4, 'motor', 'Yuvarlanma', 'd', 't')],
  [ToothCatalogItem('ll1', 'lower', 'left', 1, 'Orta kesici', 6)],
);

/// INCELEME-3 K2/K3 — J1(b) "tamamen pending sunucu kümesi otoriter değil"
/// sezgiseli yalnız **sunucudan hiç onay görmemiş** (`serverUpdatedAt IS NULL`)
/// ve **sunucunun tanıdığı** (adı listede) temiz done=true aşı satırlarıyla
/// tetiklenir. Pull'dan gelmiş/yankıyla onaylanmış tik (serverUpdatedAt dolu)
/// lazy sayılmaz → diğer cihazın "son done tiki kaldırma"sı yayılır (R1),
/// reseed kurulmaz, sahip cihazı tiki sunucuya geri yazmaz. Dil uyuşmazlığında
/// (yerel ad sunucu listesinde yok) sezgisel tetiklenmez → reseed/pull ping-pong'u
/// kesilir (K3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ApiClient api;
  late DioAdapter adapter;
  late List<RequestOptions> requests;
  late List<(String, Map<String, Object?>)> reports;
  const acct = 'u1';

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
    SharedPreferences.setMockInitialValues({});
    LocalPrefs.resetForTests();
    LocalSession.resetForTests();
    LocalSession.setActiveAccount(acct);
    db = AppDatabase(NativeDatabase.memory());
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    requests = [];
    reports = [];
    SyncTelemetry.override = (e, i) async => reports.add((e, i));
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests.add(o);
      h.next(o);
    }));
    adapter
      ..onPost('/babies', (s) => s.reply(200, {'id': 'b1', 'photo': null}),
          data: Matchers.any)
      ..onPost('/sync',
          (s) => s.reply(200, {'applied': [], 'conflicts': [], 'server_changes': []}),
          data: Matchers.any)
      ..onPost('/babies/b1/medication-plans/sync',
          (s) => s.reply(200, {'applied': [], 'plans': []}),
          data: Matchers.any)
      ..onPost('/babies/b1/health/sync', (s) => s.reply(200, {'ok': true}),
          data: Matchers.any)
      // Sunucu MEŞRU olarak tamamen pending: diğer ebeveyn BCG tikini kaldırdı.
      ..onGet('/babies/b1/vaccines', (s) => s.reply(200, [
            {'vaccine_name': 'BCG', 'status': 'pending', 'done_date': null},
            {'vaccine_name': 'Hepatit B', 'status': 'pending', 'done_date': null},
          ]))
      ..onGet('/babies/b1/milestones', (s) => s.reply(200, []))
      ..onGet('/babies/b1/teeth', (s) => s.reply(200, []));
  });

  tearDown(() async {
    SyncTelemetry.override = null;
    await db.close();
  });

  /// [serverSeen] true → satır daha önce pull/yankı ile onaylanmış (v15 damgası).
  Future<void> seedBaby({String role = 'owner', required bool serverSeen}) async {
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1',
        name: 'T',
        accountId: const Value(acct),
        myRole: Value(role),
        dirty: const Value(false),
        birthDate: Value(DateTime(2026, 1, 1))));
    await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
        baby: 'b1',
        kind: 'vaccine',
        itemKey: 'BCG',
        done: const Value(true),
        statusDate: Value(DateTime(2026, 3, 4)),
        dirty: const Value(false),
        serverUpdatedAt:
            serverSeen ? Value(DateTime(2026, 3, 5)) : const Value(null)));
  }

  ProviderContainer container({String role = 'owner'}) {
    _Babies.list = [_baby('b1', role: role)];
    final cycle = _MockCycle();
    when(() => cycle.syncIfCloud()).thenAnswer((_) async {});
    when(() => cycle.markAllDirty(accountId: any(named: 'accountId')))
        .thenAnswer((_) async {});
    when(() => cycle.migrateToCloud(accountId: any(named: 'accountId')))
        .thenAnswer((_) async {});
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
      loggedInProvider.overrideWithValue(true),
      isPremiumProvider.overrideWithValue(true),
      activeAccountIdProvider.overrideWithValue(acct),
      babyControllerProvider.overrideWith(_Babies.new),
      cycleRepositoryProvider.overrideWithValue(cycle),
      healthCatalogProvider.overrideWith((_) async => _catalog),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<HealthStatusRow> bcg() async => (await (db.select(db.healthStatuses)
        ..where((s) => s.kind.equals('vaccine') & s.itemKey.equals('BCG')))
      .getSingle());

  Iterable<RequestOptions> healthPosts() =>
      requests.where((r) => r.method == 'POST' && r.path == '/babies/b1/health/sync');

  group('K2 — sunucudan onay görmüş tik lazy sayılmaz', () {
    for (final role in ['parent', 'owner']) {
      test('$role: pull\'dan gelmiş temiz done=true + sunucu tamamen pending → '
          'kaldırma UYGULANIR, reseed yok, telemetri yok', () async {
        await seedBaby(role: role, serverSeen: true);
        await LocalSession.markPremiumSyncedForAccount(acct);
        final c = container(role: role);
        await c.read(babyControllerProvider.future);

        await c.read(syncServiceProvider).syncAll(sharedOnly: false);

        final row = await bcg();
        expect(row.done, isFalse, reason: 'R1: kaldırma yayılır');
        expect(row.serverUpdatedAt, isNotNull);
        expect(LocalSession.healthReseedPending(acct), isFalse);
        expect(reports.map((r) => r.$1),
            isNot(contains('health_pull_lazy_server_skipped')));
        expect(reports.map((r) => r.$1), contains('health_pull_cleared_done'));
      });
    }

    test('owner: ikinci açılışta reseed BCG=true\'yu sunucuya GERİ YAZMAZ', () async {
      await seedBaby(serverSeen: true);
      await LocalSession.markPremiumSyncedForAccount(acct);
      final c = container();
      await c.read(babyControllerProvider.future);
      await c.read(syncServiceProvider).syncAll(sharedOnly: false);
      requests.clear();

      await c.read(migrationControllerProvider.notifier).run();
      expect(healthPosts(), isEmpty, reason: 'reseed bayrağı kurulmadı → istek yok');
    });
  });

  group('J1(b) korunur — v14 tiki (serverUpdatedAt NULL)', () {
    test('sunucu tamamen pending + yerel temiz done=true (onaysız) → uygulanmaz, reseed',
        () async {
      await seedBaby(serverSeen: false);
      await LocalSession.markPremiumSyncedForAccount(acct);
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);

      expect((await bcg()).done, isTrue, reason: 'lazy sunucu kümesi tiki silmez');
      expect(LocalSession.healthReseedPending(acct), isTrue);
      expect(reports.map((r) => r.$1), contains('health_pull_lazy_server_skipped'));
    });

    test('pull sunucuyla aynı değeri görünce serverUpdatedAt yazar (onay)', () async {
      await seedBaby(serverSeen: false);
      await LocalSession.markPremiumSyncedForAccount(acct);
      adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, [
            {'vaccine_name': 'BCG', 'status': 'done', 'done_date': '2026-03-04'},
            {'vaccine_name': 'Hepatit B', 'status': 'pending', 'done_date': null},
          ]));
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);

      final row = await bcg();
      expect(row.done, isTrue);
      expect(row.serverUpdatedAt, isNotNull, reason: 'sunucu onayı damgalandı');
      expect(LocalSession.healthReseedPending(acct), isFalse);
    });
  });

  group('K3 — dil uyuşmazlığında ping-pong yok', () {
    test('yerel ad sunucu listesinde yok → sezgisel tetiklenmez, reseed/pull döngüsü kesilir',
        () async {
      await seedBaby(serverSeen: false); // yerel 'BCG' (TR), onaysız
      await LocalSession.markPremiumSyncedForAccount(acct);
      await LocalSession.markHealthReseedForAccount(acct); // önceki açılıştan kalan
      // Sunucu şeması başka dilde: yerel ad listede YOK, hepsi pending.
      adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, [
            {'vaccine_name': 'BCG vaccine', 'status': 'pending', 'done_date': null},
            {'vaccine_name': 'Hepatitis B', 'status': 'pending', 'done_date': null},
          ]));
      final c = container();
      await c.read(babyControllerProvider.future);

      // 1. açılış: reseed (2xx ama sunucuda eşleşme yok) → bayrak düşer → pull.
      await c.read(migrationControllerProvider.notifier).run();
      expect(healthPosts(), hasLength(1));
      expect(LocalSession.healthReseedPending(acct), isFalse);
      await c.read(syncServiceProvider).syncAll(sharedOnly: false);
      expect(LocalSession.healthReseedPending(acct), isFalse,
          reason: 'sunucunun tanımadığı ad lazy sayılmaz → bayrak yeniden KURULMAZ');
      expect(reports.map((r) => r.$1),
          isNot(contains('health_pull_lazy_server_skipped')));
      expect((await bcg()).done, isTrue, reason: 'yetim TR satırı dokunulmaz (I10)');

      // 2. açılış: reseed isteği YOK (döngü kesildi).
      requests.clear();
      await c.read(migrationControllerProvider.notifier).run();
      await c.read(syncServiceProvider).syncAll(sharedOnly: false);
      expect(healthPosts(), isEmpty);
      expect(reports.where((r) => r.$1 == 'health_pull_lazy_server_skipped'), isEmpty);
    });
  });
}
