import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/i18n_repository.dart';

/// I18nRepository.sync(locale):
///  - tr → ağ yok, boş harita
///  - cache sürümüyle GET /i18n/{locale}?v=cachedV
///  - unchanged:true → cache döner
///  - yeni bundle → cache güncellenir, string haritası döner
///  - ağ hatası → cache'e düşer
///  - bozuk gövde → güvenli varsayılanlar (version=0, strings={})
///
/// Cache disk dosyası (`i18n_{locale}.json`) her test için izole temp dizine
/// yönlendirilir. Global durum yok (I18n.instance'a yazmaz).

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => null;
  @override
  Future<String?> get refreshToken async => null;
  @override
  Future<bool> get hasSession async => false;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('i18n_repo_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File cacheFile(String locale) => File('${tmp.path}/i18n_$locale.json');

  Future<void> seedCache(String locale, int version, Map<String, String> s) =>
      cacheFile(locale).writeAsString(jsonEncode({'version': version, 'strings': s}));

  group('sync — tr kısa devre', () {
    test('tr için ağ çağrısı yapılmadan boş harita döner', () async {
      // Hiçbir route stub'lanmadı; bir GET yapılsaydı test patlardı.
      final result = await I18nRepository(api).sync('tr');
      expect(result, isEmpty);
    });
  });

  group('sync — ilk yükleme (cache yok)', () {
    test('v=0 ile çekilir, string haritası parse edilir ve cache yazılır',
        () async {
      adapter.onGet(
        '/i18n/en',
        (s) => s.reply(200, {
          'version': 7,
          'strings': {'Merhaba': 'Hello', 'Selam': 'Hi'},
        }),
        queryParameters: {'v': 0},
      );

      final result = await I18nRepository(api).sync('en');

      expect(result, {'Merhaba': 'Hello', 'Selam': 'Hi'});
      // Cache güncellendi (sürüm + stringler).
      final (cachedV, cached) = await I18nRepository(api).readCache('en');
      expect(cachedV, 7);
      expect(cached['Merhaba'], 'Hello');
    });
  });

  group('sync — sürüm geçidi (version gating)', () {
    test('cache sürümü ?v= olarak gönderilir; unchanged:true → cache döner',
        () async {
      await seedCache('en', 5, {'Merhaba': 'Hello (cached)'});

      // v=5 gönderilmeli; sunucu unchanged döndürür.
      adapter.onGet(
        '/i18n/en',
        (s) => s.reply(200, {'unchanged': true}),
        queryParameters: {'v': 5},
      );

      final result = await I18nRepository(api).sync('en');
      expect(result, {'Merhaba': 'Hello (cached)'});
    });

    test('sürüm yükselince yeni bundle gelir, cache güncellenir', () async {
      await seedCache('en', 5, {'Merhaba': 'Hello v5'});

      adapter.onGet(
        '/i18n/en',
        (s) => s.reply(200, {
          'version': 6,
          'strings': {'Merhaba': 'Hello v6', 'Yeni': 'New'},
        }),
        queryParameters: {'v': 5},
      );

      final result = await I18nRepository(api).sync('en');
      expect(result, {'Merhaba': 'Hello v6', 'Yeni': 'New'});

      // Cache yeni sürüme yükseldi.
      final (cachedV, cached) = await I18nRepository(api).readCache('en');
      expect(cachedV, 6);
      expect(cached['Yeni'], 'New');
    });
  });

  group('sync — ağ hatası', () {
    test('ağ hatasında cache döner (varsa)', () async {
      await seedCache('en', 3, {'Merhaba': 'Hello cached'});
      adapter.onGet(
        '/i18n/en',
        (s) => s.reply(500, <String, dynamic>{}),
        queryParameters: {'v': 3},
      );

      final result = await I18nRepository(api).sync('en');
      expect(result, {'Merhaba': 'Hello cached'});
    });

    test('cache yok + ağ hatası → boş harita', () async {
      adapter.onGet(
        '/i18n/de',
        (s) => s.reply(500, <String, dynamic>{}),
        queryParameters: {'v': 0},
      );
      final result = await I18nRepository(api).sync('de');
      expect(result, isEmpty);
    });
  });

  group('sync — bozuk/eksik gövde', () {
    test('strings alanı yok → boş harita, version varsayılan 0', () async {
      adapter.onGet(
        '/i18n/en',
        (s) => s.reply(200, {'version': 9}),
        queryParameters: {'v': 0},
      );
      final result = await I18nRepository(api).sync('en');
      expect(result, isEmpty);

      // version yine de yazılır (strings boş).
      final (cachedV, _) = await I18nRepository(api).readCache('en');
      expect(cachedV, 9);
    });

    test('version alanı yok → 0 olarak yazılır, stringler okunur', () async {
      adapter.onGet(
        '/i18n/en',
        (s) => s.reply(200, {
          'strings': {'A': 'B'},
        }),
        queryParameters: {'v': 0},
      );
      final result = await I18nRepository(api).sync('en');
      expect(result, {'A': 'B'});

      final (cachedV, _) = await I18nRepository(api).readCache('en');
      expect(cachedV, 0);
    });

    test('strings değerleri stringe zorlanır (toString)', () async {
      adapter.onGet(
        '/i18n/en',
        (s) => s.reply(200, {
          'version': 1,
          'strings': {'Sayı': 42, 'Bayrak': true},
        }),
        queryParameters: {'v': 0},
      );
      final result = await I18nRepository(api).sync('en');
      expect(result['Sayı'], '42');
      expect(result['Bayrak'], 'true');
    });
  });

  group('readCache', () {
    test('dosya yoksa (0, {}) döner', () async {
      final (v, s) = await I18nRepository(api).readCache('fr');
      expect(v, 0);
      expect(s, isEmpty);
    });

    test('bozuk JSON → (0, {}) (çökme yok)', () async {
      await cacheFile('fr').writeAsString('}{ bozuk');
      final (v, s) = await I18nRepository(api).readCache('fr');
      expect(v, 0);
      expect(s, isEmpty);
    });
  });

  group('locales — write-through cache', () {
    test('sunucu listesi parse edilir', () async {
      adapter.onGet('/i18n/locales', (s) => s.reply(200, {
            'locales': [
              {'code': 'tr', 'native_name': 'Türkçe', 'english_name': 'Turkish'},
              {'code': 'en', 'native_name': 'English', 'english_name': 'English',
                'is_default': true},
            ],
          }));
      final list = await I18nRepository(api).locales();
      expect(list.length, 2);
      expect(list.first.code, 'tr');
      expect(list.last.isDefault, isTrue);
    });

    test('ağ hatası + cache yok → çekirdek tr+en fallback', () async {
      adapter.onGet(
          '/i18n/locales', (s) => s.reply(500, <String, dynamic>{}));
      final list = await I18nRepository(api).locales();
      expect(list.map((e) => e.code), containsAll(['tr', 'en']));
    });

    test('ağ hatası + önceki write-through cache → cache döner', () async {
      // 1) Başarılı çağrı write-through cache'i doldurur.
      adapter.onGet('/i18n/locales', (s) => s.reply(200, {
            'locales': [
              {'code': 'de', 'native_name': 'Deutsch', 'english_name': 'German'},
            ],
          }));
      await I18nRepository(api).locales();

      // 2) Yeni istemci + ağ hatası → cache'ten 'de' gelmeli (fallback değil).
      final api2 = ApiClient(_FakeTokens());
      DioAdapter(dio: api2.dio)
          .onGet('/i18n/locales', (s) => s.reply(500, <String, dynamic>{}));
      final list = await I18nRepository(api2).locales();
      expect(list.map((e) => e.code), contains('de'));
    });
  });

  group('countries — write-through cache', () {
    test('sunucu listesi parse edilir', () async {
      adapter.onGet('/i18n/countries', (s) => s.reply(200, {
            'countries': [
              {
                'code': 'TR',
                'name': 'Türkiye',
                'dial_code': '+90',
                'currency': 'TRY',
                'uses_imperial': false,
                'locale': 'tr',
                'translated': true,
                'sales_enabled': true,
              },
            ],
          }));
      final list = await I18nRepository(api).countries();
      expect(list.length, 1);
      expect(list.first.code, 'TR');
      expect(list.first.currency, 'TRY');
    });

    test('ağ hatası + cache yok → boş liste', () async {
      adapter.onGet(
          '/i18n/countries', (s) => s.reply(500, <String, dynamic>{}));
      final list = await I18nRepository(api).countries();
      expect(list, isEmpty);
    });
  });
}
