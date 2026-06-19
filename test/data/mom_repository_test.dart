import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/mom_repository.dart';
import 'package:adena_baby/models/mom_entry.dart';

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

  MomRepository localRepo({String user = 'mom-1'}) =>
      MomRepository(db, api, user, (_) => false);
  MomRepository cloudRepo({String user = 'mom-1'}) =>
      MomRepository(db, api, user, (_) => true);

  group('add — kind bütünlüğü + yerel drift (dirty, client UUID)', () {
    test('weight kaydı: weightKg saklanır, dirty=true, createdBy set', () async {
      final repo = localRepo();
      final e = await repo.add('baby-1',
          kind: MomKind.weight, date: DateTime(2026, 6, 1), weightKg: 68.5);

      expect(e.kind, MomKind.weight);
      expect(e.weightKg, 68.5);
      expect(e.id, isNotEmpty);

      final row = await (db.select(db.momEntries)
            ..where((r) => r.id.equals(e.id)))
          .getSingle();
      expect(row.kind, 'weight');
      expect(row.weightKg, 68.5);
      expect(row.dirty, isTrue);
      expect(row.createdBy, 'mom-1');
      expect(row.isDeleted, isFalse);
      expect(row.clientUpdatedAt, isNotNull);
    });

    test('appointment kaydı: title/note saklanır', () async {
      final e = await localRepo().add('baby-1',
          kind: MomKind.appointment,
          date: DateTime(2026, 6, 2),
          title: 'Doktor',
          note: 'saat 10');
      expect(e.kind, MomKind.appointment);
      expect(e.title, 'Doktor');
      expect(e.note, 'saat 10');
      expect(e.weightKg, isNull);
    });

    test('note kaydı: boş title/note modelde null olur', () async {
      // boş string title/note → _toModel null'a çevirir
      final id = (await localRepo()
              .add('baby-1', kind: MomKind.note, date: DateTime(2026, 6, 3)))
          .id;
      await (db.update(db.momEntries)..where((r) => r.id.equals(id)))
          .write(const MomEntriesCompanion(
              title: Value(''), note: Value('')));
      final e = (await localRepo().list('baby-1')).single;
      expect(e.kind, MomKind.note);
      expect(e.title, isNull);
      expect(e.note, isNull);
    });
  });

  group('list — reaktif okuma (yeni→eski, tombstone gizli)', () {
    test('tarihe göre azalan, silinen gizli, bebek izolasyonu', () async {
      final repo = localRepo();
      await repo.add('baby-1',
          kind: MomKind.weight, date: DateTime(2026, 1, 1), weightKg: 60);
      final mid = await repo.add('baby-1',
          kind: MomKind.weight, date: DateTime(2026, 6, 1), weightKg: 65);
      await repo.add('baby-2',
          kind: MomKind.weight, date: DateTime(2026, 6, 1), weightKg: 99);

      var list = await repo.list('baby-1');
      expect(list.map((e) => e.date).toList(),
          [DateTime(2026, 6, 1), DateTime(2026, 1, 1)]);

      await repo.delete('baby-1', mid.id);
      list = await repo.list('baby-1');
      expect(list.length, 1);
      expect(list.single.date, DateTime(2026, 1, 1));
    });
  });

  group('delete — soft-delete tombstone (cloud kapalı)', () {
    test('isDeleted+dirty, satır kalır', () async {
      final e = await localRepo()
          .add('baby-1', kind: MomKind.note, date: DateTime(2026, 1, 1));
      await localRepo().delete('baby-1', e.id);
      final row = await (db.select(db.momEntries)
            ..where((r) => r.id.equals(e.id)))
          .getSingle();
      expect(row.isDeleted, isTrue);
      expect(row.dirty, isTrue);
    });
  });

  group('_pull — JSON → satır eşleme (importFromCloud)', () {
    test('kind/weight_kg/created_by ayrıştırılır, dirty=false', () async {
      adapter.onGet('/babies/baby-1/mom-entries', (s) {
        s.reply(200, [
          {
            'id': 'srv-1',
            'kind': 'weight',
            'date': '2026-05-20T00:00:00Z',
            'weight_kg': '70.2',
            'title': null,
            'note': null,
            'created_by': 'srv-user',
          },
          {
            // kind eksik → 'note' varsayımı
            'id': 'srv-2',
            'date': '2026-05-21T00:00:00Z',
          }
        ]);
      });

      await cloudRepo().importFromCloud('baby-1');

      final r1 = await (db.select(db.momEntries)
            ..where((r) => r.id.equals('srv-1')))
          .getSingle();
      expect(r1.kind, 'weight');
      expect(r1.weightKg, 70.2);
      expect(r1.createdBy, 'srv-user');
      expect(r1.dirty, isFalse);

      final r2 = await (db.select(db.momEntries)
            ..where((r) => r.id.equals('srv-2')))
          .getSingle();
      expect(r2.kind, 'note');
    });
  });

  group('pushDirty — POST create + dirty temizleme', () {
    test('toCreateJson payload gönderir, satırı temizler', () async {
      await localRepo().add('baby-1',
          kind: MomKind.weight, date: DateTime(2026, 4, 4), weightKg: 72.0);
      final row = await (db.select(db.momEntries)
            ..where((r) => r.baby.equals('baby-1')))
          .getSingle();

      var posted = false;
      adapter.onPost(
        '/babies/baby-1/mom-entries/bulk',
        (s) {
          posted = true;
          s.reply(200, {'saved': [row.id]});
        },
        data: Matchers.any,
      );

      await cloudRepo().pushDirty('baby-1');

      expect(posted, isTrue);
      final after = await (db.select(db.momEntries)
            ..where((r) => r.id.equals(row.id)))
          .getSingle();
      expect(after.dirty, isFalse);
    });

    test('tombstone → DELETE + kalıcı silme', () async {
      final e = await localRepo()
          .add('baby-1', kind: MomKind.note, date: DateTime(2026, 4, 4));
      await localRepo().delete('baby-1', e.id);

      var deleted = false;
      adapter.onDelete('/babies/baby-1/mom-entries/${e.id}', (s) {
        deleted = true;
        s.reply(204, null);
      });

      await cloudRepo().pushDirty('baby-1');
      expect(deleted, isTrue);
      final row = await (db.select(db.momEntries)
            ..where((r) => r.id.equals(e.id)))
          .getSingleOrNull();
      expect(row, isNull);
    });

    test('hata → dirty kalır', () async {
      await localRepo().add('baby-1',
          kind: MomKind.weight, date: DateTime(2026, 4, 4), weightKg: 50);
      adapter.onPost('/babies/baby-1/mom-entries',
          (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);
      await cloudRepo().pushDirty('baby-1');
      final row = await (db.select(db.momEntries)
            ..where((r) => r.baby.equals('baby-1')))
          .getSingle();
      expect(row.dirty, isTrue);
    });
  });

  group('markAllDirty / purgeBaby', () {
    test('markAllDirty tüm bebek satırlarını dirty yapar', () async {
      final e = await localRepo()
          .add('baby-1', kind: MomKind.note, date: DateTime(2026, 1, 1));
      await (db.update(db.momEntries)..where((r) => r.id.equals(e.id)))
          .write(const MomEntriesCompanion(dirty: Value(false)));

      await localRepo().markAllDirty('baby-1');
      final row = await (db.select(db.momEntries)
            ..where((r) => r.id.equals(e.id)))
          .getSingle();
      expect(row.dirty, isTrue);
    });

    test('purgeBaby o bebeğin tüm satırlarını siler', () async {
      await localRepo()
          .add('baby-1', kind: MomKind.note, date: DateTime(2026, 1, 1));
      await localRepo()
          .add('baby-2', kind: MomKind.note, date: DateTime(2026, 1, 1));
      await localRepo().purgeBaby('baby-1');
      final rows = await (db.select(db.momEntries)).get();
      expect(rows.single.baby, 'baby-2');
    });
  });
}
