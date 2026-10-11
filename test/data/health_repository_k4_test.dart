import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/sync_telemetry.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';

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

/// K4/O21 (TASARIM §6): işaretleme ağı beklemez (dirty + callback), delta push
/// yalnız dirty satırlar, pull R1 (temiz satıra işaret kaldırma da yazılır,
/// dirty korunur), aşı yankı güvencesi (O19), R5 uçuş-içi, R3 pushError,
/// "ilk v15 turunda aşıda sunucu kazanır".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const catalog = HealthCatalog(
    [
      VaccineCatalogItem('Hepatit B', 0, 'Hepatit B'),
      VaccineCatalogItem('BCG', 2, 'BCG'),
    ],
    [
      MilestoneCatalogItem('roll', 4, 'motor', 'Yuvarlanma', 'd', 't'),
      MilestoneCatalogItem('smile', 2, 'social', 'Gülümseme', 'd', 't'),
    ],
    [ToothCatalogItem('ll1', 'lower', 'left', 1, 'Orta kesici', 6)],
  );

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late HealthRepository repo;
  final changedBabies = <String>[];
  final requests = <RequestOptions>[];

  setUp(() async {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests.add(o);
      h.next(o);
    }));
    requests.clear();
    changedBabies.clear();
    db = AppDatabase(NativeDatabase.memory());
    repo = HealthRepository(db, api, () async => catalog, (_) => true,
        onStatusChanged: changedBabies.add);
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1', name: 'T', birthDate: Value(DateTime(2026, 1, 1))));
  });

  tearDown(() => db.close());

  Future<HealthStatusRow?> row(String kind, String key) =>
      (db.select(db.healthStatuses)
            ..where((s) => s.kind.equals(kind) & s.itemKey.equals(key)))
          .getSingleOrNull();

  Future<void> seed(String kind, String key, bool done,
      {bool dirty = false, DateTime? date}) =>
      db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
          baby: 'b1',
          kind: kind,
          itemKey: key,
          done: Value(done),
          statusDate: Value(date),
          dirty: Value(dirty),
          clientUpdatedAt:
              Value(dirty ? DateTime.now().toUtc() : null)));

  void stubSync({int code = 200}) => adapter.onPost(
      '/babies/b1/health/sync', (s) => s.reply(code, {'ok': code == 200}),
      data: Matchers.any);

  void stubGets({
    List<Map<String, dynamic>>? vaccines,
    List<Map<String, dynamic>>? milestones,
    List<Map<String, dynamic>>? teeth,
  }) {
    adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, vaccines ?? []));
    adapter.onGet('/babies/b1/milestones', (s) => s.reply(200, milestones ?? []));
    adapter.onGet('/babies/b1/teeth', (s) => s.reply(200, teeth ?? []));
  }

  group('O21 — işaretleme ağı beklemez', () {
    test('setVaccineDone: istek atılmaz, satır dirty + damga, callback çağrılır',
        () async {
      // Hiç stub yok: ağa çıkılsa DioAdapter hata verirdi.
      await repo.setVaccineDone('b1', 'BCG', done: true, date: DateTime(2026, 3, 4));
      expect(requests, isEmpty);
      final r = (await row('vaccine', 'BCG'))!;
      expect(r.dirty, isTrue);
      expect(r.clientUpdatedAt, isNotNull);
      expect(changedBabies, ['b1']);
    });

    test('bulut kapalı bebekte callback çağrılmaz, dirty yine yazılır (göç için)',
        () async {
      final local = HealthRepository(db, api, () async => catalog, (_) => false,
          onStatusChanged: changedBabies.add);
      await local.setMilestoneAchieved('b1', 'roll', achieved: true);
      expect(changedBabies, isEmpty);
      expect((await row('milestone', 'roll'))!.dirty, isTrue);
    });
  });

  group('K4 — delta push', () {
    test('yalnız dirty satırlar gönderilir; 2xx → gelişim/diş temiz, aşı yankı bekler',
        () async {
      await seed('vaccine', 'BCG', true, dirty: true, date: DateTime(2026, 3, 4));
      await seed('milestone', 'roll', true, dirty: true);
      await seed('tooth', 'll1', true, dirty: false); // temiz → gönderilmez
      stubSync();

      await repo.pushDirty('b1');

      expect(requests, hasLength(1));
      final body = requests.single.data as Map;
      expect((body['vaccines'] as List).map((e) => e['name']), ['BCG']);
      expect((body['milestones'] as List).map((e) => e['key']), ['roll']);
      expect(body['teeth'], isEmpty, reason: 'temiz satır gönderilmez (R7)');
      expect((await row('milestone', 'roll'))!.dirty, isFalse);
      expect((await row('vaccine', 'BCG'))!.dirty, isTrue,
          reason: 'aşı: yankı (pull) gelene dek dirty');
    });

    test('dirty satır yoksa istek atılmaz', () async {
      await seed('tooth', 'll1', true);
      await repo.pushDirty('b1');
      expect(requests, isEmpty);
    });

    test('R5: gönderim sırasında yeniden işaretlenen satır dirty kalır', () async {
      await seed('milestone', 'roll', true, dirty: true);
      // Sunucu yanıtı dönmeden önce kullanıcı işareti geri alıyor.
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await repo.setMilestoneAchieved('b1', 'roll', achieved: false);
        h.next(o);
      }));
      stubSync();
      await repo.pushDirty('b1');
      final r = (await row('milestone', 'roll'))!;
      expect(r.dirty, isTrue);
      expect(r.done, isFalse);
    });

    test('R3: kalıcı 4xx → pushError, dirty kalır, fırlatmaz', () async {
      await seed('milestone', 'roll', true, dirty: true);
      stubSync(code: 422);
      await repo.pushDirty('b1');
      final r = (await row('milestone', 'roll'))!;
      expect(r.dirty, isTrue);
      expect(r.pushError, 'HTTP 422');
    });

    test('geçici (503 / 403) → fırlatır, dirty kalır, pushError yok', () async {
      await seed('milestone', 'roll', true, dirty: true);
      stubSync(code: 503);
      await expectLater(repo.pushDirty('b1'), throwsA(isA<DioException>()));
      stubSync(code: 403);
      await expectLater(repo.pushDirty('b1'), throwsA(isA<DioException>()));
      final r = (await row('milestone', 'roll'))!;
      expect(r.dirty, isTrue);
      expect(r.pushError, isNull);
    });
  });

  group('K4 — pull (R1)', () {
    test(
        'SENKRONİZE hesapta (kapı açık — I1) ilk v15 turu: AŞIDA SUNUCU KAZANIR — '
        'temiz done=true, sunucu pending → yapılmadı; geçiş telemetriye düşer', () async {
      // Bağlam: repo.pull yalnız `healthPullAllowed` true iken çağrılır
      // (SyncService._syncHealth; test/data/health_pull_gate_i1_test.dart).
      // Bu kontrat "bu hesabın yerel kümesi bir kez tam yüklendi" varsayar;
      // free→premium / lapse yolunda pull HİÇ çağrılmaz.
      final reports = <(String, Map<String, Object?>)>[];
      SyncTelemetry.override = (e, i) async => reports.add((e, i));
      addTearDown(() => SyncTelemetry.override = null);
      await seed('vaccine', 'BCG', true, date: DateTime(2026, 3, 4)); // migrated, temiz
      stubGets(vaccines: [
        {'vaccine_name': 'BCG', 'status': 'pending', 'done_date': null},
        {'vaccine_name': 'Hepatit B', 'status': 'done', 'done_date': '2026-01-02'},
      ]);
      final changed = await repo.pull('b1');
      expect(changed, isTrue);
      expect((await row('vaccine', 'BCG'))!.done, isFalse);
      final hep = (await row('vaccine', 'Hepatit B'))!;
      expect(hep.done, isTrue);
      expect(hep.dirty, isFalse);
      expect(hep.statusDate, DateTime(2026, 1, 2));
      expect(reports, hasLength(1));
      expect(reports.single.$1, 'health_pull_cleared_done');
      expect(reports.single.$2['vaccine'], 1);
      expect(reports.single.$2['baby'], 'b1');
    });

    test('telemetri: temiz done=true → sunucu pending geçişi yoksa rapor yok', () async {
      final reports = <String>[];
      SyncTelemetry.override = (e, _) async => reports.add(e);
      addTearDown(() => SyncTelemetry.override = null);
      await seed('vaccine', 'BCG', true, date: DateTime(2026, 3, 4));
      stubGets(vaccines: [
        {'vaccine_name': 'BCG', 'status': 'done', 'done_date': '2026-03-04'},
      ]);
      await repo.pull('b1');
      expect(reports, isEmpty);
    });

    test('işaret kaldırma yayılır (gelişim/diş temiz satıra done=false yazılır)',
        () async {
      await seed('milestone', 'roll', true, date: DateTime(2026, 5, 1));
      stubGets(milestones: [
        {'key': 'roll', 'achieved': false, 'achieved_date': null},
      ]);
      await repo.pull('b1');
      expect((await row('milestone', 'roll'))!.done, isFalse);
    });

    test('dirty satır ezilmez', () async {
      await seed('milestone', 'roll', true, dirty: true);
      stubGets(milestones: [
        {'key': 'roll', 'achieved': false, 'achieved_date': null},
      ]);
      final changed = await repo.pull('b1');
      expect(changed, isFalse);
      final r = (await row('milestone', 'roll'))!;
      expect(r.done, isTrue);
      expect(r.dirty, isTrue);
    });

    test('boş liste / 200 dışı / parse hatası → o tür atlanır', () async {
      await seed('milestone', 'roll', true);
      await seed('tooth', 'll1', true);
      adapter.onGet('/babies/b1/vaccines', (s) => s.reply(200, []));
      adapter.onGet('/babies/b1/milestones', (s) => s.reply(500, {'e': 1}));
      adapter.onGet('/babies/b1/teeth', (s) => s.reply(200, {'not': 'a list'}));
      final changed = await repo.pull('b1');
      expect(changed, isFalse);
      expect((await row('milestone', 'roll'))!.done, isTrue);
      expect((await row('tooth', 'll1'))!.done, isTrue);
    });

    test('aşı yankısı: push edilen aşı sunucuda aynı değerle görünürse temizlenir',
        () async {
      await seed('vaccine', 'BCG', true, dirty: true, date: DateTime(2026, 3, 4));
      stubSync();
      await repo.pushDirty('b1');
      stubGets(vaccines: [
        {'vaccine_name': 'BCG', 'status': 'done', 'done_date': '2026-03-04'},
      ]);
      await repo.pull('b1');
      expect((await row('vaccine', 'BCG'))!.dirty, isFalse);
    });

    test('O19: aşı adı sunucuda eşleşmedi (dil farkı) → dirty kalır, pushError yok, tik kaybolmaz',
        () async {
      await seed('vaccine', 'BCG', true, dirty: true, date: DateTime(2026, 3, 4));
      stubSync(); // 2xx ama sunucu sessiz no-op
      await repo.pushDirty('b1');
      stubGets(vaccines: [
        {'vaccine_name': 'Bacillus Calmette-Guérin', 'status': 'pending', 'done_date': null},
      ]);
      await repo.pull('b1');
      final r = (await row('vaccine', 'BCG'))!;
      expect(r.dirty, isTrue);
      expect(r.done, isTrue);
      expect(r.pushError, isNull);
      // İkinci tur: yine push edilir (idempotent), yine yankı bekler.
      requests.clear();
      stubSync();
      await repo.pushDirty('b1');
      expect(requests, hasLength(1));
    });

    test('I10: katalogta olmayan (başka dildeki) sunucu aşı kalemi yerelde satır üretmez',
        () async {
      stubGets(vaccines: [
        {'vaccine_name': 'Bacillus Calmette-Guérin', 'status': 'done', 'done_date': '2026-03-04'},
        {'vaccine_name': 'BCG', 'status': 'done', 'done_date': '2026-03-04'},
      ]);
      await repo.pull('b1');
      expect(await row('vaccine', 'Bacillus Calmette-Guérin'), isNull,
          reason: 'katalog dışı ad → yetim satır yok');
      expect((await row('vaccine', 'BCG'))!.done, isTrue);
    });

    test('importFromCloud (ilk giriş/göç) = pull: artık kaldırma da uygulanır',
        () async {
      await seed('tooth', 'll1', true);
      stubGets(teeth: [
        {'key': 'll1', 'erupted': false, 'erupted_date': null},
      ]);
      await repo.importFromCloud('b1');
      expect((await row('tooth', 'll1'))!.done, isFalse);
    });
  });
  group('M9(a) — yankılanmayan aşı polling turunda yeniden gönderilmez', () {
    test('tam turda denenir, polling (retryUnechoed=false) atlar; yankı gelince normale döner',
        () async {
      await seed('vaccine', 'BCG', true, dirty: true, date: DateTime(2026, 3, 4));
      stubSync();
      await repo.pushDirty('b1');
      stubGets(vaccines: [
        {'vaccine_name': 'Other', 'status': 'pending', 'done_date': null},
      ]);
      await repo.pull('b1'); // yankı yok → işaretlendi
      requests.clear();
      stubSync();
      await repo.pushDirty('b1', retryUnechoed: false);
      expect(requests, isEmpty, reason: 'polling turunda POST atılmaz');
      await repo.pushDirty('b1'); // tam tur
      expect(requests, hasLength(1));
      stubGets(vaccines: [
        {'vaccine_name': 'BCG', 'status': 'done', 'done_date': '2026-03-04'},
      ]);
      await repo.pull('b1');
      expect((await row('vaccine', 'BCG'))!.dirty, isFalse);
    });
  });
}
