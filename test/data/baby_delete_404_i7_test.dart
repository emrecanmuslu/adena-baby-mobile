import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';

class _Tokens implements TokenStorage {
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

/// I7 (INCELEME.md) — tombstone bebek DELETE'inde 404 = "sunucuda zaten yok" →
/// başarı (dirty=false, pushError yok); diğer repolarla tutarlı. 400 ise
/// kalıcı red olarak kalır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ApiClient api;
  late DioAdapter adapter;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = ApiClient(_Tokens());
    adapter = DioAdapter(dio: api.dio);
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1',
        name: 'T',
        accountId: const Value('u1'),
        myRole: const Value('owner'),
        isDeleted: const Value(true),
        dirty: const Value(true)));
  });
  tearDown(() => db.close());

  Future<BabyRow> row() =>
      (db.select(db.babies)..where((b) => b.id.equals('b1'))).getSingle();

  test('DELETE 404 → başarı: dirty=false, pushError null', () async {
    adapter.onDelete('/babies/b1', (s) => s.reply(404, {'detail': 'yok'}));
    await BabyRepository(db, api).pushDirty(accountId: 'u1');
    final r = await row();
    expect(r.dirty, isFalse);
    expect(r.pushError, isNull);
    expect(r.isDeleted, isTrue);
  });

  test('DELETE 400 → kalıcı red: dirty kalır, pushError HTTP 400', () async {
    adapter.onDelete('/babies/b1', (s) => s.reply(400, {'detail': 'geçersiz'}));
    await BabyRepository(db, api).pushDirty(accountId: 'u1');
    final r = await row();
    expect(r.dirty, isTrue);
    expect(r.pushError, 'HTTP 400');
  });
}
