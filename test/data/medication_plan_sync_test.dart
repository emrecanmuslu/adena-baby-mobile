import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';

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

/// İlaç/vitamin planlarının aile senkronu (HealthRepository.syncMedicationPlans).
/// Sunucu, isteği yakalayıp [respond] ile yanıtlayan bir interceptor'la taklit edilir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const babyId = 'b1';
  const path = '/babies/$babyId/medication-plans/sync';

  late ApiClient api;
  late AppDatabase db;
  late HealthRepository repo;
  late bool cloud;
  late List<String> notified;
  late List<Map<String, dynamic>> sentBodies;
  // İstek gövdesinden yanıt üretir (varsayılan: hepsini uygula, sunucu boş).
  late Future<Map<String, dynamic>> Function(Map<String, dynamic> body) respond;

  Future<void> addBaby({String? role}) => db.into(db.babies).insert(
        BabiesCompanion.insert(id: babyId, name: 'Test', myRole: Value(role)),
      );

  Future<List<MedicationPlanRow>> rows() => db.select(db.medicationPlans).get();

  Map<String, dynamic> serverPlan(String id,
          {String name = 'D vitamini',
          String dose = '3 damla',
          List<String> times = const ['09:00'],
          bool active = true,
          bool deleted = false,
          String stamp = '2026-06-01T08:00:00Z'}) =>
      {
        'id': id,
        'name': name,
        'dose': dose,
        'times': times,
        'active': active,
        'is_deleted': deleted,
        'client_updated_at': stamp,
        'created_by': 'u-other',
        'created_at': '2026-06-01T08:00:00Z',
      };

  setUp(() {
    api = ApiClient(_FakeTokens());
    db = AppDatabase(NativeDatabase.memory());
    cloud = true;
    notified = [];
    sentBodies = [];
    respond = (body) async => {
          'applied': [for (final c in body['changes'] as List) c['id']],
          'plans': <Map<String, dynamic>>[],
        };
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      if (o.path != path) return h.next(o);
      final body = (o.data as Map).cast<String, dynamic>();
      sentBodies.add(body);
      try {
        h.resolve(
            Response(requestOptions: o, statusCode: 200, data: await respond(body)));
      } catch (e) {
        h.reject(DioException(requestOptions: o, error: e));
      }
    }));
    repo = HealthRepository(
      db,
      api,
      () async => const HealthCatalog([], [], []),
      (_) => cloud,
      onPlansChanged: notified.add,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('yeni plan gönderilir; sunucu yanıtıyla temizlenir', () async {
    await addBaby();
    await repo.createMedicationPlan(babyId,
        name: 'D vitamini', dose: '3 damla', times: ['09:00', '21:00']);
    expect(notified, [babyId]);
    final uuid = (await rows()).single.uuid!;

    respond = (body) async => {
          'applied': [uuid],
          'plans': [
            serverPlan(uuid, times: ['09:00', '21:00'])
          ],
        };
    final r = await repo.syncMedicationPlans(babyId);

    final change = (sentBodies.single['changes'] as List).single as Map;
    expect(change['id'], uuid);
    expect(change['op'], 'upsert');
    expect(change['name'], 'D vitamini');
    expect(change['times'], ['09:00', '21:00']);
    expect(change['active'], isTrue);
    expect(change['client_updated_at'], isNotNull);

    expect(r.changed, isFalse); // görünen liste aynı
    expect(r.removed, isEmpty);
    final row = (await rows()).single;
    expect(row.dirty, isFalse);

    // İkinci tur: gönderilecek bir şey yok.
    await repo.syncMedicationPlans(babyId);
    expect(sentBodies.last['changes'], isEmpty);
  });

  test('başka üyenin planı yerele eklenir ve listede görünür', () async {
    await addBaby(role: 'parent');
    respond = (_) async => {
          'applied': <String>[],
          'plans': [serverPlan('p-remote', name: 'Demir', active: false)],
        };

    final r = await repo.syncMedicationPlans(babyId);

    expect(r.changed, isTrue);
    final plan = (await repo.medicationPlans(babyId)).single;
    expect(plan.name, 'Demir');
    expect(plan.dose, '3 damla');
    expect(plan.times, ['09:00']);
    expect(plan.active, isFalse);
    expect((await rows()).single.dirty, isFalse);

    // Aynı yanıt tekrar gelirse değişiklik yok, çift satır yok.
    final again = await repo.syncMedicationPlans(babyId);
    expect(again.changed, isFalse);
    expect(await rows(), hasLength(1));
  });

  test('sunucuda silinen plan yerelden kalkar, yerel id döner', () async {
    await addBaby(role: 'parent');
    respond = (_) async => {
          'applied': <String>[],
          'plans': [serverPlan('p1')],
        };
    await repo.syncMedicationPlans(babyId);
    final localId = (await rows()).single.localId;

    respond = (_) async => {
          'applied': <String>[],
          'plans': [serverPlan('p1', deleted: true)],
        };
    final r = await repo.syncMedicationPlans(babyId);

    expect(r.changed, isTrue);
    expect(r.removed, [localId]);
    expect(await rows(), isEmpty);
  });

  test('yerel silme tombstone olur, gönderilir, onaylanınca satır silinir', () async {
    await addBaby();
    final p = await repo.createMedicationPlan(babyId,
        name: 'D vitamini', dose: '', times: ['09:00']);
    final uuid = (await rows()).single.uuid!;
    await repo.syncMedicationPlans(babyId); // yüklendi

    await repo.deleteMedicationPlan(p.id);
    expect(await repo.medicationPlans(babyId), isEmpty); // listede görünmez
    expect((await rows()).single.isDeleted, isTrue); // ama satır duruyor

    respond = (body) async => {
          'applied': [uuid],
          'plans': [serverPlan(uuid, deleted: true)],
        };
    await repo.syncMedicationPlans(babyId);

    expect((sentBodies.last['changes'] as List).single['op'], 'delete');
    expect(await rows(), isEmpty);
  });

  test('hiç yüklenmemiş planın silinmesi: applied gelince tombstone atılır', () async {
    await addBaby();
    final p = await repo.createMedicationPlan(babyId,
        name: 'D vitamini', dose: '', times: ['09:00']);
    await repo.deleteMedicationPlan(p.id);

    await repo.syncMedicationPlans(babyId); // varsayılan: applied, plans boş

    expect(await rows(), isEmpty);
  });

  test('bulut kapalı bebekte silme doğrudan siler (tombstone yok)', () async {
    await addBaby();
    cloud = false;
    final p = await repo.createMedicationPlan(babyId,
        name: 'D vitamini', dose: '', times: ['09:00']);
    await repo.deleteMedicationPlan(p.id);
    expect(await rows(), isEmpty);
  });

  test('sunucu kazanırsa (applied değil) yerel düzenleme sunucuyla ezilir', () async {
    await addBaby();
    final p = await repo.createMedicationPlan(babyId,
        name: 'D vitamini', dose: '', times: ['09:00']);
    final uuid = (await rows()).single.uuid!;
    await repo.updateMedicationPlan(p.id, name: 'Benim adım');

    respond = (_) async => {
          'applied': <String>[],
          'plans': [serverPlan(uuid, name: 'Eşimin adı')],
        };
    final r = await repo.syncMedicationPlans(babyId);

    expect(r.changed, isTrue);
    final row = (await rows()).single;
    expect(row.name, 'Eşimin adı');
    expect(row.dirty, isFalse);
  });

  test('uçuş sırasında yeniden düzenlenen plan ezilmez, dirty kalır', () async {
    await addBaby();
    final p = await repo.createMedicationPlan(babyId,
        name: 'D vitamini', dose: '', times: ['09:00']);
    final uuid = (await rows()).single.uuid!;

    respond = (_) async {
      // İstek havadayken kullanıcı planı yeniden düzenliyor.
      await repo.updateMedicationPlan(p.id, name: 'Sonradan');
      return {
        'applied': [uuid],
        'plans': [serverPlan(uuid)],
      };
    };
    await repo.syncMedicationPlans(babyId);

    final row = (await rows()).single;
    expect(row.name, 'Sonradan');
    expect(row.dirty, isTrue);

    // Sonraki tur yeni düzenlemeyi gönderir.
    respond = (body) async => {
          'applied': [uuid],
          'plans': [serverPlan(uuid, name: 'Sonradan')],
        };
    await repo.syncMedicationPlans(babyId);
    expect((sentBodies.last['changes'] as List).single['name'], 'Sonradan');
    expect((await rows()).single.dirty, isFalse);
  });

  test('aynı saniyedeki ardışık düzenlemede damga ileri gider', () async {
    await addBaby();
    final p = await repo.createMedicationPlan(babyId,
        name: 'D vitamini', dose: '', times: ['09:00']);
    final first = (await rows()).single.clientUpdatedAt!;
    await repo.updateMedicationPlan(p.id, active: false);
    final second = (await rows()).single.clientUpdatedAt!;
    expect(second.isAfter(first), isTrue);
  });

  test('bakıcı değişiklik göndermez; sunucu planı yerel düzenlemeyi ezer', () async {
    await addBaby(role: 'caregiver');
    respond = (_) async => {
          'applied': <String>[],
          'plans': [serverPlan('p1')],
        };
    await repo.syncMedicationPlans(babyId);
    final localId = (await rows()).single.localId;
    await repo.updateMedicationPlan(localId, name: 'Bakıcının değişikliği');

    await repo.syncMedicationPlans(babyId);

    expect(sentBodies.last['changes'], isEmpty);
    final row = (await rows()).single;
    expect(row.name, 'D vitamini');
    expect(row.dirty, isFalse);
  });

  test('v13\'ten kalan uuid\'siz plan kimlik alır ve yüklenir', () async {
    await addBaby();
    await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
          baby: babyId,
          name: 'Eski plan',
          createdAt: Value(DateTime(2026, 5, 1)),
        ));
    expect((await rows()).single.uuid, isNull);

    await repo.syncMedicationPlans(babyId);

    final change = (sentBodies.single['changes'] as List).single as Map;
    expect(change['id'], isNotNull);
    expect(change['name'], 'Eski plan');
    expect(change['client_updated_at'], isNotNull);
    expect((await rows()).single.uuid, change['id']);
  });

  test('ağ hatasında yerel plan korunur ve dirty kalır', () async {
    await addBaby();
    await repo.createMedicationPlan(babyId, name: 'D vitamini', dose: '', times: ['09:00']);
    respond = (_) async => throw StateError('offline');

    await expectLater(repo.syncMedicationPlans(babyId), throwsA(anything));

    final row = (await rows()).single;
    expect(row.dirty, isTrue);
    expect(await repo.medicationPlans(babyId), hasLength(1));
  });

  test('başka bebeğin planlarına dokunmaz', () async {
    await addBaby();
    await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b2', name: 'Diğer'));
    await repo.createMedicationPlan('b2', name: 'Onun planı', dose: '', times: ['08:00']);

    await repo.syncMedicationPlans(babyId);

    expect(sentBodies.single['changes'], isEmpty);
    expect(await repo.medicationPlans('b2'), hasLength(1));
    expect((await rows()).single.dirty, isTrue);
  });
}
