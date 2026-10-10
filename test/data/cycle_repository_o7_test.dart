import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/models/cycle.dart';

/// O7 (BULGULAR.md / TASARIM-SENKRON.md R1, R2, R4, R5): adet kaydı pull'u
/// dirty satırı ve tombstone'u eziyordu; sunucuda silinen gün yerelden
/// kalkmıyordu; bulk `failed[]` ve DELETE 404 yanlış ele alınıyordu.
class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'fake-access';
  @override
  Future<String?> get refreshToken async => 'fake-refresh';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const acct = 'acct-o7';
  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    LocalSession.setActiveAccount(acct);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  CycleRepository localRepo() => CycleRepository(db, api, () => false);
  CycleRepository cloudRepo() => CycleRepository(db, api, () => true);

  Map<String, dynamic> srv(String id, String date,
          {String flow = 'medium', String note = '', String? updatedAt}) =>
      {
        'id': id,
        'date': date,
        'flow': flow,
        'lochia_color': '',
        'symptoms': const [],
        'mood': null,
        'note': note,
        'updated_at': updatedAt ?? '2026-05-20T10:00:00Z',
      };

  Future<CycleEntryRow?> row(String id) =>
      (db.select(db.cycleEntries)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<void> markClean(String id) =>
      (db.update(db.cycleEntries)..where((r) => r.id.equals(id)))
          .write(const CycleEntriesCompanion(dirty: Value(false)));

  Future<CycleEntry> save(int day, {String? note, FlowLevel flow = FlowLevel.medium}) =>
      localRepo().saveEntry(CycleEntry(
          id: '', date: DateTime(2026, 5, day), flow: flow, note: note));

  // ───────── MEVCUT API ─────────
  group('O7 adet — pull (importFromCloud)', () {
    test('dirty yerel düzenleme korunur (R1)', () async {
      final e = await save(20, note: 'Yerel');
      adapter.onGet('/cycle/settings', (s) => s.reply(200, {}));
      adapter.onGet('/cycle/entries',
          (s) => s.reply(200, [srv(e.id, '2026-05-20', note: 'Sunucu')]));

      await cloudRepo().importFromCloud();

      final r = await row(e.id);
      expect(r!.note, 'Yerel');
      expect(r.dirty, isTrue);
    });

    test('bekleyen tombstone dirilmez (R2)', () async {
      final e = await save(20);
      await localRepo().deleteEntry(e.id);
      adapter.onGet('/cycle/settings', (s) => s.reply(200, {}));
      adapter.onGet('/cycle/entries', (s) => s.reply(200, [srv(e.id, '2026-05-20')]));

      await cloudRepo().importFromCloud();

      final r = await row(e.id);
      expect(r!.isDeleted, isTrue);
      expect(r.dirty, isTrue);
    });

    test('sunucuda olmayan temiz satır silinir; temiz satır güncellenir + serverUpdatedAt (R4)',
        () async {
      final gone = await save(1);
      final kept = await save(2);
      await markClean(gone.id);
      await markClean(kept.id);
      adapter.onGet('/cycle/settings', (s) => s.reply(200, {}));
      adapter.onGet(
          '/cycle/entries',
          (s) => s.reply(200, [
                srv(kept.id, '2026-05-02',
                    note: 'Güncel', updatedAt: '2026-05-21T08:00:00Z')
              ]));

      await cloudRepo().importFromCloud();

      expect(await row(gone.id), isNull);
      final k = await row(kept.id);
      expect(k!.note, 'Güncel');
      // drift DateTime'ı yerel saatte döndürür → anı karşılaştır.
      expect(k.serverUpdatedAt!.toUtc(), DateTime.utc(2026, 5, 21, 8));
    });

    test('sunucu boş liste → silme yok (K-2)', () async {
      final e = await save(1);
      await markClean(e.id);
      adapter.onGet('/cycle/settings', (s) => s.reply(200, {}));
      adapter.onGet('/cycle/entries', (s) => s.reply(200, []));

      await cloudRepo().importFromCloud();
      expect(await row(e.id), isNotNull);
    });

    test('oran koruması: >5 ve >%50 → silme atlanır', () async {
      final ids = <String>[];
      for (var i = 1; i <= 10; i++) {
        final e = await save(i);
        await markClean(e.id);
        ids.add(e.id);
      }
      adapter.onGet('/cycle/settings', (s) => s.reply(200, {}));
      adapter.onGet(
          '/cycle/entries',
          (s) => s.reply(200, [
                for (var i = 0; i < 4; i++) srv(ids[i], '2026-05-0${i + 1}')
              ]));

      await cloudRepo().importFromCloud();
      for (final id in ids) {
        expect(await row(id), isNotNull);
      }
    });

    test('R4 ile çapa gününün kaydı silinse de motor çapadan (firstPeriodDate) sürer',
        () async {
      // Çapa = 1 Mayıs (settings), kayıtlar 1-3 Mayıs temiz. Sunucu 1 Mayıs'ı
      // artık döndürmüyor (başka cihazda silindi) → yerelden kalkar.
      await localRepo().patchSettings({'first_period_date': '2026-05-01'});
      final a = await save(1);
      final b = await save(2);
      final c = await save(3);
      for (final id in [a.id, b.id, c.id]) {
        await markClean(id);
      }
      // Ayar GET'i O6 kapsamı (commit 6); burada sunucu çapayı aynen döndürür
      // ki test yalnız R4 silmesinin motor etkisini ölçsün.
      adapter.onGet('/cycle/settings',
          (s) => s.reply(200, {'first_period_date': '2026-05-01'}));
      adapter.onGet('/cycle/entries',
          (s) => s.reply(200, [srv(b.id, '2026-05-02'), srv(c.id, '2026-05-03')]));

      final today = DateTime(2026, 5, 10);
      final before = computeStatus(
          await localRepo().getSettings(), await localRepo().listEntries(),
          today: today);
      expect(before.mode, CycleMode.active);

      await cloudRepo().importFromCloud();
      expect(await row(a.id), isNull);

      final settings = await localRepo().getSettings();
      final after = computeStatus(settings, await localRepo().listEntries(),
          today: today);
      expect(settings.firstPeriodDate, DateTime(2026, 5, 1));
      expect(after.mode, CycleMode.active,
          reason: 'çapa settings\'te durduğundan takip aktif kalır');
      // BİLİNEN SAPMA (BULGULAR.md D33 / K6 aşaması): çapa günü kaydı silinince
      // 2 Mayıs `periodStarts` ile yeni başlangıç sayılır → dayInCycle 10→9
      // kayar. Motor/çapa semantiği K6'da ele alınacak; burada yalnız "aktif
      // kalır, çapa korunur, çökmez" garanti edilir.
      expect(after.dayInCycle, lessThanOrEqualTo(before.dayInCycle));
    });
  });

  group('O7 adet — push', () {
    test('DELETE 404 → yerel temizlenir, tekrar denenmez', () async {
      final e = await save(1);
      await localRepo().deleteEntry(e.id);
      var calls = 0;
      adapter.onDelete('/cycle/entries/${e.id}', (s) {
        calls++;
        s.reply(404, {'detail': 'Not found'});
      });
      await cloudRepo().migrateToCloud();
      expect(await row(e.id), isNull);
      await cloudRepo().migrateToCloud();
      expect(calls, 1);
    });

    test('DELETE 503 → tombstone dirty kalır', () async {
      final e = await save(1);
      await localRepo().deleteEntry(e.id);
      adapter.onDelete('/cycle/entries/${e.id}', (s) => s.reply(503, {'detail': 'down'}));
      await cloudRepo().migrateToCloud();
      final r = await row(e.id);
      expect(r!.isDeleted, isTrue);
      expect(r.dirty, isTrue);
    });
  });

  // ───────── YENİ API ─────────
  group('O7 adet — bulk failed[] + pushErrors', () {
    test('failed[] satırı dirty kalır ve pushErrors\'a yazılır; saved temizlenir',
        () async {
      final ok = await save(1);
      final bad = await save(2);
      adapter.onPost(
          '/cycle/entries/bulk',
          (s) => s.reply(200, {
                'saved': [ok.id],
                'failed': [
                  {'id': bad.id, 'error': 'date gerekli'}
                ],
              }),
          data: Matchers.any);
      final repo = cloudRepo();
      await repo.migrateToCloud();
      expect((await row(ok.id))!.dirty, isFalse);
      expect((await row(bad.id))!.dirty, isTrue);
      expect(repo.pushErrors[bad.id], contains('date gerekli'));
    });

    test('bulk 422 → dirty kalır + pushErrors; 503 → not yok', () async {
      final e = await save(1);
      adapter.onPost('/cycle/entries/bulk', (s) => s.reply(422, {'detail': 'bad'}),
          data: Matchers.any);
      final repo = cloudRepo();
      await repo.migrateToCloud();
      expect((await row(e.id))!.dirty, isTrue);
      expect(repo.pushErrors[e.id], contains('422'));

      adapter.onPost('/cycle/entries/bulk', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      final repo2 = cloudRepo();
      await repo2.migrateToCloud();
      expect(repo2.pushErrors.containsKey(e.id), isFalse);
    });
  });

  // ───────── O8 (istemci kısmı): aynı güne eşzamanlı çift kayıt ─────────
  group('O8 adet — saveEntry serileştirme', () {
    test('aynı güne eşzamanlı iki saveEntry → TEK satır (aynı id)', () async {
      final repo = localRepo();
      final e1 = CycleEntry(id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.medium);
      final e2 = CycleEntry(id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.heavy);
      final results = await Future.wait([repo.saveEntry(e1), repo.saveEntry(e2)]);

      final rows = await (db.select(db.cycleEntries)
            ..where((r) => r.date.equals(DateTime(2026, 6, 1))))
          .get();
      expect(rows, hasLength(1), reason: 'gün başına tek kayıt');
      expect(results[0].id, results[1].id);
      expect(rows.single.flow, 'heavy', reason: 'son yazan kazanır');
    });

    test('farklı günler serileşse de hepsi yazılır', () async {
      final repo = localRepo();
      await Future.wait([
        for (var d = 1; d <= 5; d++)
          repo.saveEntry(CycleEntry(id: '', date: DateTime(2026, 7, d), flow: FlowLevel.light)),
      ]);
      final rows = await (db.select(db.cycleEntries)).get();
      expect(rows, hasLength(5));
    });
  });
}
