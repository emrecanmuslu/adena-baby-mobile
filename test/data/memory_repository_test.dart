import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/memory_repository.dart';

/// Canned-token fake — interceptor token okur, atmaz.
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

  // cloud kapalı repo (free yol; ağ çağrısı yok)
  MemoryRepository localRepo({String user = 'user-1'}) =>
      MemoryRepository(db, api, user, (_) => false);
  // cloud açık repo (premium yol; sync tetiklenir)
  MemoryRepository cloudRepo({String user = 'user-1'}) =>
      MemoryRepository(db, api, user, (_) => true);

  group('create — yerel drift yazımı (dirty + client UUID + createdBy)', () {
    test('foto olmadan satır oluşturur; model alanları doğru', () async {
      final repo = localRepo();
      final m = await repo.create('baby-1',
          date: DateTime(2026, 6, 1),
          title: 'İlk gülüş',
          note: 'çok tatlı',
          firstTag: 'smile');

      expect(m.id, isNotEmpty);
      expect(m.title, 'İlk gülüş');
      expect(m.note, 'çok tatlı');
      expect(m.firstTag, 'smile');
      expect(m.isFirst, isTrue);
      expect(m.date, DateTime(2026, 6, 1));
      expect(m.photo, isNull);

      // ham satır: dirty=true, createdBy=user, client UUID atanmış
      final row = await (db.select(db.memories)
            ..where((r) => r.id.equals(m.id)))
          .getSingle();
      expect(row.dirty, isTrue);
      expect(row.createdBy, 'user-1');
      expect(row.isDeleted, isFalse);
      expect(row.clientUpdatedAt, isNotNull);
      // istemci UUID (v4) formatı
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(row.id),
          isTrue);
    });
  });

  group('list — reaktif okuma (yeni→eski, tombstone gizli)', () {
    test('tarihe göre azalan sıralı, silinen gizli', () async {
      final repo = localRepo();
      await repo.create('baby-1', date: DateTime(2026, 1, 1), title: 'eski');
      final mid =
          await repo.create('baby-1', date: DateTime(2026, 6, 1), title: 'yeni');
      await repo.create('baby-1', date: DateTime(2026, 3, 1), title: 'orta');

      var list = await repo.list('baby-1');
      expect(list.map((e) => e.title).toList(), ['yeni', 'orta', 'eski']);

      await repo.delete('baby-1', mid.id);
      list = await repo.list('baby-1');
      expect(list.map((e) => e.title).toList(), ['orta', 'eski']);
    });

    test('farklı bebek satırlarını sızdırmaz', () async {
      final repo = localRepo();
      await repo.create('baby-1', date: DateTime(2026, 1, 1), title: 'A');
      await repo.create('baby-2', date: DateTime(2026, 1, 1), title: 'B');
      final list = await repo.list('baby-1');
      expect(list.map((e) => e.title), ['A']);
    });
  });

  group('delete — soft-delete tombstone', () {
    test('isDeleted+dirty işaretler, satırı silmez (cloud kapalı)', () async {
      final repo = localRepo();
      final m = await repo.create('baby-1', date: DateTime(2026, 1, 1));
      await repo.delete('baby-1', m.id);

      final row = await (db.select(db.memories)
            ..where((r) => r.id.equals(m.id)))
          .getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.dirty, isTrue);
    });
  });

  group('_pull — JSON → satır eşleme (importFromCloud)', () {
    test('sunucu kaydını dirty=false yerel satıra çevirir', () async {
      adapter.onGet('/babies/baby-1/memories', (s) {
        s.reply(200, [
          {
            'id': 'srv-1',
            'date': '2026-05-20',
            'title': 'Sunucu anısı',
            'note': 'not',
            'photo': 'https://cdn/x.jpg',
            'first_tag': 'tooth',
            'created_by': 'other-user',
          }
        ]);
      });

      final repo = cloudRepo();
      await repo.importFromCloud('baby-1');

      final row = await (db.select(db.memories)
            ..where((r) => r.id.equals('srv-1')))
          .getSingle();
      expect(row.title, 'Sunucu anısı');
      expect(row.photo, 'https://cdn/x.jpg');
      expect(row.firstTag, 'tooth');
      expect(row.createdBy, 'other-user');
      expect(row.dirty, isFalse);
      expect(row.date, DateTime(2026, 5, 20));

      // model: photo (sunucu URL'i) önce gelir
      final m = (await repo.list('baby-1')).firstWhere((e) => e.id == 'srv-1');
      expect(m.photo, 'https://cdn/x.jpg');
    });
  });

  group('pushDirty — yerel dirty kayıtları sunucuya yollar', () {
    test('oluşturmayı POST eder, dönen URL ile satırı temizler', () async {
      // önce cloud kapalı oluştur (dirty kalsın), sonra cloud açıkken push
      await localRepo().create('baby-1',
          date: DateTime(2026, 4, 4), title: 'push edilecek', firstTag: 'word');
      final row = await (db.select(db.memories)
            ..where((r) => r.baby.equals('baby-1')))
          .getSingle();

      Map<String, dynamic>? captured;
      adapter.onPost(
        '/babies/baby-1/memories',
        (s) => s.reply(201, {
          'id': row.id,
          'date': '2026-04-04',
          'title': 'push edilecek',
          'photo': 'https://cdn/uploaded.jpg',
          'first_tag': 'word',
        }),
        data: Matchers.any,
      );

      await cloudRepo().pushDirty('baby-1');

      final after = await (db.select(db.memories)
            ..where((r) => r.id.equals(row.id)))
          .getSingle();
      expect(after.dirty, isFalse);
      expect(after.photo, 'https://cdn/uploaded.jpg');
      captured; // çağrı yapıldıysa stub eşleşti
    });

    test('tombstone push → DELETE çağrısı + satır kalıcı silinir', () async {
      final m = await localRepo()
          .create('baby-1', date: DateTime(2026, 4, 4), title: 'silinecek');
      // cloud kapalıyken sil → dirty tombstone
      await localRepo().delete('baby-1', m.id);

      var deleteCalled = false;
      adapter.onDelete('/babies/baby-1/memories/${m.id}', (s) {
        deleteCalled = true;
        s.reply(204, null);
      });

      await cloudRepo().pushDirty('baby-1');

      expect(deleteCalled, isTrue);
      final row = await (db.select(db.memories)
            ..where((r) => r.id.equals(m.id)))
          .getSingleOrNull();
      expect(row, isNull); // kalıcı silindi
    });

    test('sunucu hatasında dirty kalır (offline güvenliği)', () async {
      await localRepo()
          .create('baby-1', date: DateTime(2026, 4, 4), title: 'kalsın');
      final row = await (db.select(db.memories)
            ..where((r) => r.baby.equals('baby-1')))
          .getSingle();

      adapter.onPost('/babies/baby-1/memories',
          (s) => s.reply(500, {'detail': 'boom'}),
          data: Matchers.any);

      await cloudRepo().pushDirty('baby-1'); // yutar
      final after = await (db.select(db.memories)
            ..where((r) => r.id.equals(row.id)))
          .getSingle();
      expect(after.dirty, isTrue);
    });
  });

  group('markAllDirty — migrasyon tam yükleme işaretlemesi', () {
    test('yerel-foto satırın cloud URL temizlenir + dirty; metadata dirty olur',
        () async {
      // yerel-foto satırı (localPhotoPath dolu, cloud URL var) elle ekle
      await db.into(db.memories).insert(MemoriesCompanion.insert(
            id: 'has-local',
            baby: 'baby-1',
            date: DateTime(2026, 1, 1),
            photo: const Value('https://cdn/old.jpg'),
            localPhotoPath: const Value('/data/x.jpg'),
            dirty: const Value(false),
          ));
      // yalnız-cloud satırı (yerel kopya yok)
      await db.into(db.memories).insert(MemoriesCompanion.insert(
            id: 'cloud-only',
            baby: 'baby-1',
            date: DateTime(2026, 1, 1),
            photo: const Value('https://cdn/keep.jpg'),
            dirty: const Value(false),
          ));

      await localRepo().markAllDirty('baby-1');

      final local = await (db.select(db.memories)
            ..where((r) => r.id.equals('has-local')))
          .getSingle();
      expect(local.dirty, isTrue);
      expect(local.photo, isNull); // yeniden gönderilecek

      final cloud = await (db.select(db.memories)
            ..where((r) => r.id.equals('cloud-only')))
          .getSingle();
      expect(cloud.dirty, isTrue);
      expect(cloud.photo, 'https://cdn/keep.jpg'); // korunur
    });
  });

  group('purgeBaby — paylaşımdan düşünce yereli temizle', () {
    test('o bebeğin tüm satırlarını (tombstone dahil) kalıcı siler', () async {
      await localRepo().create('baby-1', date: DateTime(2026, 1, 1));
      final del =
          await localRepo().create('baby-1', date: DateTime(2026, 1, 2));
      await localRepo().delete('baby-1', del.id);
      await localRepo().create('baby-2', date: DateTime(2026, 1, 1));

      await localRepo().purgeBaby('baby-1');

      final remaining = await (db.select(db.memories)).get();
      expect(remaining.every((r) => r.baby == 'baby-2'), isTrue);
      expect(remaining.length, 1);
    });
  });

  group('_toModel — foto kaynağı önceliği', () {
    test('sunucu URL yoksa yerel foto yolu modelde görünür', () async {
      await db.into(db.memories).insert(MemoriesCompanion.insert(
            id: 'lp',
            baby: 'baby-1',
            date: DateTime(2026, 1, 1),
            localPhotoPath: const Value('/data/local.jpg'),
            dirty: const Value(false),
          ));
      final m = (await localRepo().list('baby-1')).single;
      expect(m.photo, '/data/local.jpg');
      expect(m.isLocalPhoto, isTrue);
    });
  });
}
