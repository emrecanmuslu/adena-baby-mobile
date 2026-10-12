import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/medication/med_names.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/models/medication_plan.dart';

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

/// İlaç v2 (A1) — plan modeli yeni alanları + sözleşme v2: tüm alanlar gidip
/// gelir; değişiklik yoksa GET (M11: sahip premium'u bitse de okunur);
/// `renamed` yerel adı günceller; `rejected` dirty + pushError bırakır;
/// duraklatma aralığı (pauses) ve zamanlama çapası (scheduleFrom) tutulur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const babyId = 'b1';
  const path = '/babies/$babyId/medication-plans/sync';

  late ApiClient api;
  late AppDatabase db;
  late HealthRepository repo;
  late List<({String method, Map<String, dynamic>? body})> sent;
  late Future<Map<String, dynamic>> Function(String method, Map<String, dynamic>? body)
      respond;

  Future<List<MedicationPlanRow>> rows() => db.select(db.medicationPlans).get();

  Map<String, dynamic> serverPlan(String id, {Map<String, dynamic> extra = const {}}) => {
        'id': id,
        'name': 'Antibiyotik',
        'dose': '5 ml',
        'times': ['08:00'],
        'active': true,
        'kind': 'scheduled',
        'freq': 'interval',
        'interval_hours': 8,
        'every_n_days': null,
        'weekdays': <int>[],
        'start_date': '2026-10-10',
        'end_date': '2026-10-16',
        'prn_min_interval_min': null,
        'prn_max_per_day': null,
        'pauses': [
          ['2026-10-11T06:00:00Z', '2026-10-11T18:00:00Z']
        ],
        'schedule_from': '2026-10-10T05:00:00Z',
        'is_deleted': false,
        'client_updated_at': '2026-10-10T05:00:00Z',
        'created_by': 'u-other',
        'created_at': '2026-10-10T05:00:00Z',
        ...extra,
      };

  setUp(() async {
    api = ApiClient(_FakeTokens());
    db = AppDatabase(NativeDatabase.memory());
    sent = [];
    respond = (method, body) async => {
          'applied': [
            if (body != null)
              for (final c in body['changes'] as List) c['id']
          ],
          'rejected': <Map<String, dynamic>>[],
          'renamed': <String, dynamic>{},
          'plans': <Map<String, dynamic>>[],
        };
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      if (o.path != path) return h.next(o);
      final body = o.data == null ? null : (o.data as Map).cast<String, dynamic>();
      sent.add((method: o.method, body: body));
      h.resolve(Response(
          requestOptions: o, statusCode: 200, data: await respond(o.method, body)));
    }));
    repo = HealthRepository(db, api, () async => const HealthCatalog([], [], []), (_) => true);
    await db.into(db.babies).insert(BabiesCompanion.insert(id: babyId, name: 'T'));
  });

  tearDown(() => db.close());

  test('medNameKey: Türkçe/İngilizce i varyantları ve boşluk katlanır (backend ile aynı)', () {
    expect(medNameKey('  İlaç  '), medNameKey('ilaç'));
    expect(medNameKey('ILAÇ'), medNameKey('ılaç'));
    expect(medNameKey('D  vitamini'), medNameKey('d vitamini'));
    expect(medNameKey('IBUPROFEN'), medNameKey('ibuprofen'));
    expect(medNameKey('Demir'), isNot(medNameKey('Demir şurubu')));
  });

  test('v2 alanlarıyla oluşturulan plan tüm alanlarla gönderilir', () async {
    final p = await repo.createMedicationPlan(babyId,
        name: 'Demir',
        dose: '1 ml',
        times: ['08:00', '20:00'],
        freq: MedFreq.weekly,
        weekdays: [1, 3, 5],
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 30));
    expect(p.freq, MedFreq.weekly);
    expect(p.weekdays, [1, 3, 5]);
    expect(p.startDate, DateTime(2026, 10, 12));
    expect(p.endDate, DateTime(2026, 10, 30));
    expect(p.scheduleFrom, isNotNull);
    expect(p.kind, MedKind.scheduled);

    await repo.syncMedicationPlans(babyId);
    expect(sent.single.method, 'POST');
    final ch = (sent.single.body!['changes'] as List).single as Map;
    expect(ch['kind'], 'scheduled');
    expect(ch['freq'], 'weekly');
    expect(ch['weekdays'], [1, 3, 5]);
    expect(ch['start_date'], '2026-10-12');
    expect(ch['end_date'], '2026-10-30');
    expect(ch['interval_hours'], isNull);
    expect(ch['every_n_days'], isNull);
    expect(ch['prn_min_interval_min'], isNull);
    expect(ch['prn_max_per_day'], isNull);
    expect(ch['pauses'], isEmpty);
    expect(ch['schedule_from'], isA<String>());
  });

  test('PRN plan: saatsiz, en kısa aralık ve günlük üst sınır taşınır', () async {
    final p = await repo.createMedicationPlan(babyId,
        name: 'Ateş düşürücü',
        dose: '2.5 ml',
        times: const [],
        kind: MedKind.prn,
        prnMinIntervalMin: 360,
        prnMaxPerDay: 4);
    expect(p.isPrn, isTrue);
    expect(p.times, isEmpty);
    await repo.syncMedicationPlans(babyId);
    final ch = (sent.single.body!['changes'] as List).single as Map;
    expect(ch['kind'], 'prn');
    expect(ch['times'], isEmpty);
    expect(ch['prn_min_interval_min'], 360);
    expect(ch['prn_max_per_day'], 4);
  });

  test('değişiklik yoksa GET; sunucu planı v2 alanlarıyla yerele iner', () async {
    respond = (method, body) async => {
          'applied': <String>[],
          'rejected': <Map<String, dynamic>>[],
          'renamed': <String, dynamic>{},
          'plans': [serverPlan('s1')],
        };
    final r = await repo.syncMedicationPlans(babyId);
    expect(sent.single.method, 'GET');
    expect(r.changed, isTrue);
    final p = (await repo.medicationPlans(babyId)).single;
    expect(p.uuid, 's1');
    expect(p.freq, MedFreq.interval);
    expect(p.intervalHours, 8);
    expect(p.startDate, DateTime(2026, 10, 10));
    expect(p.endDate, DateTime(2026, 10, 16));
    expect(p.scheduleFrom, DateTime.utc(2026, 10, 10, 5));
    expect(p.pauses.single.from, DateTime.utc(2026, 10, 11, 6));
    expect(p.pauses.single.to, DateTime.utc(2026, 10, 11, 18));

    // Sunucuda yalnız aralık değişti → changed.
    respond = (method, body) async => {
          'applied': <String>[],
          'rejected': <Map<String, dynamic>>[],
          'renamed': <String, dynamic>{},
          'plans': [serverPlan('s1', extra: {'interval_hours': 6})],
        };
    final r2 = await repo.syncMedicationPlans(babyId);
    expect(r2.changed, isTrue);
    expect((await repo.medicationPlans(babyId)).single.intervalHours, 6);
  });

  test('renamed: sunucunun eklediği ad yerelde uygulanır ve sonuçta döner', () async {
    await repo.createMedicationPlan(babyId, name: 'Demir', dose: '', times: ['08:00']);
    final uuid = (await rows()).single.uuid!;
    respond = (method, body) async => {
          'applied': [uuid],
          'rejected': <Map<String, dynamic>>[],
          'renamed': {uuid: 'Demir (2)'},
          'plans': [
            serverPlan(uuid, extra: {
              'name': 'Demir (2)',
              'freq': 'daily',
              'interval_hours': null,
              'pauses': <List<String?>>[],
              'end_date': null,
            })
          ],
        };
    final r = await repo.syncMedicationPlans(babyId);
    expect(r.renamed, {uuid: 'Demir (2)'});
    final row = (await rows()).single;
    expect(row.name, 'Demir (2)');
    expect(row.dirty, isFalse);
  });

  test('rejected: plan dirty kalır, pushError yazılır, plan modelinde görünür', () async {
    await repo.createMedicationPlan(babyId, name: 'X', dose: '', times: ['08:00']);
    final uuid = (await rows()).single.uuid!;
    respond = (method, body) async => {
          'applied': <String>[],
          'rejected': [
            {'id': uuid, 'reason': 'invalid'}
          ],
          'renamed': <String, dynamic>{},
          'plans': <Map<String, dynamic>>[],
        };
    await repo.syncMedicationPlans(babyId);
    final row = (await rows()).single;
    expect(row.dirty, isTrue);
    expect(row.pushError, 'invalid');
    expect((await repo.medicationPlans(babyId)).single.syncError, 'invalid');
  });

  test('duraklat → açık aralık eklenir; devam → aralık kapanır; saat değişince çapa ilerler',
      () async {
    final p = await repo.createMedicationPlan(babyId, name: 'D', dose: '', times: ['08:00']);
    final from0 = p.scheduleFrom!;
    await repo.updateMedicationPlan(p.id, active: false);
    var cur = (await repo.medicationPlans(babyId)).single;
    expect(cur.active, isFalse);
    expect(cur.pauses.single.to, isNull);
    await repo.updateMedicationPlan(p.id, active: true);
    cur = (await repo.medicationPlans(babyId)).single;
    expect(cur.pauses.single.to, isNotNull);
    expect(cur.scheduleFrom, from0); // duraklatma zamanlamayı değiştirmez
    await repo.updateMedicationPlan(p.id, name: 'D vitamini');
    cur = (await repo.medicationPlans(babyId)).single;
    expect(cur.scheduleFrom, from0); // ad değişikliği zamanlama değildir
    await repo.updateMedicationPlan(p.id, times: ['09:00']);
    cur = (await repo.medicationPlans(babyId)).single;
    expect(cur.scheduleFrom!.isAfter(from0), isTrue);
  });

  test('bitiş tarihi temizlenebilir (null) ve gün sayısıyla ayarlanabilir', () async {
    final p = await repo.createMedicationPlan(babyId,
        name: 'K', dose: '', times: ['08:00'], startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 7));
    await repo.updateMedicationPlan(p.id, endDate: const Value(null));
    expect((await repo.medicationPlans(babyId)).single.endDate, isNull);
    expect(MedicationPlan.endDateForDays(DateTime(2026, 10, 1), 7), DateTime(2026, 10, 7));
  });

  test('completed türetilir: bitiş günü geçince tamamlandı', () async {
    final p = await repo.createMedicationPlan(babyId,
        name: 'K', dose: '', times: ['08:00'], startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 7));
    expect(p.isCompletedAt(DateTime(2026, 10, 7, 23, 59)), isFalse);
    expect(p.isCompletedAt(DateTime(2026, 10, 8, 0, 0)), isTrue);
  });
}
