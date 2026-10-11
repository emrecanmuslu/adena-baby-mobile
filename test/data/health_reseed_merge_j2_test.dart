import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/providers.dart';
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
  @override
  Future<List<Baby>> build() async => [
        Baby(
            id: 'b1',
            name: 'T',
            gender: BabyGender.unknown,
            status: BabyStatus.born,
            birthDate: DateTime(2026, 1, 1),
            myRole: 'owner')
      ];
}

const _catalog = HealthCatalog(
  [VaccineCatalogItem('BCG', 2, 'BCG'), VaccineCatalogItem('Hepatit B', 0, 'Hepatit B')],
  [
    MilestoneCatalogItem('roll', 4, 'motor', 'Yuvarlanma', 'd', 't'),
    MilestoneCatalogItem('sit', 6, 'motor', 'Oturma', 'd', 't'),
  ],
  [ToothCatalogItem('ll1', 'lower', 'left', 1, 'Orta kesici', 6)],
);

/// INCELEME-2 J2 / KB-12 — lapse→yeniden abonelikte yeniden-tohumlama TAM küme
/// göndermez (backend damgasız son-yazan-kazanır; çok cihazlı ailede diğer
/// cihazın işaretleri ezilirdi). Birleşim semantiği: yalnız (1) done=true
/// satırlar ve (2) `clientUpdatedAt != null` satırlar (v15'te kullanıcı eliyle
/// değiştirilmiş; açık "kaldırma" dahil). Damgasız done=false (v14 varsayılanı)
/// GÖNDERİLMEZ. İlk göç (free→premium) `pushAll` tam küme olarak kalır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ApiClient api;
  late DioAdapter adapter;
  late List<RequestOptions> requests;
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
      ..onPost('/babies/b1/health/sync', (s) => s.reply(200, {'ok': true}),
          data: Matchers.any);
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1',
        name: 'T',
        accountId: const Value(acct),
        myRole: const Value('owner'),
        dirty: const Value(false), // K1(b): sunucuda var (lapse senaryosu)
        birthDate: Value(DateTime(2026, 1, 1))));
  });

  tearDown(() => db.close());

  Future<void> seed(String kind, String key, bool done,
      {DateTime? stamp, bool dirty = false}) async {
    await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
        baby: 'b1',
        kind: kind,
        itemKey: key,
        done: Value(done),
        statusDate: Value(done ? DateTime(2026, 3, 4) : null),
        dirty: Value(dirty),
        clientUpdatedAt: Value(stamp)));
  }

  ProviderContainer container() {
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

  List<RequestOptions> healthPosts() => requests
      .where((r) => r.method == 'POST' && r.path == '/babies/b1/health/sync')
      .toList();

  group('J2 — yeniden-tohumlama birleşim semantiği', () {
    test('gövde yalnız done=true + damgalı satırlar; damgasız done=false YOK', () async {
      await seed('vaccine', 'BCG', true); // v14 temiz tik → gider
      await seed('vaccine', 'Hepatit B', false); // v14 damgasız "yapılmadı" → GİTMEZ
      await seed('milestone', 'roll', false,
          stamp: DateTime.utc(2026, 9, 1)); // v15 açık kaldırma → gider
      await seed('milestone', 'sit', false); // damgasız → gitmez
      await seed('tooth', 'll1', true, stamp: DateTime.utc(2026, 9, 2), dirty: true);
      await LocalSession.markPremiumSyncedForAccount(acct);
      await LocalSession.markHealthReseedForAccount(acct);
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(migrationControllerProvider.notifier).run();

      final posts = healthPosts();
      expect(posts, hasLength(1));
      final body = posts.single.data as Map;
      final vaccines = (body['vaccines'] as List).cast<Map>();
      expect(vaccines.map((v) => v['name']), ['BCG']);
      expect(vaccines.single['done'], isTrue);
      final milestones = (body['milestones'] as List).cast<Map>();
      expect(milestones.map((m) => m['key']), ['roll']);
      expect(milestones.single['achieved'], isFalse,
          reason: 'damgalı açık kaldırma yayılır');
      final teeth = (body['teeth'] as List).cast<Map>();
      expect(teeth.map((t) => t['key']), ['ll1']);
      expect(LocalSession.healthReseedPending(acct), isFalse);
      expect(c.read(migrationControllerProvider).phase, MigrationPhase.idle,
          reason: 'overlay yok');
    });

    test('gönderilecek satır yoksa istek atılmaz, bayrak yine düşer', () async {
      await seed('vaccine', 'Hepatit B', false);
      await LocalSession.markPremiumSyncedForAccount(acct);
      await LocalSession.markHealthReseedForAccount(acct);
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(migrationControllerProvider.notifier).run();
      expect(healthPosts(), isEmpty);
      expect(LocalSession.healthReseedPending(acct), isFalse);
    });

    test('regresyon: ilk göç (free→premium) pushAll TAM küme (damgasız done=false dahil)',
        () async {
      await seed('vaccine', 'BCG', true);
      await seed('vaccine', 'Hepatit B', false);
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(migrationControllerProvider.notifier).run();

      final posts = healthPosts();
      expect(posts, hasLength(1));
      final vaccines = ((posts.single.data as Map)['vaccines'] as List).cast<Map>();
      expect(vaccines.map((v) => v['name']).toSet(), {'BCG', 'Hepatit B'});
      expect(vaccines.firstWhere((v) => v['name'] == 'Hepatit B')['done'], isFalse);
      expect(LocalSession.premiumSyncedForAccount(acct), isTrue);
    });
  });
}
