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
import 'package:adena_baby/data/baby_repository.dart';
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

Baby _baby(String id) => Baby(
    id: id,
    name: 'T',
    gender: BabyGender.unknown,
    status: BabyStatus.born,
    birthDate: DateTime(2026, 1, 1),
    myRole: 'owner');

const _catalog = HealthCatalog(
  [VaccineCatalogItem('BCG', 2, 'BCG'), VaccineCatalogItem('Hepatit B', 0, 'Hepatit B')],
  [MilestoneCatalogItem('roll', 4, 'motor', 'Yuvarlanma', 'd', 't')],
  [ToothCatalogItem('ll1', 'lower', 'left', 1, 'Orta kesici', 6)],
);

/// INCELEME-3 K1 — göçte sağlık adımı yalnız **sunucuda var olduğu doğrulanmış**
/// sahip bebeklerde zorunludur (sinyal: bebek satırı `dirty=false` — son
/// POST/PATCH 2xx aldı ya da sunucudan indi). Sunucuda henüz olmayan bebek
/// `healthOk`'u düşürmez; sağlığı sonraki turda bebek oluşunca J1(b)+reseed
/// zinciriyle gider. Sunucudaki bebekte sağlık yine de düşerse `premiumSynced`
/// VE `healthReseed` birlikte yazılır: kapı kapalı kalır ama sonraki açılışlar
/// hafif yoldan (`_reseedHealth`; overlay/markAllDirty yok) dener — her
/// açılışta tam göç + overlay döngüsü yok.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ApiClient api;
  late DioAdapter adapter;
  late List<RequestOptions> requests;
  late List<(String, Map<String, Object?>)> reports;
  late List<MigrationPhase> phases;
  late Set<String> babyPostFails; // bu id'lerin POST /babies'i 503 alır
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
    phases = [];
    babyPostFails = {};
    SyncTelemetry.override = (e, i) async => reports.add((e, i));
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests.add(o);
      final data = o.data;
      if (o.method == 'POST' &&
          o.path == '/babies' &&
          data is Map &&
          babyPostFails.contains(data['id'])) {
        // Geçici sunucu hatası (503) → bebek satırı dirty kalır, pushError yok.
        h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: o, statusCode: 503)));
        return;
      }
      h.next(o);
    }));
    adapter
      ..onPost('/babies', (s) => s.reply(200, {'id': 'x', 'photo': null}),
          data: Matchers.any)
      ..onPost('/sync',
          (s) => s.reply(200, {'applied': [], 'conflicts': [], 'server_changes': []}),
          data: Matchers.any);
    for (final b in ['b1', 'b2']) {
      adapter
        ..onPost('/babies/$b/medication-plans/sync',
            (s) => s.reply(200, {'applied': [], 'plans': []}),
            data: Matchers.any)
        ..onPost('/babies/$b/health/sync', (s) => s.reply(200, {'ok': true}),
            data: Matchers.any)
        ..onGet('/babies/$b/vaccines', (s) => s.reply(200, [
              {'vaccine_name': 'BCG', 'status': 'pending', 'done_date': null},
              {'vaccine_name': 'Hepatit B', 'status': 'pending', 'done_date': null},
            ]))
        ..onGet('/babies/$b/milestones', (s) => s.reply(200, []))
        ..onGet('/babies/$b/teeth', (s) => s.reply(200, []));
    }
  });

  tearDown(() async {
    SyncTelemetry.override = null;
    await db.close();
  });

  Future<void> seedBaby(String id, {bool cleanBcg = true}) async {
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: id,
        name: 'T',
        accountId: const Value(acct),
        myRole: const Value('owner'),
        dirty: const Value(true), // yerelde oluşturuldu, sunucuya hiç gitmedi
        birthDate: Value(DateTime(2026, 1, 1))));
    if (cleanBcg) {
      await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
          baby: id,
          kind: 'vaccine',
          itemKey: 'BCG',
          done: const Value(true),
          statusDate: Value(DateTime(2026, 3, 4)),
          dirty: const Value(false))); // v14 tiki: serverUpdatedAt NULL
    }
    await db.into(db.records).insert(RecordsCompanion.insert(
        id: 'r-$id', baby: id, type: 'feed', ts: DateTime(2026, 3, 1)));
  }

  ProviderContainer container(List<String> ids) {
    _Babies.list = [for (final id in ids) _baby(id)];
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
    c.listen(migrationControllerProvider, (_, n) => phases.add(n.phase));
    addTearDown(c.dispose);
    return c;
  }

  Future<HealthStatusRow> bcg(String id) async => (await (db.select(db.healthStatuses)
        ..where((s) => s.baby.equals(id) & s.itemKey.equals('BCG')))
      .getSingle());

  Future<bool> babyDirty(String id) async =>
      (await (db.select(db.babies)..where((b) => b.id.equals(id))).getSingle()).dirty;

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).length;

  test('(1) sunucuda oluşmamış sahip bebek + diğeri başarılı → premiumSynced, reseed yok, kapı açık',
      () async {
    await seedBaby('b1');
    await seedBaby('b2');
    babyPostFails = {'b1'};
    // b1 sunucuda yok → üyelik kontrolü 403 (IsBabyMember); pull hiçbir şey uygulamaz.
    adapter.onGet('/babies/b1/vaccines', (s) => s.reply(403, {'error': 'forbidden'}));
    final c = container(['b1', 'b2']);
    await c.read(babyControllerProvider.future);

    await c.read(migrationControllerProvider.notifier).run();

    expect(await babyDirty('b1'), isTrue, reason: 'b1 sunucuya gidemedi');
    expect(await babyDirty('b2'), isFalse, reason: 'b2 POST 2xx');
    expect(count('POST', '/babies/b2/health/sync'), 1);
    expect(count('POST', '/babies/b1/health/sync'), 0,
        reason: 'sunucuda olmayan bebeğe sağlık gönderilmez (403 olurdu)');
    expect(LocalSession.premiumSyncedForAccount(acct), isTrue);
    expect(LocalSession.healthReseedPending(acct), isFalse);
    // Kapı açık: tam tur b2 için pull atar.
    requests.clear();
    await c.read(syncServiceProvider).syncAll(sharedOnly: false);
    expect(count('GET', '/babies/b2/vaccines'), 1);
  });

  test('(2) ikinci run(): overlay yok, bebek/kayıt yeniden POST edilmez, markAllDirty koşmaz',
      () async {
    await seedBaby('b1');
    await seedBaby('b2');
    babyPostFails = {'b1'};
    final c = container(['b1', 'b2']);
    await c.read(babyControllerProvider.future);
    final ctl = c.read(migrationControllerProvider.notifier);
    await ctl.run();
    expect(phases, contains(MigrationPhase.running));
    ctl.dismiss();
    phases.clear();
    requests.clear();

    await ctl.run();

    expect(phases, isNot(contains(MigrationPhase.running)), reason: 'overlay yok');
    expect(count('POST', '/babies'), 0);
    expect(count('POST', '/sync'), 0);
    expect(await babyDirty('b2'), isFalse, reason: 'markAllDirty koşmadı');
  });

  test('(3) UÇTAN UCA kurtarma zinciri: bebek POST\'u geçici düşer → göç biter → '
      'bebek oluşur → lazy pull uygulanmaz + reseed → reseed BCG=true gönderir → '
      'yankı serverUpdatedAt yazar → sonraki pull K-4', () async {
    await seedBaby('b1');
    babyPostFails = {'b1'};
    final c = container(['b1']);
    await c.read(babyControllerProvider.future);
    final ctl = c.read(migrationControllerProvider.notifier);

    // 1) Göç: bebek POST'u 503 → sağlık gönderilmez, premiumSynced yine yazılır.
    await ctl.run();
    expect(count('POST', '/babies/b1/health/sync'), 0);
    expect(LocalSession.premiumSyncedForAccount(acct), isTrue);
    expect(LocalSession.healthReseedPending(acct), isFalse);
    expect((await bcg('b1')).done, isTrue);

    // 2) Sonraki tur: sunucu düzeldi → bebek oluşur (BabyController._pull yolu).
    babyPostFails = {};
    await c.read(babyRepositoryProvider).pushDirty(accountId: acct);
    expect(await babyDirty('b1'), isFalse);

    // 3) Tam tur: sunucu takvimi lazy (tamamen pending) → J1(b): uygulanmaz + reseed.
    requests.clear();
    await c.read(syncServiceProvider).syncAll(sharedOnly: false);
    expect(count('GET', '/babies/b1/vaccines'), 1);
    expect((await bcg('b1')).done, isTrue, reason: 'v14 tiki silinmedi');
    expect(LocalSession.healthReseedPending(acct), isTrue);
    expect(reports.map((r) => r.$1), contains('health_pull_lazy_server_skipped'));

    // 4) Sonraki açılış: hafif yol → pushReseed BCG done=true (overlay yok).
    ctl.dismiss();
    phases.clear();
    requests.clear();
    await ctl.run();
    expect(phases, isNot(contains(MigrationPhase.running)));
    final reseed =
        requests.where((r) => r.method == 'POST' && r.path == '/babies/b1/health/sync');
    expect(reseed, hasLength(1));
    expect(((reseed.single.data as Map)['vaccines'] as List).single,
        {'name': 'BCG', 'done': true, 'done_date': '2026-03-04'});
    expect(LocalSession.healthReseedPending(acct), isFalse);

    // 5) Sunucu artık BCG=done → pull "aynı değer" → serverUpdatedAt (onay) yazılır.
    adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, [
          {'vaccine_name': 'BCG', 'status': 'done', 'done_date': '2026-03-04'},
          {'vaccine_name': 'Hepatit B', 'status': 'pending', 'done_date': null},
        ]));
    await c.read(syncServiceProvider).syncAll(sharedOnly: false);
    expect((await bcg('b1')).serverUpdatedAt, isNotNull);

    // 6) Diğer cihaz tiki kaldırdı (sunucu tamamen pending) → K-4: sunucu kazanır.
    adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, [
          {'vaccine_name': 'BCG', 'status': 'pending', 'done_date': null},
          {'vaccine_name': 'Hepatit B', 'status': 'pending', 'done_date': null},
        ]));
    reports.clear();
    await c.read(syncServiceProvider).syncAll(sharedOnly: false);
    expect((await bcg('b1')).done, isFalse, reason: 'kaldırma yayıldı (K-4)');
    expect(LocalSession.healthReseedPending(acct), isFalse);
    expect(reports.map((r) => r.$1), isNot(contains('health_pull_lazy_server_skipped')));
  });

  test('(4) sunucudaki bebekte sağlık 503 → iki bayrak birlikte; sonraki açılış hafif yol',
      () async {
    await seedBaby('b1');
    adapter.onPost('/babies/b1/health/sync', (s) => s.reply(503, {'detail': 'down'}),
        data: Matchers.any);
    final c = container(['b1']);
    await c.read(babyControllerProvider.future);
    final ctl = c.read(migrationControllerProvider.notifier);

    await ctl.run();
    expect(await babyDirty('b1'), isFalse);
    expect(LocalSession.premiumSyncedForAccount(acct), isTrue);
    expect(LocalSession.healthReseedPending(acct), isTrue);
    // Kapı kapalı: tam tur pull atmaz, tik korunur.
    requests.clear();
    await c.read(syncServiceProvider).syncAll(sharedOnly: false);
    expect(count('GET', '/babies/b1/vaccines'), 0);
    expect((await bcg('b1')).done, isTrue);

    // Sonraki açılış: sunucu düzeldi → hafif yol (overlay yok, bebek POST yok).
    adapter.onPost('/babies/b1/health/sync', (s) => s.reply(200, {'ok': true}),
        data: Matchers.any);
    ctl.dismiss();
    phases.clear();
    requests.clear();
    await ctl.run();
    expect(phases, isNot(contains(MigrationPhase.running)));
    expect(count('POST', '/babies'), 0);
    expect(count('POST', '/babies/b1/health/sync'), 1);
    expect(LocalSession.healthReseedPending(acct), isFalse, reason: 'kapı açıldı');
  });
}
