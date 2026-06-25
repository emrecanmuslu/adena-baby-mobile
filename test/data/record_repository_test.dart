import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/record_repository.dart';
import 'package:adena_baby/models/record.dart';

/// Secure storage'a dokunmadan sabit bir access token döndüren sahte depo.
/// TokenStorage somut sınıf — getter/metotları override edip statik
/// FlutterSecureStorage erişimini tamamen by-pass ediyoruz.
class _FakeTokens extends TokenStorage {
  @override
  Future<String?> get accessToken async => 'fake-access-token';

  @override
  Future<String?> get refreshToken async => null;

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
  late RecordRepository repo;

  const babyId = 'baby-1';

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    repo = RecordRepository(db, api);
  });

  tearDown(() async {
    await db.close();
  });

  // Deterministik kayıt üretici.
  Record rec(
    String id,
    RecordType type,
    DateTime ts, {
    Map<String, dynamic> data = const {},
    String? createdBy,
  }) =>
      Record(
        id: id,
        baby: babyId,
        type: type,
        ts: ts,
        data: data,
        createdBy: createdBy,
      );

  // Bir kayıt satırını id ile ham olarak oku (dirty/isDeleted kontrolü için).
  Future<RecordRow?> rawRow(String id) => (db.select(db.records)
        ..where((r) => r.id.equals(id)))
      .getSingleOrNull();

  group('upsertLocal (offline-first yazma)', () {
    test('yerel drift\'e dirty=true ile yazar, model döndüren okuma yapar',
        () async {
      final r = rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: {'sub': 'bottle', 'amount_ml': 120}, createdBy: 'u1');
      await repo.upsertLocal(r);

      final row = await rawRow('r1');
      expect(row, isNotNull);
      expect(row!.dirty, isTrue);
      expect(row.isDeleted, isFalse);
      expect(row.baby, babyId);
      expect(row.type, 'feed');
      expect(row.createdBy, 'u1');
      // ts UTC olarak saklanır (drift yereli döndürür → instant'ı karşılaştır).
      expect(row.ts.toUtc(), DateTime.utc(2026, 1, 1, 8));
      // clientUpdatedAt damgalanır (now — değerini doğrulamıyoruz, sadece var).
      expect(row.clientUpdatedAt, isNotNull);
    });

    test('polimorfik data JSON olarak round-trip korur', () async {
      final data = {
        'sub': 'breast',
        'start_ts': '2026-01-01T08:00:00.000Z',
        'left_min': 7,
        'nested': {
          'a': [1, 2, 3],
          'b': true,
        },
      };
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: data));

      final row = await rawRow('r1');
      expect(jsonDecode(row!.data), equals(data));
    });

    test('aynı id ile tekrar upsert satırı günceller (insert-or-update)',
        () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: {'amount_ml': 100}));
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 9),
          data: {'amount_ml': 200}));

      final rows = await db.select(db.records).get();
      expect(rows.length, 1);
      expect(jsonDecode(rows.first.data)['amount_ml'], 200);
      expect(rows.first.ts.toUtc(), DateTime.utc(2026, 1, 1, 9));
    });
  });

  group('softDeleteLocal (tombstone)', () {
    test('isDeleted=true + dirty=true işaretler, satırı silmez', () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      // Yazımdan sonra temizleyip silmenin dirty'yi geri açtığını görelim.
      await (db.update(db.records)..where((t) => t.id.equals('r1')))
          .write(const RecordsCompanion(dirty: Value(false)));

      await repo.softDeleteLocal('r1');

      final row = await rawRow('r1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.dirty, isTrue);
    });
  });

  group('reaktif okuma akışları', () {
    test('watch() yerel değişimde silinmemiş kayıtları yeni-önce yayar',
        () async {
      final stream = repo.watch(babyId);
      // İlk emisyon boş, sonra eklenenler.
      final emissions = <List<Record>>[];
      final sub = stream.listen(emissions.add);

      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      await repo.upsertLocal(rec('r2', RecordType.sleep, DateTime.utc(2026, 1, 1, 10)));
      // İki kayıt arasında küçük bir nefes (drift watch debounce).
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final last = emissions.last;
      expect(last.map((e) => e.id).toList(), ['r2', 'r1']); // ts desc
      await sub.cancel();
    });

    test('watch() tombstone (isDeleted) kayıtları hariç tutar', () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      await repo.upsertLocal(rec('r2', RecordType.feed, DateTime.utc(2026, 1, 1, 9)));
      await repo.softDeleteLocal('r1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final list = await repo.watch(babyId).first;
      expect(list.map((e) => e.id).toList(), ['r2']);
    });

    test('watchRecent() limit\'i uygular', () async {
      for (var i = 0; i < 5; i++) {
        await repo.upsertLocal(
            rec('r$i', RecordType.feed, DateTime.utc(2026, 1, 1, i)));
      }
      final list = await repo.watchRecent(babyId, limit: 3).first;
      expect(list.length, 3);
      // En yeni 3 (i=4,3,2).
      expect(list.map((e) => e.id).toList(), ['r4', 'r3', 'r2']);
    });

    test('watchLatestByType() tip başına yalnız MAX(ts) kaydı döndürür',
        () async {
      await repo.upsertLocal(rec('f1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      await repo.upsertLocal(rec('f2', RecordType.feed, DateTime.utc(2026, 1, 1, 12)));
      await repo.upsertLocal(rec('s1', RecordType.sleep, DateTime.utc(2026, 1, 1, 9)));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final map = await repo.watchLatestByType(babyId).first;
      expect(map.keys.toSet(), {RecordType.feed, RecordType.sleep});
      expect(map[RecordType.feed]!.id, 'f2'); // en son feed
      expect(map[RecordType.sleep]!.id, 's1');
    });

    test('watchSince() sınır tarihten itibaren kayıtları döndürür', () async {
      await repo.upsertLocal(rec('old', RecordType.feed, DateTime.utc(2026, 1, 1, 0)));
      await repo.upsertLocal(rec('new', RecordType.feed, DateTime.utc(2026, 1, 3, 0)));
      final list =
          await repo.watchSince(babyId, DateTime.utc(2026, 1, 2)).first;
      expect(list.map((e) => e.id).toList(), ['new']);
    });

    test('watchDay() yalnız o günün kayıtlarını döndürür', () async {
      // watchDay yerel günü kullanır; UTC ts'leri yerel güne göre filtreler.
      final localNoon = DateTime(2026, 1, 2, 12);
      await repo.upsertLocal(rec('inDay', RecordType.feed, localNoon));
      await repo.upsertLocal(
          rec('nextDay', RecordType.feed, DateTime(2026, 1, 3, 12)));
      final list =
          await repo.watchDay(babyId, DateTime(2026, 1, 2)).first;
      expect(list.map((e) => e.id).toList(), ['inDay']);
    });

    test('watchOngoingSleep() bitmemiş uykuyu yakalar, biteni gizler',
        () async {
      await repo.upsertLocal(rec('s1', RecordType.sleep, DateTime.utc(2026, 1, 1, 8),
          data: {'end_ts': null}));
      final ongoing = await repo.watchOngoingSleep(babyId).first;
      expect(ongoing, isNotNull);
      expect(ongoing!.id, 's1');

      // end_ts ekleyince artık ongoing değil.
      await repo.upsertLocal(rec('s1', RecordType.sleep, DateTime.utc(2026, 1, 1, 8),
          data: {'end_ts': '2026-01-01T09:00:00.000Z'}));
      final done = await repo.watchOngoingSleep(babyId).first;
      expect(done, isNull);
    });

    test('watchOngoingBreast() süren emzirmeyi son 10 içinde tarar', () async {
      await repo.upsertLocal(rec('b1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: {'sub': 'breast', 'start_ts': '2026-01-01T08:00:00.000Z'}));
      // Araya başka beslenme (bottle) — gene de yakalanmalı.
      await repo.upsertLocal(rec('f1', RecordType.feed, DateTime.utc(2026, 1, 1, 9),
          data: {'sub': 'bottle', 'amount_ml': 100}));
      final ongoing = await repo.watchOngoingBreast(babyId).first;
      expect(ongoing, isNotNull);
      expect(ongoing!.id, 'b1');
    });

    test('watchPaged() tip filtresi + limit uygular', () async {
      await repo.upsertLocal(rec('f1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      await repo.upsertLocal(rec('s1', RecordType.sleep, DateTime.utc(2026, 1, 1, 9)));
      await repo.upsertLocal(rec('f2', RecordType.feed, DateTime.utc(2026, 1, 1, 10)));
      final feeds = await repo
          .watchPaged(babyId, limit: 10, type: RecordType.feed)
          .first;
      expect(feeds.map((e) => e.id).toSet(), {'f1', 'f2'});
    });
  });

  group('presentTypes', () {
    test('SQL distinct ile var olan tipleri döndürür', () async {
      await repo.upsertLocal(rec('f1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      await repo.upsertLocal(rec('f2', RecordType.feed, DateTime.utc(2026, 1, 1, 9)));
      await repo.upsertLocal(rec('s1', RecordType.sleep, DateTime.utc(2026, 1, 1, 9)));
      final types = await repo.presentTypes(babyId);
      expect(types, {RecordType.feed, RecordType.sleep});
    });

    test('silinmiş kayıt tipini saymaz', () async {
      await repo.upsertLocal(rec('b1', RecordType.bath, DateTime.utc(2026, 1, 1, 8)));
      await repo.softDeleteLocal('b1');
      final types = await repo.presentTypes(babyId);
      expect(types, isEmpty);
    });
  });

  group('purgeBaby', () {
    test('bebeğin tüm kayıtlarını ve sync cursor\'ını siler', () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      await db.into(db.syncCursors).insertOnConflictUpdate(
            SyncCursorsCompanion(
              baby: const Value(babyId),
              cursor: const Value('2026-01-01T00:00:00.000Z'),
            ),
          );
      await repo.purgeBaby(babyId);

      expect(await db.select(db.records).get(), isEmpty);
      expect(await db.select(db.syncCursors).get(), isEmpty);
    });
  });

  group('markAllDirty', () {
    test('tüm kayıtları (tombstone dahil) dirty işaretler', () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8)));
      // Temizle.
      await (db.update(db.records)..where((t) => t.id.equals('r1')))
          .write(const RecordsCompanion(dirty: Value(false)));
      await repo.markAllDirty(babyId);
      final row = await rawRow('r1');
      expect(row!.dirty, isTrue);
    });
  });

  group('sync (delta, son-yazan-kazanır)', () {
    test('dirty satırları /sync\'e gönderir; applied olanları temizler',
        () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: {'amount_ml': 120}));

      adapter.onPost(
        '/sync',
        (server) => server.reply(200, {
          'applied': ['r1'],
          'conflicts': [],
          'server_changes': [],
          'next_cursor': '2026-01-02T00:00:00.000Z',
        }),
        data: Matchers.any,
      );

      await repo.sync(babyId);

      final row = await rawRow('r1');
      expect(row!.dirty, isFalse); // applied → temiz

      // next_cursor kaydedildi.
      final cursor = await (db.select(db.syncCursors)
            ..where((c) => c.baby.equals(babyId)))
          .getSingleOrNull();
      expect(cursor, isNotNull);
      expect(cursor!.cursor, '2026-01-02T00:00:00.000Z');
    });

    test('gönderilen changes payload\'u doğru biçimlenir (op/type/ts/data)',
        () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: {'amount_ml': 120}));
      await repo.upsertLocal(rec('r2', RecordType.sleep, DateTime.utc(2026, 1, 1, 9)));
      await repo.softDeleteLocal('r2');

      Map<String, dynamic>? sentBody;
      adapter.onPost(
        '/sync',
        (server) => server.reply(200, {
          'applied': ['r1', 'r2'],
          'conflicts': [],
          'server_changes': [],
          'next_cursor': null,
        }),
        data: Matchers.any,
      );

      // dio interceptor sonrası gövdeyi yakalamak için ayrı interceptor ekle.
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path == '/sync') sentBody = o.data as Map<String, dynamic>;
        h.next(o);
      }));

      await repo.sync(babyId);

      expect(sentBody, isNotNull);
      expect(sentBody!['baby'], babyId);
      final changes = (sentBody!['changes'] as List).cast<Map>();
      final byId = {for (final c in changes) c['id']: c};
      expect(byId['r1']!['op'], 'upsert');
      expect(byId['r1']!['type'], 'feed');
      expect(byId['r1']!['ts'], '2026-01-01T08:00:00.000Z');
      expect((byId['r1']!['data'] as Map)['amount_ml'], 120);
      expect(byId['r2']!['op'], 'delete'); // tombstone
    });

    test('conflicts: sunucu kazanır, server_record yerele uygulanır (temiz)',
        () async {
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: {'amount_ml': 120}));

      adapter.onPost(
        '/sync',
        (server) => server.reply(200, {
          'applied': [],
          'conflicts': [
            {
              'server_record': {
                'id': 'r1',
                'baby': babyId,
                'type': 'feed',
                'ts': '2026-01-01T08:00:00.000Z',
                'data': {'amount_ml': 999}, // sunucu değeri kazanır
                'is_deleted': false,
                'updated_at': '2026-01-01T08:05:00.000Z',
              }
            }
          ],
          'server_changes': [],
          'next_cursor': null,
        }),
        data: Matchers.any,
      );

      await repo.sync(babyId);

      final row = await rawRow('r1');
      expect(jsonDecode(row!.data)['amount_ml'], 999); // sunucu kazandı
      expect(row.dirty, isFalse);
      expect(row.serverUpdatedAt!.toUtc(), DateTime.utc(2026, 1, 1, 8, 5));
    });

    test('server_changes: yereldeki YENİ dirty düzenlemeyi ESKİ echo ezmez (#3)',
        () async {
      // Yerelde gönderilmemiş yeni düzenleme (upsertLocal clientUpdatedAt=now damgalar).
      await repo.upsertLocal(rec('r1', RecordType.feed, DateTime.utc(2026, 1, 1, 8),
          data: {'amount_ml': 200}));
      // Sunucu, ESKİ client_updated_at'li aynı kaydı server_changes'te yansıtır
      // (echo/başka cihazın eski sürümü). Yerel daha yeni → UYGULANMAMALI.
      adapter.onPost(
        '/sync',
        (server) => server.reply(200, {
          'applied': [],
          'conflicts': [],
          'server_changes': [
            {
              'id': 'r1',
              'baby': babyId,
              'type': 'feed',
              'ts': '2026-01-01T08:00:00.000Z',
              'data': {'amount_ml': 999}, // eski/echo değeri ezmemeli
              'is_deleted': false,
              'client_updated_at': '2020-01-01T00:00:00.000Z', // yereldekinden ESKİ
              'updated_at': '2020-01-01T00:00:00.000Z',
            }
          ],
          'next_cursor': null,
        }),
        data: Matchers.any,
      );

      await repo.sync(babyId);

      final row = await rawRow('r1');
      // Yerel yeni düzenleme korunur (999 değil 200) + dirty kalır (tekrar gönderilir).
      expect(jsonDecode(row!.data)['amount_ml'], 200);
      expect(row.dirty, isTrue);
    });

    test('server_changes: yeni sunucu kayıtları yerele temiz upsert edilir',
        () async {
      // Yerelde hiç dirty yok; sunucudan yeni kayıt gelir.
      adapter.onPost(
        '/sync',
        (server) => server.reply(200, {
          'applied': [],
          'conflicts': [],
          'server_changes': [
            {
              'id': 'srv1',
              'baby_id': babyId, // baby_id alternatif anahtar
              'type': 'diaper',
              'ts': '2026-01-05T10:00:00.000Z',
              'data': {'kind': 'wet'},
              'is_deleted': false,
              'created_by': 'partner',
              'updated_at': '2026-01-05T10:00:00.000Z',
            }
          ],
          'next_cursor': '2026-01-06T00:00:00.000Z',
        }),
        data: Matchers.any,
      );

      await repo.sync(babyId);

      final row = await rawRow('srv1');
      expect(row, isNotNull);
      expect(row!.type, 'diaper');
      expect(row.dirty, isFalse);
      expect(row.createdBy, 'partner');
      expect(jsonDecode(row.data)['kind'], 'wet');
    });

    test('since_cursor mevcut cursor\'dan gönderilir', () async {
      await db.into(db.syncCursors).insertOnConflictUpdate(
            SyncCursorsCompanion(
              baby: const Value(babyId),
              cursor: const Value('2026-01-01T00:00:00.000Z'),
            ),
          );
      Map<String, dynamic>? sentBody;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path == '/sync') sentBody = o.data as Map<String, dynamic>;
        h.next(o);
      }));
      adapter.onPost(
        '/sync',
        (server) => server.reply(200, {
          'applied': [],
          'conflicts': [],
          'server_changes': [],
          'next_cursor': null,
        }),
        data: Matchers.any,
      );
      await repo.sync(babyId);
      expect(sentBody!['since_cursor'], '2026-01-01T00:00:00.000Z');
    });
  });

  group('importFromCloud (GET sayfalama)', () {
    test('GET /babies/{id}/records sonuçlarını yerele temiz yazar', () async {
      adapter.onGet(
        '/babies/$babyId/records',
        (server) => server.reply(200, {
          'results': [
            {
              'id': 'c1',
              'baby': babyId,
              'type': 'feed',
              'ts': '2026-01-01T08:00:00.000Z',
              'data': {'amount_ml': 90},
              'is_deleted': false,
              'updated_at': '2026-01-01T08:00:00.000Z',
            }
          ],
          'next_cursor': null,
        }),
        queryParameters: {'limit': 200},
      );

      await repo.importFromCloud(babyId);

      final row = await rawRow('c1');
      expect(row, isNotNull);
      expect(row!.dirty, isFalse);
      expect(jsonDecode(row.data)['amount_ml'], 90);
    });

    test('next_cursor ile ikinci sayfayı çeker', () async {
      adapter.onGet(
        '/babies/$babyId/records',
        (server) => server.reply(200, {
          'results': [
            {
              'id': 'p1',
              'baby': babyId,
              'type': 'feed',
              'ts': '2026-01-01T08:00:00.000Z',
              'data': {},
              'is_deleted': false,
            }
          ],
          'next_cursor': 'CUR2',
        }),
        queryParameters: {'limit': 200},
      );
      adapter.onGet(
        '/babies/$babyId/records',
        (server) => server.reply(200, {
          'results': [
            {
              'id': 'p2',
              'baby': babyId,
              'type': 'feed',
              'ts': '2026-01-02T08:00:00.000Z',
              'data': {},
              'is_deleted': false,
            }
          ],
          'next_cursor': null,
        }),
        queryParameters: {'limit': 200, 'cursor': 'CUR2'},
      );

      await repo.importFromCloud(babyId);

      expect(await rawRow('p1'), isNotNull);
      expect(await rawRow('p2'), isNotNull);
    });
  });
}
