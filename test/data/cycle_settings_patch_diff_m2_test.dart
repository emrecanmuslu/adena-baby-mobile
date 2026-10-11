import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';

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

/// M2 — adet ayarı dirty PATCH'i yalnız yerelde DEĞİŞEN alanları gönderir
/// (`baseJson` = sunucunun son onayladığı JSON). O26 sonrası whole-row gönderim
/// B cihazındaki bayat `baby: null`'ı sunucuya taşıyıp A'nın kurduğu bebek bağını
/// çözebiliyordu. K-8 (bilinçli null) korunur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late CycleRepository repo;
  final patches = <Map<String, dynamic>>[];

  Map<String, dynamic> serverJson({String? baby, int cycleLen = 28}) => {
        'baby': baby,
        'birth_date': null,
        'breastfeeding': '',
        'first_period_date': '2026-05-01',
        'reminders': {},
        'show_fertility_warning': true,
        'enabled': true,
        'expected_cycle_length': cycleLen,
        'lifecycle_mode': 'tracking',
      };

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      if (o.method == 'PATCH') patches.add(Map<String, dynamic>.from(o.data as Map));
      h.next(o);
    }));
    patches.clear();
    db = AppDatabase(NativeDatabase.memory());
    LocalSession.setActiveAccount('u1');
    repo = CycleRepository(db, api, () => true);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  test('B cihazı: sunucuda bebek bağı var, yerelde bayat baby=null + başka alan dirty → PATCH baby içermez',
      () async {
    // 1) B daha önce sunucudan çekti: o zaman baby yoktu (base: baby null).
    adapter.onGet('/cycle/settings', (s) => s.reply(200, serverJson(baby: null)));
    adapter.onGet('/cycle/entries', (s) => s.reply(200, []));
    await repo.syncIfCloud();
    expect((await (db.select(db.cycleSettingsTable)).getSingle()).baseJson, isNotNull);

    // 2) A cihazı sunucuda bebek bağını kurdu (B bunu görmedi). B başka alan değiştirir.
    await repo.patchSettings({'expected_cycle_length': 31});
    adapter.onPatch('/cycle/settings', (s) => s.reply(200, serverJson(baby: 'baby-A', cycleLen: 31)),
        data: Matchers.any);
    await repo.syncIfCloud();

    expect(patches, hasLength(1));
    expect(patches.single.containsKey('baby'), isFalse,
        reason: 'bayat null bebek bağını çözmemeli');
    expect(patches.single['expected_cycle_length'], 31);
    expect(patches.single.keys, ['expected_cycle_length'], reason: 'yalnız değişen alan');
    final row = await (db.select(db.cycleSettingsTable)).getSingle();
    expect(row.dirty, isFalse);
    expect(row.baby, 'baby-A', reason: 'PATCH yanıtı otoriter → bağ yerelde de kuruldu');
  });

  test('K-8: bilinçli null (base\'de dolu, yerelde null) PATCH\'te baby: null gider', () async {
    adapter.onGet('/cycle/settings', (s) => s.reply(200, serverJson(baby: 'baby-A')));
    adapter.onGet('/cycle/entries', (s) => s.reply(200, []));
    await repo.syncIfCloud();
    await repo.patchSettings({'baby': null});
    adapter.onPatch('/cycle/settings', (s) => s.reply(200, serverJson(baby: null)),
        data: Matchers.any);
    await repo.syncIfCloud();
    expect(patches.single.containsKey('baby'), isTrue);
    expect(patches.single['baby'], isNull);
  });

  test('base yok (ilk kullanım) → tam sözlük (eski kontrat); değişiklik yoksa istek yok',
      () async {
    await repo.patchSettings({'expected_cycle_length': 31});
    adapter.onPatch('/cycle/settings', (s) => s.reply(200, serverJson(cycleLen: 31)),
        data: Matchers.any);
    adapter.onGet('/cycle/entries', (s) => s.reply(200, []));
    await repo.syncIfCloud();
    expect(patches.single.length, greaterThan(5), reason: 'base yokken tam sözlük');

    // Aynı değeri tekrar yaz → base ile aynı → PATCH atılmaz, temiz.
    patches.clear();
    await repo.patchSettings({'expected_cycle_length': 31});
    await repo.syncIfCloud();
    expect(patches, isEmpty);
    expect((await (db.select(db.cycleSettingsTable)).getSingle()).dirty, isFalse);
  });

  test('I9: importFromCloud base yazar → import sonrası (çevrimdışı) tek alan değişikliği '
      "PATCH'te yalnız o alan (baby yok)", () async {
    adapter
      ..onGet('/cycle/settings', (s) => s.reply(200, serverJson(baby: 'b1')))
      ..onGet('/cycle/entries', (s) => s.reply(200, []));
    await repo.importFromCloud();

    await repo.patchSettings({'expected_cycle_length': 30}); // satır içi ağ yok
    adapter.onPatch('/cycle/settings',
        (s) => s.reply(200, serverJson(baby: 'b1', cycleLen: 30)),
        data: Matchers.any);
    await repo.syncIfCloud();

    expect(patches, hasLength(1));
    expect(patches.single, {'expected_cycle_length': 30});
  });
}
