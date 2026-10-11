import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/memory_repository.dart';

/// O5 (BULGULAR.md / TASARIM-SENKRON.md R1, R2, R4, R5, R8): anı pull'u dirty
/// satırı ve tombstone'u sunucu kopyasıyla eziyordu; sunucuda silinen anı
/// yerelden hiç kalkmıyordu; DELETE 404 sonsuza dek yeniden deneniyordu;
/// list() ağı bekliyordu.
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

  MemoryRepository localRepo() => MemoryRepository(db, api, 'u1', (_) => false);
  MemoryRepository cloudRepo() => MemoryRepository(db, api, 'u1', (_) => true);

  const baby = 'baby-1';
  const path = '/babies/$baby/memories';

  Map<String, dynamic> srv(String id, String title, {String? photo}) => {
        'id': id,
        'date': '2026-05-20',
        'title': title,
        'note': '',
        'photo': photo,
        'first_tag': '',
        'updated_at': '2026-05-20T10:00:00Z',
      };

  Future<MemoryRow?> row(String id) =>
      (db.select(db.memories)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<void> markClean(String id) =>
      (db.update(db.memories)..where((r) => r.id.equals(id)))
          .write(const MemoriesCompanion(dirty: Value(false)));

  // ───────── MEVCUT API (importFromCloud / pushDirty) ─────────
  group('O5 anı — pull (importFromCloud)', () {
    test('dirty yerel düzenleme pull sonrası korunur (R1)', () async {
      final m = await localRepo().create(baby,
          date: DateTime(2026, 5, 20), title: 'Yerel düzenleme'); // dirty
      adapter.onGet(path, (s) => s.reply(200, [srv(m.id, 'Sunucu')]));

      await cloudRepo().importFromCloud(baby);

      final r = await row(m.id);
      expect(r!.title, 'Yerel düzenleme');
      expect(r.dirty, isTrue);
    });

    test('bekleyen tombstone pull ile dirilmez (R2)', () async {
      final m = await localRepo().create(baby, date: DateTime(2026, 5, 20));
      await localRepo().delete(baby, m.id); // isDeleted + dirty
      adapter.onGet(path, (s) => s.reply(200, [srv(m.id, 'Sunucu')]));

      await cloudRepo().importFromCloud(baby);

      final r = await row(m.id);
      expect(r!.isDeleted, isTrue);
      expect(r.dirty, isTrue);
    });

    test('sunucuda olmayan temiz satır silinir (R4); temiz satır güncellenir',
        () async {
      final gone = await localRepo().create(baby, date: DateTime(2026, 5, 1));
      final kept = await localRepo().create(baby, date: DateTime(2026, 5, 2));
      await markClean(gone.id);
      await markClean(kept.id);
      adapter.onGet(path, (s) => s.reply(200, [srv(kept.id, 'Güncel')]));

      await cloudRepo().importFromCloud(baby);

      expect(await row(gone.id), isNull);
      expect((await row(kept.id))!.title, 'Güncel');
    });

    test('sunucu boş liste → silme yok (K-2)', () async {
      final m = await localRepo().create(baby, date: DateTime(2026, 5, 1));
      await markClean(m.id);
      adapter.onGet(path, (s) => s.reply(200, []));

      await cloudRepo().importFromCloud(baby);
      expect(await row(m.id), isNotNull);
    });

    test('oran koruması: >5 ve >%50 silinecekse silme atlanır', () async {
      final ids = <String>[];
      for (var i = 0; i < 10; i++) {
        final m = await localRepo().create(baby, date: DateTime(2026, 5, 1 + i));
        await markClean(m.id);
        ids.add(m.id);
      }
      // Sunucu yalnız 4'ünü döndürüyor → 6 silinecek (6>5 ve 6*2>10) → atla.
      adapter.onGet(
          path, (s) => s.reply(200, [for (final id in ids.take(4)) srv(id, 't')]));

      await cloudRepo().importFromCloud(baby);
      for (final id in ids) {
        expect(await row(id), isNotNull, reason: 'oran koruması $id');
      }
    });

    test('yüklenmemiş yerel foto: dirty satır korunur, temiz satırda yol kalır',
        () async {
      // dirty + yerel foto → dokunulmaz
      final d = await localRepo().create(baby, date: DateTime(2026, 5, 1));
      await (db.update(db.memories)..where((r) => r.id.equals(d.id))).write(
          const MemoriesCompanion(localPhotoPath: Value('/local/d.jpg')));
      // temiz + yerel foto → sunucu URL'i gelir, yerel yol korunur
      final c = await localRepo().create(baby, date: DateTime(2026, 5, 2));
      await (db.update(db.memories)..where((r) => r.id.equals(c.id))).write(
          const MemoriesCompanion(
              localPhotoPath: Value('/local/c.jpg'), dirty: Value(false)));
      adapter.onGet(
          path,
          (s) => s.reply(200, [
                srv(d.id, 'S', photo: 'https://cdn/d.jpg'),
                srv(c.id, 'S', photo: 'https://cdn/c.jpg'),
              ]));

      await cloudRepo().importFromCloud(baby);

      final rd = await row(d.id);
      expect(rd!.photo, isNull);
      expect(rd.localPhotoPath, '/local/d.jpg');
      expect(rd.dirty, isTrue);
      final rc = await row(c.id);
      expect(rc!.photo, 'https://cdn/c.jpg');
      expect(rc.localPhotoPath, '/local/c.jpg');
    });
  });

  group('O5 anı — push (DELETE sınıflandırması)', () {
    test('DELETE 404 → yerel satır temizlenir, tekrar denenmez', () async {
      final m = await localRepo().create(baby, date: DateTime(2026, 5, 1));
      await localRepo().delete(baby, m.id);
      var calls = 0;
      adapter.onDelete('$path/${m.id}', (s) {
        calls++;
        s.reply(404, {'detail': 'Not found'});
      });

      await cloudRepo().pushDirty(baby);
      expect(await row(m.id), isNull);
      await cloudRepo().pushDirty(baby);
      expect(calls, 1, reason: 'ikinci turda DELETE atılmamalı');
    });

    test('DELETE 503 → tombstone dirty kalır', () async {
      final m = await localRepo().create(baby, date: DateTime(2026, 5, 1));
      await localRepo().delete(baby, m.id);
      adapter.onDelete('$path/${m.id}', (s) => s.reply(503, {'detail': 'down'}));

      await cloudRepo().pushDirty(baby);
      final r = await row(m.id);
      expect(r!.isDeleted, isTrue);
      expect(r.dirty, isTrue);
    });
  });

  // ───────── YENİ API (watch / syncIfCloud / pushErrors) ─────────
  group('O5 anı — R8 stream + pushErrors', () {
    test('watch: yerel yazım ağ beklemeden akışa düşer (cloud açık, sunucu yok)',
        () async {
      final repo = cloudRepo(); // stub yok → push başarısız, yutulur
      final stream = repo.watch(baby);
      expect(await stream.first, isEmpty);
      await repo.create(baby, date: DateTime(2026, 5, 1), title: 'Anında');
      final after = await repo.watch(baby).first;
      expect(after.map((m) => m.title), ['Anında']);
    });

    test('syncIfCloud: cloud kapalıyken ağa çıkmaz; açıkken hata yutulur',
        () async {
      await localRepo().syncIfCloud(baby); // stub yok, istek de yok
      await cloudRepo().syncIfCloud(baby); // stub yok → hata yutulur
    });

    test('POST 422 → dirty kalır, pushErrors notu; 503 → not yok', () async {
      final repo = cloudRepo();
      final a = await localRepo().create(baby, date: DateTime(2026, 5, 1));
      adapter.onPost(path, (s) => s.reply(422, {'title': ['x']}),
          data: Matchers.any);
      await repo.pushDirty(baby);
      expect((await row(a.id))!.dirty, isTrue);
      expect((await row(a.id))!.pushError, contains('422'));

      adapter.onPost(path, (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      final repo2 = cloudRepo();
      await repo2.pushDirty(baby);
      // K-1: kolon süreç/örnek ömrünü aşar — 503 notu YAZMAZ, 422 notu kalır.
      expect((await row(a.id))!.pushError, contains('422'));
    });

    test('pull ağ hatasında hiçbir şey silinmez', () async {
      final m = await localRepo().create(baby, date: DateTime(2026, 5, 1));
      await markClean(m.id);
      adapter.onGet(
          path,
          (s) => s.throws(
              0,
              DioException(
                  requestOptions: RequestOptions(path: path),
                  type: DioExceptionType.connectionError)));
      await cloudRepo().syncIfCloud(baby);
      expect(await row(m.id), isNotNull);
    });
  });
}
