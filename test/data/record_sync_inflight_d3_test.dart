import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/record_repository.dart';

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

/// D3 — damga drift'te saniye hassasiyetli: uçuş sırasında AYNI saniyede
/// yeniden düzenlenen kayıt "applied" ile temizlenip ikinci düzenleme
/// gönderilmiyordu. İçerik de karşılaştırılır → dirty kalır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aynı saniyede uçuş-içi düzenleme → dirty kalır', () async {
    final api = ApiClient(_FakeTokens());
    final adapter = DioAdapter(dio: api.dio);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = RecordRepository(db, api);
    final stamp = DateTime(2026, 6, 1, 10, 0, 0);
    await db.into(db.records).insert(RecordsCompanion.insert(
        id: 'r1', baby: 'b1', type: 'feed', ts: DateTime(2026, 6, 1),
        data: const Value('{"ml":100}'), dirty: const Value(true),
        clientUpdatedAt: Value(stamp)));
    // İstek yoldayken kullanıcı aynı saniye içinde düzenler (damga aynı).
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      await (db.update(db.records)..where((r) => r.id.equals('r1'))).write(
          RecordsCompanion(data: const Value('{"ml":120}'), clientUpdatedAt: Value(stamp)));
      h.next(o);
    }));
    adapter.onPost('/sync', (s) => s.reply(200, {
          'applied': ['r1'], 'conflicts': [], 'server_changes': [], 'next_cursor': 'c1'
        }), data: Matchers.any);

    await repo.sync('b1');

    final row = await (db.select(db.records)..where((r) => r.id.equals('r1'))).getSingle();
    expect(row.dirty, isTrue, reason: 'ikinci düzenleme (ml 120) gönderilmeli');
    expect(row.data, '{"ml":120}');
  });
}
