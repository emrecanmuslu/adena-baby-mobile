import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/memory_repository.dart';
import 'package:adena_baby/data/mom_repository.dart';
import 'package:adena_baby/data/push_error_repository.dart';
import 'package:adena_baby/data/sync_merge.dart';

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

/// K-1 (TASARIM §6b): `pushError` kolonu — sayaç (6 tablo, hesap kapsamı),
/// liste, "geri al" (sunucu kopyası uygulanır / sunucuda yoksa notOnServer),
/// discard, 403+caregiver → 'role'.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late PushErrorRepository repo;
  late MemoryRepository memories;
  late HealthRepository health;

  const catalog = HealthCatalog([], [MilestoneCatalogItem('roll', 4, 'motor', 'R', 'd', 't')], []);

  setUp(() async {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    LocalSession.setActiveAccount('u1');
    final babies = BabyRepository(db, api);
    memories = MemoryRepository(db, api, 'u1', (_) => true);
    final mom = MomRepository(db, api, 'u1', (_) => true);
    final cycle = CycleRepository(db, api, () => true);
    health = HealthRepository(db, api, () async => catalog, (_) => true);
    repo = PushErrorRepository(db, babies, memories, mom, cycle, health);
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b1', name: 'Bebek', accountId: const Value('u1'), dirty: const Value(false)));
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'b2', name: 'Diğer', accountId: const Value('u2'), dirty: const Value(false)));
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Future<void> seedErrors() async {
    await (db.update(db.babies)..where((b) => b.id.equals('b1')))
        .write(const BabiesCompanion(pushError: Value('HTTP 422'), dirty: Value(true)));
    await (db.update(db.babies)..where((b) => b.id.equals('b2')))
        .write(const BabiesCompanion(pushError: Value('HTTP 422')));
    await db.into(db.memories).insert(MemoriesCompanion.insert(
        id: 'm1', baby: 'b1', date: DateTime(2026, 5, 1), title: const Value('İlk'),
        pushError: const Value('HTTP 400')));
    await db.into(db.memories).insert(MemoriesCompanion.insert(
        id: 'm2', baby: 'b2', date: DateTime(2026, 5, 1), pushError: const Value('x')));
    await db.into(db.momEntries).insert(MomEntriesCompanion.insert(
        id: 'mo1', baby: 'b1', kind: 'note', date: DateTime(2026, 5, 2),
        pushError: const Value('date gerekli')));
    await db.into(db.cycleEntries).insert(CycleEntriesCompanion.insert(
        id: 'c1', accountId: const Value('u1'), date: DateTime(2026, 5, 3),
        pushError: const Value('HTTP 422')));
    await db.into(db.cycleEntries).insert(CycleEntriesCompanion.insert(
        id: 'c2', accountId: const Value('u2'), date: DateTime(2026, 5, 3),
        pushError: const Value('HTTP 422')));
    await db.into(db.cycleSettingsTable).insert(CycleSettingsTableCompanion.insert(
        id: const Value('u1'), pushError: const Value('HTTP 400')));
    await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
        baby: 'b1', kind: 'milestone', itemKey: 'roll', done: const Value(true),
        dirty: const Value(true), pushError: const Value('role')));
  }

  test('watchCount: 6 tablo, yalnız aktif hesabın satırları; değişince güncellenir',
      () async {
    await seedErrors();
    final counts = <int>[];
    final sub = repo.watchCount('u1').listen(counts.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(counts.last, 6, reason: 'b1, m1, mo1, c1, settings u1, health');
    expect(await repo.watchCount('u2').first, 3);
    await (db.update(db.memories)..where((m) => m.id.equals('m1')))
        .write(const MemoriesCompanion(pushError: Value(null)));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(counts.last, 5);
    await sub.cancel();
  });

  test('list: türler, başlıklar, hesap kapsamı', () async {
    await seedErrors();
    final items = await repo.list('u1');
    expect(items.map((i) => i.kind).toSet(), PushErrorKind.values.toSet());
    expect(items.any((i) => i.id == 'm2'), isFalse, reason: 'u2 bebeği dışarıda');
    expect(items.firstWhere((i) => i.kind == PushErrorKind.memory).title, 'İlk');
    expect(items.firstWhere((i) => i.kind == PushErrorKind.health).id, 'milestone/roll');
    expect(items.firstWhere((i) => i.kind == PushErrorKind.health).error, 'role');
  });

  group('revert', () {
    test('anı sunucuda var → uygulanır (dirty=false, pushError=null, tombstone kalkar)',
        () async {
      await db.into(db.memories).insert(MemoriesCompanion.insert(
          id: 'm1', baby: 'b1', date: DateTime(2026, 5, 1), title: const Value('yerel'),
          isDeleted: const Value(true), pushError: const Value('HTTP 400')));
      adapter.onGet('/babies/b1/memories', (s) => s.reply(200, [
            {'id': 'm1', 'date': '2026-05-01', 'title': 'sunucu', 'note': '', 'first_tag': '', 'updated_at': '2026-05-01T10:00:00Z'}
          ]));
      final it = (await repo.list('u1')).single;
      expect(await repo.revert(it), RevertResult.applied);
      final r = await (db.select(db.memories)).getSingle();
      expect(r.title, 'sunucu');
      expect(r.dirty, isFalse);
      expect(r.isDeleted, isFalse);
      expect(r.pushError, isNull);
      expect(await repo.watchCount('u1').first, 0);
    });

    test('anı sunucuda yok → notOnServer; discard yerelden siler', () async {
      await db.into(db.memories).insert(MemoriesCompanion.insert(
          id: 'm1', baby: 'b1', date: DateTime(2026, 5, 1), pushError: const Value('HTTP 400')));
      adapter.onGet('/babies/b1/memories', (s) => s.reply(200, []));
      final it = (await repo.list('u1')).single;
      expect(await repo.revert(it), RevertResult.notOnServer);
      expect(await (db.select(db.memories)).get(), hasLength(1), reason: 'onaysız silinmez');
      await repo.discard(it);
      expect(await (db.select(db.memories)).get(), isEmpty);
    });

    test('ağ hatası → failed, dokunulmaz', () async {
      await db.into(db.memories).insert(MemoriesCompanion.insert(
          id: 'm1', baby: 'b1', date: DateTime(2026, 5, 1), pushError: const Value('HTTP 400')));
      adapter.onGet('/babies/b1/memories', (s) => s.reply(503, {}));
      final it = (await repo.list('u1')).single;
      expect(await repo.revert(it), RevertResult.failed);
      expect((await (db.select(db.memories)).getSingle()).pushError, 'HTTP 400');
    });

    test('bebek: sunucu profili uygulanır, ayar JSON\'u dokunulmaz; 404 → notOnServer, discard yerelde temiz bırakır (silmez)',
        () async {
      await (db.update(db.babies)..where((b) => b.id.equals('b1'))).write(
          const BabiesCompanion(
              pushError: Value('HTTP 422'), dirty: Value(true), name: Value('yerel'),
              settings: Value('{"units":{"volume":"oz"}}')));
      adapter.onGet('/babies/b1', (s) => s.reply(200, {
            'id': 'b1', 'name': 'sunucu', 'gender': 'unknown', 'status': 'born',
            'my_role': 'owner', 'member_count': 1
          }));
      final it = (await repo.list('u1')).single;
      expect(await repo.revert(it), RevertResult.applied);
      var r = await (db.select(db.babies)..where((b) => b.id.equals('b1'))).getSingle();
      expect(r.name, 'sunucu');
      expect(r.dirty, isFalse);
      expect(r.pushError, isNull);
      expect(r.settings, '{"units":{"volume":"oz"}}');

      await (db.update(db.babies)..where((b) => b.id.equals('b1'))).write(
          const BabiesCompanion(pushError: Value('HTTP 422'), dirty: Value(true)));
      adapter.onGet('/babies/b1', (s) => s.reply(404, {'detail': 'yok'}));
      final it2 = (await repo.list('u1')).single;
      expect(await repo.revert(it2), RevertResult.notOnServer);
      await repo.discard(it2);
      r = await (db.select(db.babies)..where((b) => b.id.equals('b1'))).getSingle();
      expect(r.dirty, isFalse);
      expect(r.pushError, isNull);
    });

    test('âdet ayarı: GET /cycle/settings uygulanır', () async {
      await db.into(db.cycleSettingsTable).insert(CycleSettingsTableCompanion.insert(
          id: const Value('u1'), pushError: const Value('HTTP 400'), dirty: const Value(true)));
      adapter.onGet('/cycle/settings', (s) => s.reply(200, {'enabled': false, 'reminders': {}}));
      final it = (await repo.list('u1')).single;
      expect(await repo.revert(it), RevertResult.applied);
      final r = await (db.select(db.cycleSettingsTable)).getSingle();
      expect(r.dirty, isFalse);
      expect(r.pushError, isNull);
      expect(r.enabled, isFalse);
    });

    test('sağlık: sunucu kalemi varsa değeri alır; yoksa yerel değer korunur, bayraklar temiz',
        () async {
      await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
          baby: 'b1', kind: 'milestone', itemKey: 'roll', done: const Value(true),
          dirty: const Value(true), pushError: const Value('HTTP 422')));
      adapter.onGet('/babies/b1/milestones', (s) => s.reply(200, [
            {'key': 'roll', 'achieved': false, 'achieved_date': null}
          ]));
      final it = (await repo.list('u1')).single;
      expect(await repo.revert(it), RevertResult.applied);
      var r = await (db.select(db.healthStatuses)).getSingle();
      expect(r.done, isFalse);
      expect(r.dirty, isFalse);
      expect(r.pushError, isNull);

      await (db.update(db.healthStatuses)).write(const HealthStatusesCompanion(
          done: Value(true), dirty: Value(true), pushError: Value('role')));
      adapter.onGet('/babies/b1/milestones', (s) => s.reply(200, [
            {'key': 'other', 'achieved': false, 'achieved_date': null}
          ]));
      expect(await repo.revert((await repo.list('u1')).single), RevertResult.applied);
      r = await (db.select(db.healthStatuses)).getSingle();
      expect(r.done, isTrue, reason: 'sunucuda kalem yok → yerel korunur');
      expect(r.pushError, isNull);
    });
  });

  test('403 + caregiver → pushError \'role\' (sağlık ve anı)', () async {
    await (db.update(db.babies)..where((b) => b.id.equals('b1')))
        .write(const BabiesCompanion(myRole: Value('caregiver')));
    await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
        baby: 'b1', kind: 'milestone', itemKey: 'roll', done: const Value(true),
        dirty: const Value(true)));
    adapter.onPost('/babies/b1/health/sync', (s) => s.reply(403, {'detail': 'no'}),
        data: Matchers.any);
    await health.pushDirty('b1');
    expect((await (db.select(db.healthStatuses)).getSingle()).pushError, 'role');

    await db.into(db.memories).insert(MemoriesCompanion.insert(
        id: 'm1', baby: 'b1', date: DateTime(2026, 5, 1)));
    adapter.onPost('/babies/b1/memories', (s) => s.reply(403, {'detail': 'no'}),
        data: Matchers.any);
    await memories.pushDirty('b1');
    expect((await (db.select(db.memories)).getSingle()).pushError, 'role');
  });
}
