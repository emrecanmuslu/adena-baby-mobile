import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/mom_repository.dart';
import 'package:adena_baby/models/mom_entry.dart';

/// O5 (anne takibi): anı ile aynı kurallar; sunucu `updated_at` döndürmediği
/// için "dirty yerel kazanır, temiz yerel sunucuyu alır".
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

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  MomRepository localRepo() => MomRepository(db, api, 'm1', (_) => false);
  MomRepository cloudRepo() => MomRepository(db, api, 'm1', (_) => true);

  const baby = 'baby-1';
  const path = '/babies/$baby/mom-entries';

  Map<String, dynamic> srv(String id, String note) => {
        'id': id,
        'kind': 'note',
        'date': '2026-05-20T10:00:00Z',
        'weight_kg': null,
        'title': '',
        'note': note,
      };

  Future<MomEntryRow?> row(String id) =>
      (db.select(db.momEntries)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<void> markClean(String id) =>
      (db.update(db.momEntries)..where((r) => r.id.equals(id)))
          .write(const MomEntriesCompanion(dirty: Value(false)));

  Future<MomEntry> add(String note, {int day = 1}) => localRepo().add(baby,
      kind: MomKind.note, date: DateTime(2026, 5, day), note: note);

  // ───────── MEVCUT API ─────────
  group('O5 anne — pull (importFromCloud)', () {
    test('dirty yerel düzenleme korunur (R1)', () async {
      final e = await add('Yerel');
      adapter.onGet(path, (s) => s.reply(200, [srv(e.id, 'Sunucu')]));
      await cloudRepo().importFromCloud(baby);
      final r = await row(e.id);
      expect(r!.note, 'Yerel');
      expect(r.dirty, isTrue);
    });

    test('bekleyen tombstone dirilmez (R2)', () async {
      final e = await add('x');
      await localRepo().delete(baby, e.id);
      adapter.onGet(path, (s) => s.reply(200, [srv(e.id, 'Sunucu')]));
      await cloudRepo().importFromCloud(baby);
      final r = await row(e.id);
      expect(r!.isDeleted, isTrue);
      expect(r.dirty, isTrue);
    });

    test('sunucuda olmayan temiz satır silinir; temiz satır güncellenir (R4)',
        () async {
      final gone = await add('g', day: 1);
      final kept = await add('k', day: 2);
      await markClean(gone.id);
      await markClean(kept.id);
      adapter.onGet(path, (s) => s.reply(200, [srv(kept.id, 'Güncel')]));
      await cloudRepo().importFromCloud(baby);
      expect(await row(gone.id), isNull);
      expect((await row(kept.id))!.note, 'Güncel');
    });

    test('sunucu boş liste → silme yok (K-2)', () async {
      final e = await add('x');
      await markClean(e.id);
      adapter.onGet(path, (s) => s.reply(200, []));
      await cloudRepo().importFromCloud(baby);
      expect(await row(e.id), isNotNull);
    });

    test('oran koruması: >5 ve >%50 → silme atlanır', () async {
      final ids = <String>[];
      for (var i = 0; i < 10; i++) {
        final e = await add('n$i', day: 1 + i);
        await markClean(e.id);
        ids.add(e.id);
      }
      adapter.onGet(
          path, (s) => s.reply(200, [for (final id in ids.take(4)) srv(id, 'n')]));
      await cloudRepo().importFromCloud(baby);
      for (final id in ids) {
        expect(await row(id), isNotNull);
      }
    });
  });

  group('O5 anne — push (DELETE sınıflandırması)', () {
    test('DELETE 404 → yerel temizlenir, tekrar denenmez', () async {
      final e = await add('x');
      await localRepo().delete(baby, e.id);
      var calls = 0;
      adapter.onDelete('$path/${e.id}', (s) {
        calls++;
        s.reply(404, {'detail': 'Not found'});
      });
      await cloudRepo().pushDirty(baby);
      expect(await row(e.id), isNull);
      await cloudRepo().pushDirty(baby);
      expect(calls, 1);
    });

    test('DELETE 503 → tombstone dirty kalır', () async {
      final e = await add('x');
      await localRepo().delete(baby, e.id);
      adapter.onDelete('$path/${e.id}', (s) => s.reply(503, {'detail': 'down'}));
      await cloudRepo().pushDirty(baby);
      final r = await row(e.id);
      expect(r!.isDeleted, isTrue);
      expect(r.dirty, isTrue);
    });
  });

  // ───────── YENİ API ─────────
  group('O5 anne — R8 stream + pushErrors', () {
    test('watch: yerel yazım ağ beklemeden akışa düşer', () async {
      final repo = cloudRepo();
      expect(await repo.watch(baby).first, isEmpty);
      await repo.add(baby, kind: MomKind.note, date: DateTime(2026, 5, 1), note: 'Anında');
      expect((await repo.watch(baby).first).map((e) => e.note), ['Anında']);
    });

    test('bulk failed[] → o id pushErrors, diğeri temizlenir', () async {
      final ok = await add('ok', day: 1);
      final bad = await add('bad', day: 2);
      adapter.onPost(
          '$path/bulk',
          (s) => s.reply(200, {
                'saved': [ok.id],
                'failed': [
                  {'id': bad.id, 'error': 'date gerekli'}
                ],
              }),
          data: Matchers.any);
      final repo = cloudRepo();
      await repo.pushDirty(baby);
      expect((await row(ok.id))!.dirty, isFalse);
      expect((await row(bad.id))!.dirty, isTrue);
      expect((await row(bad.id))!.pushError, contains('date gerekli'));
    });

    test('bulk 422 → tümü dirty kalır + pushErrors; 503 → not yok', () async {
      final e = await add('x');
      adapter.onPost('$path/bulk', (s) => s.reply(422, {'detail': 'bad'}),
          data: Matchers.any);
      final repo = cloudRepo();
      await repo.pushDirty(baby);
      expect((await row(e.id))!.dirty, isTrue);
      expect((await row(e.id))!.pushError, contains('422'));

      adapter.onPost('$path/bulk', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      final repo2 = cloudRepo();
      await repo2.pushDirty(baby);
      // K-1: kolon kalıcı — 503 notu yazmaz, önceki 422 notu durur.
      expect((await row(e.id))!.pushError, contains('422'));
    });
  });
}
