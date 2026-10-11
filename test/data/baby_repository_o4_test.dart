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

/// O4 (TASARIM §5C): aile ayarı ayrı bayrak (`settingsDirty`), değişen-alan
/// PATCH (K-5, `settingsBase` diff), `GET /settings` pull R1 (dirty korunur,
/// değişmemiş anahtar sunucudan dolar), caregiver asla PATCH atmaz,
/// kalıcı 4xx → pushError.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late BabyRepository repo;
  final requests = <RequestOptions>[];

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests.add(o);
      h.next(o);
    }));
    requests.clear();
    db = AppDatabase(NativeDatabase.memory());
    repo = BabyRepository(db, api);
    LocalSession.setActiveAccount('u1');
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Future<void> seed(String id,
      {String? role,
      Map<String, dynamic> settings = const {},
      Map<String, dynamic>? base,
      bool settingsDirty = false}) =>
      db.into(db.babies).insert(BabiesCompanion.insert(
          id: id,
          name: id,
          accountId: const Value('u1'),
          myRole: Value(role),
          dirty: const Value(false),
          settings: Value(jsonEncode(settings)),
          settingsBase: Value(base == null ? null : jsonEncode(base)),
          settingsDirty: Value(settingsDirty)));

  Future<BabyRow> row(String id) =>
      (db.select(db.babies)..where((b) => b.id.equals(id))).getSingle();

  List<RequestOptions> patches() =>
      requests.where((r) => r.method == 'PATCH').toList();

  group('changedSettingsKeys (K-5)', () {
    test('base yok → yerel tüm anahtarlar; anahtar sırası farkı değişiklik değil',
        () {
      expect(BabyRepository.changedSettingsKeys({'a': 1, 'b': 2}, null),
          ['a', 'b']);
      expect(
          BabyRepository.changedSettingsKeys({
            'units': {'volume': 'ml', 'weight': 'kg'},
            'quiet_hours': {'enabled': true}
          }, {
            'units': {'weight': 'kg', 'volume': 'ml'},
            'quiet_hours': {'enabled': false},
            'defaults': {}
          }),
          ['quiet_hours']);
    });
  });

  group('pushSettings', () {
    test('yalnız DEĞİŞEN anahtar PATCH edilir; 2xx → yerel=base=yanıt, temiz',
        () async {
      await seed('b1',
          settings: {'units': {'volume': 'oz'}, 'quiet_hours': {'enabled': true}},
          base: {'units': {'volume': 'ml'}, 'quiet_hours': {'enabled': true}},
          settingsDirty: true);
      final serverResp = {
        'units': {'volume': 'oz'},
        'quiet_hours': {'enabled': true},
        'enabled_types': [],
      };
      adapter.onPatch('/babies/b1/settings', (s) => s.reply(200, serverResp),
          data: Matchers.any);

      await repo.pushSettings();

      expect(patches(), hasLength(1));
      expect(patches().single.data, {'units': {'volume': 'oz'}},
          reason: 'değişmeyen quiet_hours gönderilmez (K-5)');
      final r = await row('b1');
      expect(r.settingsDirty, isFalse);
      expect(jsonDecode(r.settings), serverResp);
      expect(jsonDecode(r.settingsBase!), serverResp);
      expect(r.pushError, isNull);
    });

    test('base yok (migration/ilk) → tam yerel sözlük PATCH', () async {
      await seed('b1', settings: {'units': {'volume': 'oz'}}, settingsDirty: true);
      adapter.onPatch('/babies/b1/settings',
          (s) => s.reply(200, {'units': {'volume': 'oz'}}),
          data: Matchers.any);
      await repo.pushSettings();
      expect(patches().single.data, {'units': {'volume': 'oz'}});
    });

    test('caregiver satırı asla PATCH atmaz; parent atar; owned includeOwned=false ise atmaz',
        () async {
      await seed('c', role: 'caregiver', settings: {'units': {'volume': 'oz'}}, settingsDirty: true);
      await seed('p', role: 'parent', settings: {'units': {'volume': 'oz'}}, settingsDirty: true);
      await seed('o', role: 'owner', settings: {'units': {'volume': 'oz'}}, settingsDirty: true);
      adapter.onPatch('/babies/p/settings', (s) => s.reply(200, {}), data: Matchers.any);
      adapter.onPatch('/babies/o/settings', (s) => s.reply(200, {}), data: Matchers.any);
      await repo.pushSettings(includeOwned: false);
      expect(patches().map((r) => r.path), ['/babies/p/settings']);
      requests.clear();
      await repo.pushSettings(includeOwned: true);
      expect(patches().map((r) => r.path), ['/babies/o/settings']);
      expect((await row('c')).settingsDirty, isTrue, reason: 'dokunulmaz');
    });

    test('R5: PATCH sırasında yerel yeniden değiştiyse dirty kalır, base güncellenir',
        () async {
      await seed('b1', settings: {'units': {'volume': 'oz'}}, settingsDirty: true);
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
        await repo.updateFamilySettings('b1', {'units': {'volume': 'ml'}});
        h.next(o);
      }));
      adapter.onPatch('/babies/b1/settings',
          (s) => s.reply(200, {'units': {'volume': 'oz'}}),
          data: Matchers.any);
      await repo.pushSettings();
      final r = await row('b1');
      expect(r.settingsDirty, isTrue);
      expect(jsonDecode(r.settings), {'units': {'volume': 'ml'}});
      expect(jsonDecode(r.settingsBase!), {'units': {'volume': 'oz'}});
    });

    test('kalıcı 4xx → pushError, dirty kalır; geçici → yalnız dirty kalır', () async {
      await seed('b1', settings: {'units': {'volume': 'oz'}}, settingsDirty: true);
      adapter.onPatch('/babies/b1/settings', (s) => s.reply(400, {'units': ['bad']}),
          data: Matchers.any);
      await repo.pushSettings();
      var r = await row('b1');
      expect(r.settingsDirty, isTrue);
      expect(r.pushError, 'HTTP 400');

      await seed('b2', settings: {'units': {'volume': 'oz'}}, settingsDirty: true);
      adapter.onPatch('/babies/b2/settings', (s) => s.reply(503, {}),
          data: Matchers.any);
      await repo.pushSettings();
      r = await row('b2');
      expect(r.settingsDirty, isTrue);
      expect(r.pushError, isNull);
    });

    test('değişen anahtar yoksa istek atılmaz, dirty temizlenir', () async {
      await seed('b1',
          settings: {'units': {'volume': 'oz'}},
          base: {'units': {'volume': 'oz'}, 'defaults': {}},
          settingsDirty: true);
      await repo.pushSettings();
      expect(requests, isEmpty);
      expect((await row('b1')).settingsDirty, isFalse);
    });
  });

  group('pullSettings (R1)', () {
    test('temiz satır: yerel = base = sunucu (yeni cihaz sahibin ayarını görür)',
        () async {
      await seed('b1', settings: {});
      final srv = {'units': {'volume': 'oz'}, 'quiet_hours': {'enabled': true}};
      adapter.onGet('/babies/b1/settings', (s) => s.reply(200, srv));
      expect(await repo.pullSettings('b1'), isTrue);
      final r = await row('b1');
      expect(jsonDecode(r.settings), srv);
      expect(jsonDecode(r.settingsBase!), srv);
    });

    test('dirty satır: değişmiş anahtar korunur, değişmemiş anahtar sunucudan dolar',
        () async {
      await seed('b1',
          settings: {'units': {'volume': 'oz'}, 'quiet_hours': {'enabled': false}},
          base: {'units': {'volume': 'ml'}, 'quiet_hours': {'enabled': false}},
          settingsDirty: true);
      final srv = {'units': {'volume': 'ml'}, 'quiet_hours': {'enabled': true}};
      adapter.onGet('/babies/b1/settings', (s) => s.reply(200, srv));
      await repo.pullSettings('b1');
      final r = await row('b1');
      expect(jsonDecode(r.settings),
          {'units': {'volume': 'oz'}, 'quiet_hours': {'enabled': true}});
      expect(r.settingsDirty, isTrue, reason: 'units hâlâ gönderilmeyi bekliyor');
      expect(jsonDecode(r.settingsBase!), srv);
    });

    test('200 dışı / Map dışı yanıt → dokunulmaz', () async {
      await seed('b1', settings: {'units': {'volume': 'oz'}});
      adapter.onGet('/babies/b1/settings', (s) => s.reply(500, {'e': 1}));
      expect(await repo.pullSettings('b1'), isFalse);
      adapter.onGet('/babies/b1/settings', (s) => s.reply(200, [1, 2]));
      expect(await repo.pullSettings('b1'), isFalse);
      expect(jsonDecode((await row('b1')).settings), {'units': {'volume': 'oz'}});
    });

    test('pull sonrası pushSettings: sunucudan gelen anahtarlar değişiklik sayılmaz',
        () async {
      await seed('b1', settings: {});
      final srv = {'units': {'volume': 'oz'}, 'enabled_types': ['feed']};
      adapter.onGet('/babies/b1/settings', (s) => s.reply(200, srv));
      await repo.pullSettings('b1');
      await repo.updateFamilySettings('b1', {'quiet_hours': {'enabled': true}});
      adapter.onPatch('/babies/b1/settings', (s) => s.reply(200, {}), data: Matchers.any);
      await repo.pushSettings();
      expect(patches().single.data, {'quiet_hours': {'enabled': true}});
    });
  });

  group('markAllDirty (free→premium)', () {
    test('dolu ayarı olan sahip bebeği settingsDirty yapar; boş ayarı yapmaz', () async {
      await seed('full', role: 'owner', settings: {'units': {'volume': 'oz'}});
      await seed('empty', role: 'owner', settings: {});
      await seed('shared', role: 'parent', settings: {'units': {'volume': 'oz'}});
      await repo.markAllDirty();
      expect((await row('full')).settingsDirty, isTrue);
      expect((await row('empty')).settingsDirty, isFalse);
      expect((await row('shared')).settingsDirty, isFalse);
    });
  });
}
