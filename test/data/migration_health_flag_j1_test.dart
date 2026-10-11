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

/// INCELEME-2 J1/J8 (+ INCELEME-3 K1(a)) — sahip bebek sağlık pull kapısı
/// yalnız sağlık tam kümesi GERÇEKTEN buluta yüklendiyse açılır. Göçte
/// (sunucudaki bebekte) sağlık adımı düşerse (ağ/5xx/404) `premiumSynced` VE
/// `health_reseed` BİRLİKTE yazılır: kapı kapalı kalır, sonraki açılışlar hafif
/// yoldan (`_reseedHealth`) dener (K1(a) — eskiden `premiumSynced` yazılmaz,
/// her açılışta tam göç + overlay tekrarlanırdı). `_dirtyCount` hatası
/// "bilinmiyor"dur (kısayol yok, bayrak yok); göç sırasında kapsam değişirse
/// eski hesaba bayrak yazılmaz. (b) Sunucu aşı listesi tamamen pending iken
/// yerelde temiz done=true satır varsa aşı kalemleri uygulanmaz.
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

  Future<void> seedOwnerBabyWithCleanVaccine() async {
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1',
        name: 'T',
        accountId: const Value(acct),
        myRole: const Value('owner'),
        birthDate: Value(DateTime(2026, 1, 1))));
    await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
        baby: 'b1',
        kind: 'vaccine',
        itemKey: 'BCG',
        done: const Value(true),
        statusDate: Value(DateTime(2026, 3, 4)),
        dirty: const Value(false)));
  }

  ProviderContainer container({bool withBaby = true}) {
    _Babies.list = withBaby ? [_baby('b1')] : const [];
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

  Future<bool> bcgDone() async => (await (db.select(db.healthStatuses)
        ..where((s) => s.kind.equals('vaccine') & s.itemKey.equals('BCG')))
      .getSingle())
      .done;

  bool pulledVaccines() =>
      requests.any((r) => r.method == 'GET' && r.path == '/babies/b1/vaccines');

  void healthSyncFails(void Function(dynamic s) fail) {
    adapter.onPost('/babies/b1/health/sync', fail, data: Matchers.any);
  }

  Future<void> expectBothFlagsAndPullClosed(ProviderContainer c) async {
    expect(LocalSession.premiumSyncedForAccount(acct), isTrue,
        reason: 'K1(a): tam göç bitti → bir daha overlay/markAllDirty yok');
    expect(LocalSession.healthReseedPending(acct), isTrue,
        reason: 'sağlık yüklenmedi → yeniden-tohumlama bekler (kapı kapalı)');
    // Ağ geldi: bir sonraki tam tur sahip bebekte pull atmaz, tik korunur.
    adapter.onPost('/babies/b1/health/sync', (s) => s.reply(200, {'ok': true}),
        data: Matchers.any);
    requests.clear();
    await c.read(syncServiceProvider).syncAll(sharedOnly: false);
    expect(pulledVaccines(), isFalse);
    expect(await bcgDone(), isTrue);
  }

  group('J1 — göçte sağlık adımı düşerse', () {
    for (final (label, fail) in <(String, void Function(dynamic))>[
      (
        'connectionError',
        (s) => s.throws(
            0,
            DioException(
                requestOptions: RequestOptions(path: '/babies/b1/health/sync'),
                type: DioExceptionType.connectionError))
      ),
      ('503', (s) => s.reply(503, {'detail': 'down'})),
      ('404', (s) => s.reply(404, {'detail': 'nope'})),
    ]) {
      test('$label → premiumSynced + reseed birlikte, sonraki tur pull yok (K1(a))',
          () async {
        await seedOwnerBabyWithCleanVaccine();
        healthSyncFails(fail);
        final c = container();
        await c.read(babyControllerProvider.future);

        await c.read(migrationControllerProvider.notifier).run();
        expect(c.read(migrationControllerProvider).phase, MigrationPhase.done);
        await expectBothFlagsAndPullClosed(c);
      });
    }

    test('sağlık adımı başarılı → premiumSynced yazılır, reseed düşer (J8)', () async {
      await seedOwnerBabyWithCleanVaccine();
      adapter.onPost('/babies/b1/health/sync', (s) => s.reply(200, {'ok': true}),
          data: Matchers.any);
      await LocalSession.markHealthReseedForAccount(acct); // purge→lapse kalıntısı
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(migrationControllerProvider.notifier).run();
      expect(LocalSession.premiumSyncedForAccount(acct), isTrue);
      expect(LocalSession.healthReseedPending(acct), isFalse,
          reason: 'tam göç sağlık tam kümesini gönderdi → reseed gereksiz');
    });
  });

  group('J1 — _dirtyCount hatası "bilinmiyor"', () {
    test('sayım düşerse "veri yok" kısayolu alınmaz, bayrak yazılmaz', () async {
      // Sahip bebek yok (tüm sayılar 0 olurdu); health_statuses tablosu yok →
      // sayım hata verir. Eski kod: catch→0 → "veri yok" → premiumSynced.
      await db.customStatement('DROP TABLE health_statuses');
      final c = container(withBaby: false);
      await c.read(babyControllerProvider.future);

      await c.read(migrationControllerProvider.notifier).run();
      expect(LocalSession.premiumSyncedForAccount(acct), isFalse,
          reason: 'sayım bilinmiyor → kapı açılmaz');
    });
  });

  group('J1 — göç sırasında kapsam değişimi', () {
    test('bebek POST\'u sürerken hesap değişir → eski hesaba bayrak yazılmaz', () async {
      await seedOwnerBabyWithCleanVaccine();
      adapter.onPost(
          '/babies',
          (s) => s.reply(200, {'id': 'b1', 'photo': null},
              delay: const Duration(milliseconds: 60)),
          data: Matchers.any);
      adapter.onPost('/babies/b1/health/sync', (s) => s.reply(200, {'ok': true}),
          data: Matchers.any);
      final c = container();
      await c.read(babyControllerProvider.future);

      final run = c.read(migrationControllerProvider.notifier).run();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      LocalSession.setActiveAccount('u2'); // çıkış + başka hesap
      await run;
      expect(LocalSession.premiumSyncedForAccount(acct), isFalse);
      expect(LocalSession.premiumSyncedForAccount('u2'), isFalse);
    });
  });

  group('J1(b) — tamamen pending sunucu kümesi otoriter değildir', () {
    test('sunucu hiç done içermiyor + yerel temiz done=true → aşı uygulanmaz, reseed, telemetri',
        () async {
      await seedOwnerBabyWithCleanVaccine();
      // Gelişim bu kuraldan etkilenmez: sunucu değeri uygulanır.
      adapter.onGet('/babies/b1/milestones', (s) => s.reply(200, [
            {'key': 'roll', 'achieved': true, 'achieved_date': '2026-05-01'},
          ]));
      await LocalSession.markPremiumSyncedForAccount(acct); // kapı açık
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);
      expect(pulledVaccines(), isTrue);
      expect(await bcgDone(), isTrue, reason: 'lazy sunucu kümesi tiki silmez');
      expect(LocalSession.healthReseedPending(acct), isTrue);
      expect(reports.map((r) => r.$1), contains('health_pull_lazy_server_skipped'));
      expect(reports.map((r) => r.$1), isNot(contains('health_pull_cleared_done')));
      final roll = await (db.select(db.healthStatuses)
            ..where((s) => s.kind.equals('milestone') & s.itemKey.equals('roll')))
          .getSingle();
      expect(roll.done, isTrue, reason: 'gelişim/diş etkilenmez');
    });

    test('sunucuda en az bir done var → mevcut K-4 davranışı (sunucu kazanır)', () async {
      await seedOwnerBabyWithCleanVaccine();
      adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, [
            {'vaccine_name': 'BCG', 'status': 'pending', 'done_date': null},
            {'vaccine_name': 'Hepatit B', 'status': 'done', 'done_date': '2026-01-02'},
          ]));
      await LocalSession.markPremiumSyncedForAccount(acct);
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);
      expect(await bcgDone(), isFalse);
      expect(LocalSession.healthReseedPending(acct), isFalse);
      expect(reports.map((r) => r.$1), contains('health_pull_cleared_done'));
    });
  });
}
