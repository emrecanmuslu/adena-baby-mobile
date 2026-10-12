import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
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

/// KB-8 (a) — bakıcı ilaç planı ekleyemez/düzenleyemez/silemez (repo
/// StateError); doz işareti (medication kaydı) bakıcıdan da senkronlanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late HealthRepository health;

  setUp(() async {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    health = HealthRepository(db, api, () async => HealthCatalog.empty, (_) => false);
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'cg', name: 'Bebek', myRole: const Value('caregiver'), dirty: const Value(false)));
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'pa', name: 'Bebek2', myRole: const Value('parent'), dirty: const Value(false)));
  });

  tearDown(() => db.close());

  test('caregiver: create/update/delete StateError; parent: serbest', () async {
    await expectLater(
        health.createMedicationPlan('cg', name: 'D vit', dose: '1', times: const ['09:00']),
        throwsA(isA<StateError>()));
    final plan = await health.createMedicationPlan('pa', name: 'D vit', dose: '1', times: const ['09:00']);
    expect(await health.medicationPlans('cg'), isEmpty);
    expect(await health.medicationPlans('pa'), hasLength(1));

    // Rol sonradan bakıcıya düştü → sunucudaki (temiz) plan düzenlenemez/silinemez.
    await (db.update(db.medicationPlans)..where((r) => r.localId.equals(plan.id)))
        .write(const MedicationPlansCompanion(dirty: Value(false))); // sunucuda var
    await (db.update(db.babies)..where((b) => b.id.equals('pa')))
        .write(const BabiesCompanion(myRole: Value('caregiver')));
    await expectLater(health.updateMedicationPlan(plan.id, active: false), throwsA(isA<StateError>()));
    await expectLater(health.deleteMedicationPlan(plan.id), throwsA(isA<StateError>()));
    expect((await health.medicationPlans('pa')).single.active, isTrue);
  });

  test('bakıcının doz işareti (medication kaydı) /sync ile gönderilir', () async {
    final records = RecordRepository(db, api);
    await db.into(db.records).insert(RecordsCompanion.insert(
        id: 'dose1', baby: 'cg', type: 'medication', ts: DateTime(2026, 6, 1, 9),
        data: const Value('{"name":"D vit","given":true}'), dirty: const Value(true),
        clientUpdatedAt: Value(DateTime(2026, 6, 1, 9))));
    Map<String, dynamic>? sent;
    api.dio.interceptors.add(InterceptorsWrapperProbe((o) => sent = Map<String, dynamic>.from(o.data as Map)));
    adapter.onPost('/sync', (s) => s.reply(200, {
          'applied': ['dose1'], 'conflicts': [], 'server_changes': [], 'next_cursor': 'c'
        }), data: Matchers.any);
    await records.sync('cg');
    expect(sent, isNotNull);
    expect((sent!['changes'] as List).single['id'], 'dose1');
    expect((await (db.select(db.records)).getSingle()).dirty, isFalse);
  });

  group('N2 / KB-10 — bakıcı cihazındaki yerel-only (KB-8 öncesi) planlar', () {
    test('dirty satır localOnly işaretlenir; sunucudan gelen (temiz) satır işaretlenmez',
        () async {
      // KB-8 öncesi bakıcı oluşturmuştu: dirty, uuid var, sunucuya gitmedi.
      await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
          baby: 'cg', name: 'Eski yerel', createdAt: Value(DateTime(2026, 5, 1)),
          uuid: const Value('u-local'), dirty: const Value(true)));
      await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
          baby: 'cg', name: 'Sunucudan', createdAt: Value(DateTime(2026, 5, 1)),
          uuid: const Value('u-srv'), dirty: const Value(false)));
      final plans = await health.medicationPlans('cg');
      expect(plans.firstWhere((p) => p.name == 'Eski yerel').localOnly, isTrue);
      expect(plans.firstWhere((p) => p.name == 'Sunucudan').localOnly, isFalse);
      // Sahip/parent bebekte dirty satır localOnly DEĞİL (gönderilmeyi bekliyor).
      await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
          baby: 'pa', name: 'Bekleyen', createdAt: Value(DateTime(2026, 5, 1)),
          uuid: const Value('u-pa'), dirty: const Value(true)));
      expect((await health.medicationPlans('pa')).single.localOnly, isFalse);
    });

    test('bakıcı yerel-only planı SİLEBİLİR (yerelden, senkronsuz); sunucu planını silemez/düzenleyemez',
        () async {
      await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
          baby: 'cg', name: 'Eski yerel', createdAt: Value(DateTime(2026, 5, 1)),
          uuid: const Value('u-local'), dirty: const Value(true)));
      await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
          baby: 'cg', name: 'Sunucudan', createdAt: Value(DateTime(2026, 5, 1)),
          uuid: const Value('u-srv'), dirty: const Value(false)));
      final plans = await health.medicationPlans('cg');
      final local = plans.firstWhere((p) => p.localOnly);
      final srv = plans.firstWhere((p) => !p.localOnly);

      await health.deleteMedicationPlan(local.id);
      expect((await db.select(db.medicationPlans).get()).map((r) => r.name), ['Sunucudan'],
          reason: 'yerel-only plan tombstone değil, doğrudan silinir');
      await expectLater(health.deleteMedicationPlan(srv.id), throwsA(isA<StateError>()));
      await expectLater(health.updateMedicationPlan(srv.id, name: 'x'), throwsA(isA<StateError>()));
    });

    test('senkron yerel-only planı SİLMEZ (sunucu listesinde yok, dirty, bakıcı)', () async {
      await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
          baby: 'cg', name: 'Eski yerel', createdAt: Value(DateTime(2026, 5, 1)),
          uuid: const Value('u-local'), dirty: const Value(true)));
      // İlaç v2 (M11): bakıcı değişiklik göndermez → GET.
      adapter.onGet('/babies/cg/medication-plans/sync', (s) => s.reply(200, {
            'applied': <String>[],
            'plans': <Map<String, dynamic>>[],
          }));
      await health.syncMedicationPlans('cg');
      final rows = await db.select(db.medicationPlans).get();
      expect(rows.map((r) => r.name), ['Eski yerel']);
      expect(rows.single.dirty, isTrue);
    });
  });
}

/// Küçük istek yakalayıcı (dio interceptor).
class InterceptorsWrapperProbe extends Interceptor {
  final void Function(RequestOptions) onReq;
  InterceptorsWrapperProbe(this.onReq);
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    onReq(options);
    handler.next(options);
  }
}
