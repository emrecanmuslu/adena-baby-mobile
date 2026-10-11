import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/memory_repository.dart';
import 'package:adena_baby/data/mom_repository.dart';
import 'package:adena_baby/models/cycle.dart';
import 'package:adena_baby/models/mom_entry.dart';

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

/// Yol bazlı yanıt; [midFlight] yalnız [slowPath] isteği sürerken bir kez çalışır.
class _Adapter implements HttpClientAdapter {
  final String slowPath;
  final Future<void> Function() midFlight;
  final Map<String, dynamic> Function(RequestOptions) reply;
  final requests = <RequestOptions>[];
  var _fired = false;
  _Adapter({required this.slowPath, required this.midFlight, required this.reply});
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    if (o.path == slowPath && !_fired) {
      _fired = true;
      await midFlight();
    }
    return ResponseBody.fromString(jsonEncode(reply(o)), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// I3 (INCELEME.md) — R5 uçuş-içi koruması bulk/POST yollarında: adet kaydı bulk
/// `saved` → uçuşta düzenlenen satır dirty KALIR; anne/anı: uçuşta silinen
/// satırın tombstone'u dirty kalır ve DELETE bir sonraki turda gider (eskiden
/// `dirty=false` yazılıp satır yerelde gizli, sunucuda canlı "zombi" kalıyordu).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ApiClient api;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = ApiClient(_Tokens());
    LocalSession.setActiveAccount('u1');
    await db.into(db.babies).insert(
        BabiesCompanion.insert(id: 'b1', name: 'T', accountId: const Value('u1')));
  });
  tearDown(() => db.close());

  test('adet kaydı: bulk uçuştayken aynı gün yeniden düzenlendi → dirty kalır, yeni not; '
      'sonraki tur yeni notu gönderir', () async {
    late CycleRepository repo;
    final day = DateTime(2026, 5, 1);
    final adapter = _Adapter(
      slowPath: '/cycle/entries/bulk',
      midFlight: () async {
        await repo.saveEntry(CycleEntry(id: '', date: day, note: 'yeni'));
      },
      reply: (o) => {
        'saved': [for (final e in o.data as List) (e as Map)['id']],
        'failed': [],
      },
    );
    api.dio.httpClientAdapter = adapter;
    repo = CycleRepository(db, api, () => false); // satır içi push yok; elle tur
    await repo.saveEntry(CycleEntry(id: '', date: day, note: 'eski'));

    await repo.migrateToCloud(); // _pushDirtyEntries

    var r = await (db.select(db.cycleEntries)).getSingle();
    expect(r.note, 'yeni');
    expect(r.dirty, isTrue, reason: 'uçuş içi düzenleme bir sonraki turda gitmeli');

    await repo.migrateToCloud();
    final bulks = adapter.requests.where((q) => q.path == '/cycle/entries/bulk').toList();
    expect(bulks, hasLength(2));
    expect(((bulks.last.data as List).single as Map)['note'], 'yeni');
    r = await (db.select(db.cycleEntries)).getSingle();
    expect(r.dirty, isFalse);
  });

  test('anne takibi: bulk uçuştayken silindi → tombstone dirty kalır; sonraki tur DELETE atar',
      () async {
    late MomRepository repo;
    final adapter = _Adapter(
      slowPath: '/babies/b1/mom-entries/bulk',
      midFlight: () async {
        final id = (await (db.select(db.momEntries)).getSingle()).id;
        await repo.delete('b1', id);
      },
      reply: (o) => o.method == 'DELETE'
          ? {}
          : {
              'saved': [for (final e in o.data as List) (e as Map)['id']],
              'failed': [],
            },
    );
    api.dio.httpClientAdapter = adapter;
    repo = MomRepository(db, api, 'me', (_) => false);
    await repo.add('b1', kind: MomKind.note, date: DateTime(2026, 5, 1), note: 'n');

    await repo.pushDirty('b1');
    final r = await (db.select(db.momEntries)).getSingle();
    expect(r.isDeleted, isTrue);
    expect(r.dirty, isTrue, reason: 'silme bir sonraki turda DELETE olarak gitmeli');

    await repo.pushDirty('b1');
    expect(adapter.requests.last.method, 'DELETE');
    expect(await (db.select(db.momEntries)).get(), isEmpty);
  });

  test('anı: POST uçuştayken silindi → tombstone dirty kalır; sonraki tur DELETE atar',
      () async {
    late MemoryRepository repo;
    final adapter = _Adapter(
      slowPath: '/babies/b1/memories',
      midFlight: () async {
        final id = (await (db.select(db.memories)).getSingle()).id;
        await repo.delete('b1', id);
      },
      reply: (o) => o.method == 'DELETE'
          ? {}
          : {'id': 'x', 'photo': null, 'updated_at': '2026-05-01T00:00:00Z'},
    );
    api.dio.httpClientAdapter = adapter;
    repo = MemoryRepository(db, api, 'me', (_) => false);
    await repo.create('b1', date: DateTime(2026, 5, 1), title: 'ilk');

    await repo.pushDirty('b1');
    final r = await (db.select(db.memories)).getSingle();
    expect(r.isDeleted, isTrue);
    expect(r.dirty, isTrue, reason: 'silme bir sonraki turda DELETE olarak gitmeli');

    await repo.pushDirty('b1');
    expect(adapter.requests.last.method, 'DELETE');
    expect(await (db.select(db.memories)).get(), isEmpty);
  });

  test('anı: uçuşta değişiklik yoksa eski davranış (dirty=false, foto/damga yazılır)', () async {
    final adapter = _Adapter(
      slowPath: '/none',
      midFlight: () async {},
      reply: (_) => {'id': 'x', 'photo': 'http://srv/p.jpg', 'updated_at': '2026-05-01T00:00:00Z'},
    );
    api.dio.httpClientAdapter = adapter;
    final repo = MemoryRepository(db, api, 'me', (_) => false);
    await repo.create('b1', date: DateTime(2026, 5, 1), title: 'ilk');
    await repo.pushDirty('b1');
    final r = await (db.select(db.memories)).getSingle();
    expect(r.dirty, isFalse);
    expect(r.photo, 'http://srv/p.jpg');
    expect(r.serverUpdatedAt, isNotNull);
  });
}
