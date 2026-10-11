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
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
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

class _Flag extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool v) => state = v;
}

Baby _baby(String id, {String? role}) => Baby(
    id: id,
    name: 'T',
    gender: BabyGender.unknown,
    status: BabyStatus.born,
    birthDate: DateTime(2026, 1, 1),
    myRole: role);

class _Babies extends BabyController {
  static List<Baby> list = const [];
  @override
  Future<List<Baby>> build() async => list;
}

const _catalog = HealthCatalog(
  [VaccineCatalogItem('BCG', 2, 'BCG'), VaccineCatalogItem('Hepatit B', 0, 'Hepatit B')],
  [MilestoneCatalogItem('roll', 4, 'motor', 'Yuvarlanma', 'd', 't')],
  [ToothCatalogItem('ll1', 'lower', 'left', 1, 'Orta kesici', 6)],
);

/// I1 (INCELEME.md) — free→premium (ve lapse→yeniden abone) kullanıcıda v14'te
/// işaretlenmiş (TEMİZ) aşı tikleri, göç `pushAll` sunucuya yazmadan önce koşan
/// `syncAll` tam turunun pull'uyla siliniyordu (sunucu lazy "pending" küme).
/// Kapı: sahip bebekte sağlık pull'u yalnız `premiumSyncedForAccount` true VE
/// yeniden-tohumlama (lapse) beklemiyorken; paylaşılan bebekte kapı yok (K-4).
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
      ..onPost('/sync', (s) => s.reply(200, {'applied': [], 'conflicts': [], 'server_changes': []}),
          data: Matchers.any)
      ..onPost('/babies/b1/medication-plans/sync',
          (s) => s.reply(200, {'applied': [], 'plans': []}),
          data: Matchers.any)
      ..onPost('/babies/b1/health/sync', (s) => s.reply(200, {'ok': true}),
          data: Matchers.any)
      // Sunucu bu bebek için takvimi lazy üretir: her şey pending (free kullanıcı
      // hiç push etmemişti).
      ..onGet('/babies/b1/vaccines', (s) => s.reply(200, [
            {'vaccine_name': 'BCG', 'status': 'pending', 'done_date': null},
            {'vaccine_name': 'Hepatit B', 'status': 'pending', 'done_date': null},
          ]))
      ..onGet('/babies/b1/milestones', (s) => s.reply(200, []))
      ..onGet('/babies/b1/teeth', (s) => s.reply(200, []));
  });

  tearDown(() => db.close());

  Future<void> seedOwnerBabyWithCleanVaccine({String? role}) async {
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1',
        name: 'T',
        accountId: const Value(acct),
        myRole: Value(role ?? 'owner'),
        birthDate: Value(DateTime(2026, 1, 1))));
    // v14'ten gelen temiz satır (K-4: aşıda backfill yok).
    await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
        baby: 'b1',
        kind: 'vaccine',
        itemKey: 'BCG',
        done: const Value(true),
        statusDate: Value(DateTime(2026, 3, 4)),
        dirty: const Value(false)));
  }

  ProviderContainer container({String? role, bool premium = true}) {
    _Babies.list = [_baby('b1', role: role)];
    final cycle = _MockCycle();
    when(() => cycle.syncIfCloud()).thenAnswer((_) async {});
    when(() => cycle.markAllDirty(accountId: any(named: 'accountId'))).thenAnswer((_) async {});
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
      loggedInProvider.overrideWithValue(true),
      isPremiumProvider.overrideWithValue(premium),
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

  /// J1(b): tamamen pending (lazy) sunucu kümesi artık otoriter DEĞİL; K-4
  /// "sunucu kazanır" kontratı yalnız sunucuda en az bir done varken geçerli.
  void serverHasOneDone() {
    adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, [
          {'vaccine_name': 'BCG', 'status': 'pending', 'done_date': null},
          {'vaccine_name': 'Hepatit B', 'status': 'done', 'done_date': '2026-01-02'},
        ]));
  }

  group('I1 — sağlık pull kapısı (syncAll tam turu)', () {
    test('free→premium: göç pushAll ÖNCESİ tam tur aşıyı sıfırlamaz (pull yok)',
        () async {
      await seedOwnerBabyWithCleanVaccine();
      final c = container();
      await c.read(babyControllerProvider.future);
      expect(LocalSession.premiumSyncedForAccount(acct), isFalse);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);

      expect(await bcgDone(), isTrue, reason: 'temiz v14 tiki pull ile silinmemeli');
      expect(pulledVaccines(), isFalse, reason: 'kapı: pull hiç atılmaz');
    });

    test('göç tamamlanınca (premiumSynced) pull açılır → K-4: sunucu kazanır',
        () async {
      await seedOwnerBabyWithCleanVaccine();
      serverHasOneDone();
      final c = container();
      await c.read(babyControllerProvider.future);
      await LocalSession.markPremiumSyncedForAccount(acct);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);

      expect(pulledVaccines(), isTrue);
      expect(await bcgDone(), isFalse, reason: 'senkronize hesapta sunucu otoriter');
    });

    test('paylaşılan (parent) bebekte kapı yok: premiumSynced false olsa da pull',
        () async {
      await seedOwnerBabyWithCleanVaccine(role: 'parent');
      serverHasOneDone();
      final c = container(role: 'parent', premium: false);
      await c.read(babyControllerProvider.future);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);

      expect(pulledVaccines(), isTrue);
      expect(await bcgDone(), isFalse);
    });

    test('lapse→yeniden abone: yeniden-tohumlama beklerken pull yok; '
        'göç birleşim kümesini gönderip bayrağı düşürünce pull açılır', () async {
      await seedOwnerBabyWithCleanVaccine();
      await LocalSession.markPremiumSyncedForAccount(acct); // önceden senkron
      await LocalSession.markHealthReseedForAccount(acct); // premium bitmişti
      final c = container();
      await c.read(babyControllerProvider.future);

      await c.read(syncServiceProvider).syncAll(sharedOnly: false);
      expect(pulledVaccines(), isFalse);
      expect(await bcgDone(), isTrue);

      // Yeniden abonelik → MigrationService: premiumSynced true ama reseed bekliyor
      // → yalnız sağlık işaretleri gönderilir (J2 birleşim: done=true + damgalı;
      // damgasız done=false GİTMEZ), overlay yok, bayrak düşer.
      await c.read(migrationControllerProvider.notifier).run();
      final post = requests.where(
          (r) => r.method == 'POST' && r.path == '/babies/b1/health/sync');
      expect(post, hasLength(1));
      final vaccines = ((post.single.data as Map)['vaccines'] as List).cast<Map>();
      expect(
          vaccines.any((v) => v['name'] == 'BCG' && v['done'] == true), isTrue,
          reason: 'temiz v14 tiki sunucuya yazılır');
      expect(vaccines.any((v) => v['name'] == 'Hepatit B'), isFalse,
          reason: 'J2: damgasız done=false (v14 varsayılanı) gönderilmez');
      expect(LocalSession.healthReseedPending(acct), isFalse);
      expect(c.read(migrationControllerProvider).phase, MigrationPhase.idle,
          reason: 'overlay gösterilmez');

      requests.clear();
      await c.read(syncServiceProvider).syncAll(sharedOnly: false);
      expect(pulledVaccines(), isTrue);
    });
  });

  group('I1 — MigrationService bayrakları', () {
    test('yüklenecek yerel veri yokken (yeni cihaz/boş hesap) premiumSynced işaretlenir',
        () async {
      final c = container();
      await c.read(babyControllerProvider.future);
      expect(LocalSession.premiumSyncedForAccount(acct), isFalse);
      await c.read(migrationControllerProvider.notifier).run();
      expect(LocalSession.premiumSyncedForAccount(acct), isTrue,
          reason: 'kaybedilecek yerel veri yok → kapı açılmalı');
    });

    test('cloudSync true→false (lapse, oturum açıkken) yeniden-tohumlama bayrağını kurar; '
        'çıkışta (hesap kapsamı kapalı) kurmaz', () async {
      final premium = NotifierProvider<_Flag, bool>(_Flag.new);
      final c = ProviderContainer(overrides: [
        loggedInProvider.overrideWithValue(true),
        isPremiumProvider.overrideWith((ref) => ref.watch(premium)),
      ]);
      addTearDown(c.dispose);
      c.read(localToCloudMigrationProvider);
      // Uygulamada cloudSyncEnabledProvider widget'larca izlenir; container'da
      // da bir dinleyici tut ki değişiklik dinleyiciye anında yansısın.
      c.listen(cloudSyncEnabledProvider, (_, _) {});
      expect(c.read(cloudSyncEnabledProvider), isTrue);

      c.read(premium.notifier).set(false); // lapse
      await Future<void>.delayed(Duration.zero);
      expect(LocalSession.healthReseedPending(acct), isTrue);

      await LocalSession.clearHealthReseedForAccount(acct);
      LocalSession.setActiveAccount(null); // çıkış: kapsam önce kapanır
      c.read(premium.notifier).set(true);
      await Future<void>.delayed(Duration.zero);
      c.read(premium.notifier).set(false);
      await Future<void>.delayed(Duration.zero);
      expect(LocalSession.healthReseedPending(acct), isFalse);
    });
  });

  group('I1 — healthPullAllowed (saf)', () {
    test('matris', () {
      expect(healthPullAllowed(shared: true, premiumSynced: false, reseedPending: true), isTrue);
      expect(healthPullAllowed(shared: false, premiumSynced: false, reseedPending: false), isFalse);
      expect(healthPullAllowed(shared: false, premiumSynced: true, reseedPending: true), isFalse);
      expect(healthPullAllowed(shared: false, premiumSynced: true, reseedPending: false), isTrue);
    });
  });
}
