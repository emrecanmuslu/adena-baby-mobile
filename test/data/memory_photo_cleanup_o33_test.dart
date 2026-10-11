import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/memory_repository.dart';

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

/// O33 (ek not) — anı satırı yerelden kalıcı silinince (purge, pull R4,
/// discard, tombstone DELETE başarısı) yerel fotoğraf dosyası da diskten silinir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late MemoryRepository repo;
  late Directory tmp;

  setUp(() async {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    repo = MemoryRepository(db, api, 'u1', (_) => true);
    tmp = await Directory.systemTemp.createTemp('o33');
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> photo(String name) async {
    final f = File('${tmp.path}/$name.jpg');
    await f.writeAsBytes([1, 2, 3]);
    return f;
  }

  Future<void> seed(String id, File f, {bool deleted = false, bool dirty = false}) =>
      db.into(db.memories).insert(MemoriesCompanion.insert(
          id: id,
          baby: 'b1',
          date: DateTime(2026, 5, 1),
          localPhotoPath: Value(f.path),
          isDeleted: Value(deleted),
          dirty: Value(dirty)));

  test('purgeBaby fotoğraf dosyalarını siler', () async {
    final f = await photo('p1');
    await seed('m1', f);
    await repo.purgeBaby('b1');
    expect(await f.exists(), isFalse);
  });

  test('pull R4 ile silinen (başka üyenin sildiği) anının fotoğrafı silinir', () async {
    final f = await photo('p2');
    await seed('m2', f);
    adapter.onGet('/babies/b1/memories', (s) => s.reply(200, [
          {'id': 'other', 'date': '2026-05-02', 'title': '', 'note': '', 'first_tag': ''}
        ]));
    await repo.importFromCloud('b1');
    expect(await (db.select(db.memories)..where((m) => m.id.equals('m2'))).get(), isEmpty);
    expect(await f.exists(), isFalse);
  });

  test('tombstone DELETE başarısı (ve 404) sonrası fotoğraf silinir', () async {
    final f = await photo('p3');
    await seed('m3', f, deleted: true, dirty: true);
    adapter.onDelete('/babies/b1/memories/m3', (s) => s.reply(404, {}));
    await repo.pushDirty('b1');
    expect(await f.exists(), isFalse);
  });

  test('discardLocal fotoğrafı siler', () async {
    final f = await photo('p4');
    await seed('m4', f);
    await repo.discardLocal('m4');
    expect(await f.exists(), isFalse);
  });
}
