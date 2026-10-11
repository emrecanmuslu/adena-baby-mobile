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
  k2Tests();
  o20Tests();
  k2bTests();

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
    test('updateFamilySettings birleştirir ve settingsDirty açar (profil dirty DEĞİL — O4/R6)',
        () async {
      await repo.create(baby('b1', 'X'));
      // create → dirty=true; profil push edilmiş gibi temizle ki ayar değişimi
      // profil dirty'sini AÇMADIĞI görülsün.
      await (db.update(db.babies)..where((b) => b.id.equals('b1')))
          .write(const BabiesCompanion(dirty: Value(false)));
      await repo.updateFamilySettings('b1', {'units': 'metric'});
      final merged = await repo.updateFamilySettings('b1', {'theme': 'dark'});
      expect(merged, {'units': 'metric', 'theme': 'dark'});

      final row = await rawRow('b1');
      expect(jsonDecode(row!.settings), {'units': 'metric', 'theme': 'dark'});
      expect(row.settingsDirty, isTrue);
      expect(row.dirty, isFalse, reason: 'ayar profili dirty yapmaz (R6)');
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

    test('profil push\'u ayar PATCH\'i İÇERMEZ; ayar pushSettings ile ayrı gider (O4/R6)',
        () async {
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
      adapter.onPatch('/babies/b1/settings', (s) => s.reply(200, {'units': 'metric'}),
          data: Matchers.any);

      await repo.pushDirty();
      expect(patched, isFalse, reason: 'profil push\'u ayarı taşımaz');
      await repo.pushSettings();
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
      // K2-3b: silmeden önce erişim doğrulanır — 403 = gerçekten kalktı.
      adapter.onGet('/babies/local-gone',
          (s) => s.reply(403, {'detail': 'Yetkiniz yok'}));

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

/// K2 (BULGULAR.md / TASARIM-SENKRON.md R1-R3, R5): pull, push'u henüz
/// başarmamış dirty yerel satırı ve yüklenmemiş yerel fotoyu sunucu kopyasıyla
/// eziyordu; pushDirty kalıcı (4xx) reddi geçici hatadan ayırmıyordu.
void k2Tests() {
  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late BabyRepository repo;
  const acct = 'acct-k2';

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    repo = BabyRepository(db, api);
    LocalSession.setActiveAccount(acct);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Future<BabyRow?> rawRow(String id) =>
      (db.select(db.babies)..where((b) => b.id.equals(id))).getSingleOrNull();

  Map<String, dynamic> srv(String id, String name, {String? photo}) => {
        'id': id,
        'name': name,
        'status': 'born',
        'my_role': 'owner',
        'member_count': 1,
        'photo': ?photo,
      };

  group('K2 — pull dirty satırı ezmez (R1)', () {
    test('dirty yerel ad düzenlemesi pull sonrası korunur, dirty kalır', () async {
      await repo.create(const Baby(id: 'b1', name: 'Eski'));
      await (db.update(db.babies)..where((b) => b.id.equals('b1')))
          .write(const BabiesCompanion(dirty: Value(false))); // sunucuyla eşit
      await repo.update('b1', {'name': 'Yeni'}); // push henüz gitmedi → dirty

      adapter.onGet('/babies', (s) => s.reply(200, [srv('b1', 'Eski')]));
      await repo.pullFromServer();

      final row = await rawRow('b1');
      expect(row!.name, 'Yeni', reason: 'sunucu kopyası dirty satırı ezmemeli');
      expect(row.dirty, isTrue, reason: 'bir sonraki push göndermeli');
    });

    test('yüklenmemiş yerel foto yolu pull sonrası korunur', () async {
      await repo.create(const Baby(id: 'b2', name: 'Foto'));
      await (db.update(db.babies)..where((b) => b.id.equals('b2'))).write(
          const BabiesCompanion(
              photo: Value('/data/user/0/app/babies/b2-1.jpg'),
              dirty: Value(true)));

      adapter.onGet('/babies',
          (s) => s.reply(200, [srv('b2', 'Foto', photo: 'https://cdn/old.jpg')]));
      await repo.pullFromServer();

      final row = await rawRow('b2');
      expect(row!.photo, '/data/user/0/app/babies/b2-1.jpg');
      expect(row.dirty, isTrue);
    });

    test('bekleyen silme (tombstone, dirty) pull ile geri gelmez (R2)', () async {
      await repo.create(const Baby(id: 'b3', name: 'Silinecek'));
      await repo.delete('b3'); // isDeleted + dirty

      adapter.onGet('/babies', (s) => s.reply(200, [srv('b3', 'Silinecek')]));
      await repo.pullFromServer();

      final row = await rawRow('b3');
      expect(row!.isDeleted, isTrue);
      expect(row.dirty, isTrue);
    });

    test('temiz bebek sunucudan güncellenir', () async {
      await repo.create(const Baby(id: 'b4', name: 'Eski'));
      await (db.update(db.babies)..where((b) => b.id.equals('b4')))
          .write(const BabiesCompanion(dirty: Value(false)));

      adapter.onGet('/babies',
          (s) => s.reply(200, [srv('b4', 'Yeni', photo: 'https://cdn/n.jpg')]));
      await repo.pullFromServer();

      final row = await rawRow('b4');
      expect(row!.name, 'Yeni');
      expect(row.photo, 'https://cdn/n.jpg');
      expect(row.dirty, isFalse);
    });

    test('paylaşılan temiz bebek listeden düşünce hâlâ silinir', () async {
      await repo.create(const Baby(id: 'sh', name: 'Paylaşılan', myRole: 'parent'));
      await (db.update(db.babies)..where((b) => b.id.equals('sh')))
          .write(const BabiesCompanion(dirty: Value(false)));
      await repo.create(const Baby(id: 'mine', name: 'Benim'));
      await (db.update(db.babies)..where((b) => b.id.equals('mine')))
          .write(const BabiesCompanion(dirty: Value(false)));

      adapter.onGet('/babies', (s) => s.reply(200, [srv('mine', 'Benim')]));
      adapter.onGet('/babies/sh', (s) => s.reply(404, {'detail': 'Not found'}));
      final removed = await repo.pullFromServer();

      expect(removed.map((b) => b.id), ['sh']);
      expect(await rawRow('sh'), isNull);
      expect(await rawRow('mine'), isNotNull);
    });
  });

  group('K2 — pushDirty R3 sınıflandırması', () {
    test('kalıcı red (422): dirty KALIR, pushError kaydedilir', () async {
      await repo.create(const Baby(id: 'p1', name: 'Red'));
      adapter.onPost('/babies', (s) => s.reply(422, {'name': ['geçersiz']}),
          data: Matchers.any);

      await repo.pushDirty();

      expect((await rawRow('p1'))!.dirty, isTrue);
      expect((await rawRow('p1'))!.pushError, contains('422'));
    });

    test('geçici hata (503): dirty kalır, pushError YOK', () async {
      await repo.create(const Baby(id: 'p2', name: 'Geçici'));
      adapter.onPost('/babies', (s) => s.reply(503, {'detail': 'down'}),
          data: Matchers.any);

      await repo.pushDirty();

      expect((await rawRow('p2'))!.dirty, isTrue);
      expect((await rawRow('p2'))!.pushError, isNull);
    });

    test('başarılı push önceki pushError notunu temizler', () async {
      await repo.create(const Baby(id: 'p3', name: 'Düzeldi'));
      adapter.onPost('/babies', (s) => s.reply(422, {'name': ['x']}),
          data: Matchers.any);
      await repo.pushDirty();
      expect((await rawRow('p3'))!.pushError, isNotNull);

      adapter.onPost('/babies', (s) => s.reply(201, {'id': 'p3', 'name': 'Düzeldi'}),
          data: Matchers.any);
      await repo.pushDirty();

      expect((await rawRow('p3'))!.dirty, isFalse);
      expect((await rawRow('p3'))!.pushError, isNull);
    });
  });
}

/// O20: caregiver yazımı repo'da reddedilir (dirty üretmez); K2 sonrası
/// caregiver cihazında dirty kalmış satırlar pull'da sunucu kopyasıyla düzelir
/// (push rol filtresi onları hiç göndermediği için başka düzelme yolu yok).
void o20Tests() {
  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late BabyRepository repo;
  const acct = 'acct-o20';

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    repo = BabyRepository(db, api);
    LocalSession.setActiveAccount(acct);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Future<BabyRow?> rawRow(String id) =>
      (db.select(db.babies)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<void> seedClean(String id, String name, String role) async {
    await repo.create(Baby(id: id, name: name, myRole: role));
    await (db.update(db.babies)..where((b) => b.id.equals(id)))
        .write(const BabiesCompanion(dirty: Value(false)));
  }

  Map<String, dynamic> srv(String id, String name, String role) => {
        'id': id,
        'name': name,
        'status': 'born',
        'my_role': role,
        'member_count': 2,
      };

  group('O20 — caregiver yazımı reddedilir', () {
    test('update → StateError, satır değişmez, dirty açılmaz', () async {
      await seedClean('c1', 'Sunucu Adı', 'caregiver');
      await expectLater(
          repo.update('c1', {'name': 'Bakıcı Değiştirdi'}), throwsStateError);
      final row = await rawRow('c1');
      expect(row!.name, 'Sunucu Adı');
      expect(row.dirty, isFalse);
    });

    test('updateFamilySettings → StateError, settings değişmez', () async {
      await seedClean('c2', 'X', 'caregiver');
      await expectLater(
          repo.updateFamilySettings('c2', {'units': {'volume': 'oz'}}),
          throwsStateError);
      final row = await rawRow('c2');
      expect(row!.settings, '{}');
      expect(row.dirty, isFalse);
    });

    test('updatePhoto → StateError, photo/dirty değişmez', () async {
      await seedClean('c3', 'X', 'caregiver');
      await expectLater(
          repo.updatePhoto('c3', '/tmp/does-not-matter.jpg'), throwsStateError);
      final row = await rawRow('c3');
      expect(row!.photo, isNull);
      expect(row.dirty, isFalse);
    });

    test('parent update çalışır (regresyon)', () async {
      await seedClean('p1', 'Eski', 'parent');
      final b = await repo.update('p1', {'name': 'Yeni'});
      expect(b.name, 'Yeni');
      expect((await rawRow('p1'))!.dirty, isTrue);
    });
  });

  group('O20 — pull: dirty kalmış caregiver satırı sunucuyla düzelir', () {
    test('caregiver dirty satırı pull sonrası sunucu kopyası + dirty=false',
        () async {
      await seedClean('c4', 'Sunucu', 'caregiver');
      // K2 öncesinden kalmış yetim dirty düzenleme (doğrudan DB'ye).
      await (db.update(db.babies)..where((b) => b.id.equals('c4'))).write(
          const BabiesCompanion(name: Value('Yetim'), dirty: Value(true)));

      adapter.onGet('/babies', (s) => s.reply(200, [srv('c4', 'Sunucu', 'caregiver')]));
      await repo.pullFromServer();

      final row = await rawRow('c4');
      expect(row!.name, 'Sunucu');
      expect(row.dirty, isFalse);
    });

    test('parent dirty satırı pull sonrası korunur (K2 regresyonu)', () async {
      await seedClean('p2', 'Sunucu', 'parent');
      await repo.update('p2', {'name': 'Yerel'}); // dirty

      adapter.onGet('/babies', (s) => s.reply(200, [srv('p2', 'Sunucu', 'parent')]));
      await repo.pullFromServer();

      final row = await rawRow('p2');
      expect(row!.name, 'Yerel');
      expect(row.dirty, isTrue);
    });
  });
}

/// K2-3b: paylaşılan temiz bebek /babies listesinde yoksa silmeden önce
/// GET /babies/{id} ile erişim doğrulanır. 403/404 → erişim kalktı → sil;
/// 200 → geçici liste tutarsızlığı → dokunma; ağ/5xx → dokunma. Böylece 200 ile
/// gelen eksik/boş liste üyenin gönderilmemiş child verisini (purge) kaybettirmez.
void k2bTests() {
  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late BabyRepository repo;
  const acct = 'acct-k2b';

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    repo = BabyRepository(db, api);
    LocalSession.setActiveAccount(acct);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Future<BabyRow?> rawRow(String id) =>
      (db.select(db.babies)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<void> seedShared(String id) async {
    await repo.create(Baby(id: id, name: 'Paylaşılan $id', myRole: 'parent'));
    await (db.update(db.babies)..where((b) => b.id.equals(id)))
        .write(const BabiesCompanion(dirty: Value(false)));
    // Gönderilmemiş (dirty) child kaydı — purge ile kaybolmamalı.
    await db.into(db.records).insert(RecordsCompanion.insert(
        id: 'rec-$id', baby: id, type: 'feed', ts: DateTime(2026, 5, 1)));
  }

  Future<bool> recordExists(String id) async =>
      (await (db.select(db.records)..where((r) => r.id.equals('rec-$id')))
              .getSingleOrNull()) !=
      null;

  group('K2-3b — purge öncesi erişim doğrulaması', () {
    test('liste boş ama GET /babies/{id} 200 → bebek ve dirty child korunur',
        () async {
      await seedShared('s200');
      adapter.onGet('/babies', (s) => s.reply(200, []));
      adapter.onGet('/babies/s200',
          (s) => s.reply(200, {'id': 's200', 'name': 'Paylaşılan s200'}));

      final removed = await repo.pullFromServer();

      expect(removed, isEmpty);
      expect(await rawRow('s200'), isNotNull);
      expect(await recordExists('s200'), isTrue);
    });

    test('403 → silinir ve removed ile döner (child purge çağıranda)', () async {
      await seedShared('s403');
      adapter.onGet('/babies', (s) => s.reply(200, []));
      adapter.onGet('/babies/s403', (s) => s.reply(403, {'detail': 'x'}));

      final removed = await repo.pullFromServer();
      expect(removed.map((b) => b.id), ['s403']);
      expect(await rawRow('s403'), isNull);
    });

    test('404 → silinir', () async {
      await seedShared('s404');
      adapter.onGet('/babies', (s) => s.reply(200, []));
      adapter.onGet('/babies/s404', (s) => s.reply(404, {'detail': 'x'}));

      final removed = await repo.pullFromServer();
      expect(removed.map((b) => b.id), ['s404']);
    });

    test('ağ hatası → korunur', () async {
      await seedShared('snet');
      adapter.onGet('/babies', (s) => s.reply(200, []));
      adapter.onGet(
          '/babies/snet',
          (s) => s.throws(
              0,
              DioException(
                  requestOptions: RequestOptions(path: '/babies/snet'),
                  type: DioExceptionType.connectionError)));

      final removed = await repo.pullFromServer();
      expect(removed, isEmpty);
      expect(await rawRow('snet'), isNotNull);
      expect(await recordExists('snet'), isTrue);
    });

    test('503 → korunur', () async {
      await seedShared('s503');
      adapter.onGet('/babies', (s) => s.reply(200, []));
      adapter.onGet('/babies/s503', (s) => s.reply(503, {'detail': 'down'}));

      expect(await repo.pullFromServer(), isEmpty);
      expect(await rawRow('s503'), isNotNull);
    });

    test('birden fazla aday: biri 200, biri 403, biri ağ hatası → yalnız 403 silinir',
        () async {
      await seedShared('m1');
      await seedShared('m2');
      await seedShared('m3');
      adapter.onGet('/babies', (s) => s.reply(200, []));
      adapter.onGet('/babies/m1', (s) => s.reply(200, {'id': 'm1', 'name': 'm1'}));
      adapter.onGet('/babies/m2', (s) => s.reply(403, {'detail': 'x'}));
      adapter.onGet(
          '/babies/m3',
          (s) => s.throws(
              0,
              DioException(
                  requestOptions: RequestOptions(path: '/babies/m3'),
                  type: DioExceptionType.connectionError)));

      final removed = await repo.pullFromServer();
      expect(removed.map((b) => b.id), ['m2']);
      expect(await rawRow('m1'), isNotNull);
      expect(await rawRow('m3'), isNotNull);
    });
  });
}
