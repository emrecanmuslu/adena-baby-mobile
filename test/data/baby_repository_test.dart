import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/models/baby.dart';

/// Secure storage'a dokunmadan sabit access token döndüren sahte depo.
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
  late BabyRepository repo;

  const acct = 'acct-1';

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    repo = BabyRepository(db, api);
    // watchAll/getAll/create aktif hesaba göre izole çalışır.
    LocalSession.setActiveAccount(acct);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Baby baby(
    String id,
    String name, {
    BabyStatus status = BabyStatus.born,
    BabyGender gender = BabyGender.unknown,
    DateTime? birthDate,
    String? myRole,
    int memberCount = 1,
  }) =>
      Baby(
        id: id,
        name: name,
        status: status,
        gender: gender,
        birthDate: birthDate,
        myRole: myRole,
        memberCount: memberCount,
      );

  Future<BabyRow?> rawRow(String id) =>
      (db.select(db.babies)..where((b) => b.id.equals(id))).getSingleOrNull();

  group('create (offline-first)', () {
    test('drift\'e dirty=true + aktif hesap ile yazar, domain döndürür',
        () async {
      final created = await repo.create(baby('b1', 'Adena',
          gender: BabyGender.female, birthDate: DateTime(2026, 1, 1)));

      expect(created.id, 'b1');
      expect(created.name, 'Adena');
      expect(created.gender, BabyGender.female);

      final row = await rawRow('b1');
      expect(row!.dirty, isTrue);
      expect(row.accountId, acct);
      expect(row.gender, 'female');
      expect(row.myRole, 'owner'); // null myRole → owner varsayılır
      expect(row.clientUpdatedAt, isNotNull);
    });

    test('expecting bebek status alanını korur', () async {
      await repo.create(baby('b1', 'Bebek',
          status: BabyStatus.expecting,
          birthDate: null));
      final row = await rawRow('b1');
      expect(row!.status, 'expecting');
    });
  });

  group('getAll / watchAll (hesap izolasyonu)', () {
    test('yalnız aktif hesabın silinmemiş bebeklerini döndürür', () async {
      await repo.create(baby('b1', 'Bir'));
      // Başka hesabın bebeği — görünmemeli.
      LocalSession.setActiveAccount('acct-other');
      await repo.create(baby('b2', 'Diger'));
      LocalSession.setActiveAccount(acct);

      final all = await repo.getAll();
      expect(all.map((e) => e.id).toList(), ['b1']);
    });

    test('watchAll() isimle alfabetik sıralı yayar', () async {
      await repo.create(baby('b1', 'Zeynep'));
      await repo.create(baby('b2', 'Ahmet'));
      final list = await repo.watchAll().first;
      expect(list.map((e) => e.name).toList(), ['Ahmet', 'Zeynep']);
    });

    test('aktif hesap yokken boş döner', () async {
      LocalSession.setActiveAccount(null);
      expect(await repo.getAll(), isEmpty);
      expect(await repo.watchAll().first, isEmpty);
    });
  });

  group('update (alan-bazlı)', () {
    test('verilen alanları günceller, dokunulmayanı korur, dirty açar',
        () async {
      await repo.create(baby('b1', 'Eski'));
      await (db.update(db.babies)..where((b) => b.id.equals('b1')))
          .write(const BabiesCompanion(dirty: Value(false)));

      final updated =
          await repo.update('b1', {'name': 'Yeni', 'gender': 'male'});

      expect(updated.name, 'Yeni');
      expect(updated.gender, BabyGender.male);
      final row = await rawRow('b1');
      expect(row!.dirty, isTrue);
      expect(row.name, 'Yeni');
      expect(row.gender, 'male');
    });

    test('birth_date string → DateTime parse edilir', () async {
      await repo.create(baby('b1', 'X'));
      final updated = await repo.update('b1', {'birth_date': '2026-03-15'});
      expect(updated.birthDate, DateTime(2026, 3, 15));
    });
  });

  group('delete (tombstone)', () {
    test('isDeleted + dirty işaretler, satırı silmez', () async {
      await repo.create(baby('b1', 'X'));
      await repo.delete('b1');
      final row = await rawRow('b1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.dirty, isTrue);
    });
  });

  group('familySettings (yerel JSON)', () {
    test('updateFamilySettings birleştirir ve dirty açar', () async {
      await repo.create(baby('b1', 'X'));
      await repo.updateFamilySettings('b1', {'units': 'metric'});
      final merged = await repo.updateFamilySettings('b1', {'theme': 'dark'});
      expect(merged, {'units': 'metric', 'theme': 'dark'});

      final row = await rawRow('b1');
      expect(jsonDecode(row!.settings), {'units': 'metric', 'theme': 'dark'});
      expect(row.dirty, isTrue);
    });
  });

  group('pushDirty (premium push)', () {
    test('dirty bebeği POST /babies ile gönderir, sonra temizler', () async {
      await repo.create(baby('b1', 'Adena',
          gender: BabyGender.female, birthDate: DateTime(2026, 1, 1)));

      Map<String, dynamic>? postBody;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'POST' && o.path == '/babies') {
          postBody = o.data as Map<String, dynamic>;
        }
        h.next(o);
      }));
      adapter.onPost('/babies', (s) => s.reply(200, {'ok': true}),
          data: Matchers.any);

      await repo.pushDirty();

      expect(postBody, isNotNull);
      expect(postBody!['id'], 'b1');
      expect(postBody!['name'], 'Adena');
      expect(postBody!['gender'], 'female');
      expect(postBody!['birth_date'], '2026-01-01');

      final row = await rawRow('b1');
      expect(row!.dirty, isFalse); // başarılı push → temiz
    });

    test('settings varsa PATCH /babies/{id}/settings gönderir', () async {
      await repo.create(baby('b1', 'X'));
      await repo.updateFamilySettings('b1', {'units': 'metric'});

      var patched = false;
      Map<String, dynamic>? patchBody;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'PATCH' && o.path == '/babies/b1/settings') {
          patched = true;
          patchBody = o.data as Map<String, dynamic>;
        }
        h.next(o);
      }));
      adapter.onPost('/babies', (s) => s.reply(200, {}), data: Matchers.any);
      adapter.onPatch('/babies/b1/settings', (s) => s.reply(200, {}),
          data: Matchers.any);

      await repo.pushDirty();
      expect(patched, isTrue);
      expect(patchBody, {'units': 'metric'});
    });

    test('silinen (tombstone) dirty bebek için DELETE /babies/{id} çağrılır',
        () async {
      await repo.create(baby('b1', 'X'));
      await repo.delete('b1');

      var deleted = false;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'DELETE' && o.path == '/babies/b1') deleted = true;
        h.next(o);
      }));
      adapter.onDelete('/babies/b1', (s) => s.reply(204, null),
          data: Matchers.any);

      await repo.pushDirty();
      expect(deleted, isTrue);
      final row = await rawRow('b1');
      expect(row!.dirty, isFalse);
    });

    test('paylaşımlı (myRole=parent) bebeği POST\'lamaz', () async {
      await repo.create(baby('b1', 'Shared', myRole: 'parent'));

      var posted = false;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'POST' && o.path == '/babies') posted = true;
        h.next(o);
      }));
      adapter.onPost('/babies', (s) => s.reply(200, {}), data: Matchers.any);

      await repo.pushDirty();
      expect(posted, isFalse); // sahip değil → yüklenmez
      // dirty olduğu gibi kalır (filtre dışı).
      final row = await rawRow('b1');
      expect(row!.dirty, isTrue);
    });

    test('hata atan POST yerel dirty\'yi korur (çevrimdışı dayanıklılığı)',
        () async {
      await repo.create(baby('b1', 'X'));
      adapter.onPost('/babies', (s) => s.reply(500, {'error': 'boom'}),
          data: Matchers.any);
      await repo.pushDirty(); // try/catch yutar
      final row = await rawRow('b1');
      expect(row!.dirty, isTrue); // korunur
    });
  });

  group('pullFromServer (premium pull)', () {
    test('GET /babies sonuçlarını yerele temiz yansıtır', () async {
      adapter.onGet(
        '/babies',
        (s) => s.reply(200, [
          {
            'id': 'srv1',
            'name': 'Sunucu',
            'gender': 'male',
            'status': 'born',
            'birth_date': '2026-01-01',
            'my_role': 'owner',
            'member_count': 2,
          }
        ]),
      );

      final removed = await repo.pullFromServer();
      expect(removed, isEmpty);

      final row = await rawRow('srv1');
      expect(row!.dirty, isFalse);
      expect(row.accountId, acct);
      expect(row.name, 'Sunucu');
      expect(row.memberCount, 2);
    });

    test('sunucuda olmayan + yerel temiz PAYLAŞILAN bebeği siler ve döndürür (erişim kalktı)',
        () async {
      // Paylaşılan (sahibi başkası) temiz bir bebek — sunucudan düşünce erişim kalkar.
      await repo.create(baby('local-gone', 'Gidecek', myRole: 'parent'));
      await (db.update(db.babies)..where((b) => b.id.equals('local-gone')))
          .write(const BabiesCompanion(dirty: Value(false)));

      adapter.onGet('/babies', (s) => s.reply(200, []));

      final removed = await repo.pullFromServer();
      expect(removed.map((e) => e.id).toList(), ['local-gone']);
      expect(await rawRow('local-gone'), isNull);
    });

    test('sunucuda olmayan KENDİ (sahip) bebeğini SİLMEZ (local-first; free/lapsed korunur)',
        () async {
      // Pull artık free/lapsed oturumda da koşuyor — kendi bebeğim asla reconcile ile
      // silinmemeli (yerel veri korunur). Yalnız paylaşılan bebek erişimi kalkabilir.
      await repo.create(baby('mine', 'Benim', myRole: 'owner'));
      await (db.update(db.babies)..where((b) => b.id.equals('mine')))
          .write(const BabiesCompanion(dirty: Value(false)));

      adapter.onGet('/babies', (s) => s.reply(200, []));

      final removed = await repo.pullFromServer();
      expect(removed, isEmpty);
      expect(await rawRow('mine'), isNotNull);
    });

    test('sunucuda olmayan ama dirty (push bekleyen) bebeği silmez', () async {
      await repo.create(baby('pending', 'Bekleyen')); // dirty=true kalır
      adapter.onGet('/babies', (s) => s.reply(200, []));
      final removed = await repo.pullFromServer();
      expect(removed, isEmpty);
      expect(await rawRow('pending'), isNotNull);
    });
  });

  group('markAllDirty (free→premium tam yükleme)', () {
    test('yalnız sahip olunan (owner/null) bebekleri dirty işaretler', () async {
      await repo.create(baby('owned', 'Benim', myRole: 'owner'));
      await repo.create(baby('shared', 'Paylasilan', myRole: 'caregiver'));
      // İkisini de temizle.
      await db.update(db.babies).write(const BabiesCompanion(dirty: Value(false)));

      await repo.markAllDirty();

      expect((await rawRow('owned'))!.dirty, isTrue);
      expect((await rawRow('shared'))!.dirty, isFalse); // sahip değil
    });
  });

  group('üyelik & davet (cloud endpoint\'leri)', () {
    test('members() GET /babies/{id}/members parse eder', () async {
      adapter.onGet(
        '/babies/b1/members',
        (s) => s.reply(200, [
          {
            'user': {'id': 'u1', 'email': 'a@b.com', 'name': 'Anne'},
            'role': 'owner',
            'joined_at': '2026-01-01T00:00:00.000Z',
          }
        ]),
      );
      final members = await repo.members('b1');
      expect(members.length, 1);
      expect(members.first.role, 'owner');
      expect(members.first.user.id, 'u1');
    });

    test('createInvitation() doğru payload ile POST eder', () async {
      Map<String, dynamic>? body;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path == '/babies/b1/invitations') {
          body = o.data as Map<String, dynamic>;
        }
        h.next(o);
      }));
      adapter.onPost('/babies/b1/invitations',
          (s) => s.reply(200, {'code': 'ABC123'}),
          data: Matchers.any);

      final res = await repo.createInvitation('b1',
          role: 'parent', email: 'x@y.com');
      expect(res['code'], 'ABC123');
      expect(body, {'role': 'parent', 'email': 'x@y.com'});
    });

    test('createInvitation() email boşsa email alanını eklemez', () async {
      Map<String, dynamic>? body;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path == '/babies/b1/invitations') {
          body = o.data as Map<String, dynamic>;
        }
        h.next(o);
      }));
      adapter.onPost('/babies/b1/invitations', (s) => s.reply(200, {}),
          data: Matchers.any);
      await repo.createInvitation('b1', role: 'caregiver');
      expect(body, {'role': 'caregiver'});
    });

    test('acceptInvitation() kodu POST eder, bebeği yerele temiz yazar',
        () async {
      adapter.onPost(
        '/invitations/accept',
        (s) => s.reply(200, {
          'baby': {
            'id': 'shared-1',
            'name': 'Paylasilan',
            'gender': 'female',
            'status': 'born',
            'my_role': 'parent',
            'member_count': 2,
          }
        }),
        data: Matchers.any,
      );

      final b = await repo.acceptInvitation('CODE');
      expect(b.id, 'shared-1');
      expect(b.myRole, 'parent');

      final row = await rawRow('shared-1');
      expect(row, isNotNull);
      expect(row!.dirty, isFalse); // accept sonrası temiz (sahip değil)
      expect(row.myRole, 'parent');
    });

    test('updateMemberRole() PATCH /babies/{id}/members/{uid} + role payload',
        () async {
      Map<String, dynamic>? body;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path == '/babies/b1/members/u1') {
          body = o.data as Map<String, dynamic>;
        }
        h.next(o);
      }));
      adapter.onPatch('/babies/b1/members/u1', (s) => s.reply(200, {}),
          data: Matchers.any);
      await repo.updateMemberRole('b1', 'u1', 'caregiver');
      expect(body, {'role': 'caregiver'});
    });

    test('removeMember() DELETE /babies/{id}/members/{uid}', () async {
      var hit = false;
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.method == 'DELETE' && o.path == '/babies/b1/members/u1') {
          hit = true;
        }
        h.next(o);
      }));
      adapter.onDelete('/babies/b1/members/u1', (s) => s.reply(204, null),
          data: Matchers.any);
      await repo.removeMember('b1', 'u1');
      expect(hit, isTrue);
    });
  });
}
