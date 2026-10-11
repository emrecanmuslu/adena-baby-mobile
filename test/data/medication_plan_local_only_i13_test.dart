import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';

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

/// I13 (INCELEME.md) / KB-10 — "yalnız bu cihazda" etiketi: bakıcıda dirty VE
/// sunucunun bildiği bir plan DEĞİL. Sunucuda olan ama bakıcının (KB-8 öncesi)
/// düzenlediği plan etiket almaz ve silinemez (senkron zaten geri getirirdi).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late HealthRepository health;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'med_server_plan_ids_cg': ['srv1'],
    });
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    health = HealthRepository(db, api, () async => HealthCatalog.empty, (_) => true);
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'cg', name: 'Bebek', myRole: const Value('caregiver'), dirty: const Value(false)));
    // Sunucudan gelmiş, KB-8 öncesi bakıcının düzenlediği (dirty) plan.
    await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
        baby: 'cg',
        name: 'D vit',
        uuid: const Value('srv1'),
        dirty: const Value(true),
        clientUpdatedAt: Value(DateTime(2026, 1, 2))));
    // Yerelde oluşturulmuş, sunucuya hiç gitmemiş plan.
    await db.into(db.medicationPlans).insert(MedicationPlansCompanion.insert(
        baby: 'cg',
        name: 'Demir',
        uuid: const Value('loc1'),
        dirty: const Value(true),
        clientUpdatedAt: Value(DateTime(2026, 1, 3))));
  });
  tearDown(() => db.close());

  test('sunucunun bildiği dirty plan localOnly DEĞİL; hiç gitmemiş plan localOnly', () async {
    final plans = await health.medicationPlans('cg');
    final byName = {for (final p in plans) p.name: p};
    expect(byName['D vit']!.localOnly, isFalse);
    expect(byName['Demir']!.localOnly, isTrue);
  });

  test('bakıcı sunucu planını silemez (StateError); yerel-only planı silebilir', () async {
    final plans = await health.medicationPlans('cg');
    final srv = plans.firstWhere((p) => p.name == 'D vit');
    final loc = plans.firstWhere((p) => p.name == 'Demir');
    await expectLater(health.deleteMedicationPlan(srv.id), throwsA(isA<StateError>()));
    await health.deleteMedicationPlan(loc.id);
    final left = await (db.select(db.medicationPlans)).get();
    expect(left.map((r) => r.name), ['D vit']);
  });

  test('senkron sunucu plan kümesini prefs\'e yazar (sonraki açılış için kalıcı)', () async {
    adapter.onPost(
        '/babies/cg/medication-plans/sync',
        (s) => s.reply(200, {
              'applied': [],
              'plans': [
                {
                  'id': 'srv1',
                  'name': 'D vit',
                  'dose': '',
                  'times': ['09:00'],
                  'active': true,
                  'is_deleted': false,
                  'client_updated_at': '2026-01-01T00:00:00Z',
                  'created_at': '2026-01-01T00:00:00Z',
                },
                {
                  'id': 'srv2',
                  'name': 'C vit',
                  'dose': '',
                  'times': ['10:00'],
                  'active': true,
                  'is_deleted': false,
                  'client_updated_at': '2026-01-01T00:00:00Z',
                  'created_at': '2026-01-01T00:00:00Z',
                },
              ],
            }),
        data: Matchers.any);
    await health.syncMedicationPlans('cg');
    final known = (await SharedPreferences.getInstance()).getStringList('med_server_plan_ids_cg');
    expect(known!.toSet(), {'srv1', 'srv2'});
    // Senkron sonrası: sunucu planı temiz (bakıcı düzenlemesi ezildi), yerel-only hâlâ dirty.
    final plans = await health.medicationPlans('cg');
    expect(plans.where((p) => p.localOnly).map((p) => p.name), ['Demir']);
  });
}
