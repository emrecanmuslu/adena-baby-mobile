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

    // Rol sonradan bakıcıya düştü → mevcut plan düzenlenemez/silinemez.
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
