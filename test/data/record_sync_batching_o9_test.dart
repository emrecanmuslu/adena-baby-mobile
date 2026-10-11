import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// /sync'i taklit eden adapter: gönderilen `changes` id'lerini `applied` döner.
class _SyncAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> bodies = [];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final body = Map<String, dynamic>.from(options.data as Map);
    bodies.add(body);
    final ids = [for (final c in body['changes'] as List) (c as Map)['id']];
    return ResponseBody.fromString(
        jsonEncode({
          'applied': ids,
          'conflicts': [],
          'server_changes': [],
          'next_cursor': 'c${bodies.length}',
        }),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// O9 — kayıt senkronu dirty satırları SAYFALI gönderir (tek sınırsız POST
/// zayıf ağda 20 sn timeout → sonsuz başarısız tur).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1200 dirty kayıt → 500/500/200 üç POST; hepsi temizlenir, cursor ilerler',
      () async {
    final api = ApiClient(_FakeTokens());
    final adapter = _SyncAdapter();
    api.dio.httpClientAdapter = adapter;
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = RecordRepository(db, api);
    await db.batch((b) {
      for (var i = 0; i < 1200; i++) {
        b.insert(
            db.records,
            RecordsCompanion.insert(
                id: 'r$i', baby: 'b1', type: 'feed', ts: DateTime(2026, 1, 1),
                data: const Value('{}'), dirty: const Value(true),
                clientUpdatedAt: Value(DateTime(2026, 1, 1))));
      }
    });

    await repo.sync('b1');

    expect(adapter.bodies.map((b) => (b['changes'] as List).length), [500, 500, 200]);
    expect(adapter.bodies[0]['since_cursor'], isNull);
    expect(adapter.bodies[1]['since_cursor'], 'c1', reason: 'cursor sayfalar arası ilerler');
    final dirtyLeft = await (db.select(db.records)..where((r) => r.dirty.equals(true))).get();
    expect(dirtyLeft, isEmpty);
    final cur = await (db.select(db.syncCursors)).getSingle();
    expect(cur.cursor, 'c3');
  });
}
