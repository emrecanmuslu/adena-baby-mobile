import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/who_lms.dart';
import 'package:adena_baby/data/who_lms_repository.dart';

/// WhoLmsRepository: API → cache yaz + global [whoLms] tablosuna uygula;
/// API yoksa cache → uygula; ikisi de yoksa gömülü tablo dokunulmadan kalır.
///
/// [applyWhoLms] global mutable durumu değiştirir; her testte snapshot alınıp
/// tearDown'da geri yüklenir → testler izole kalır. Cache disk dosyası da her
/// test için izole temp dizine yönlendirilir.

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

/// Gömülüde olmayan benzersiz bir anahtar; API'den geldiğini kanıtlar.
const _newKey = 'wt_TEST';
final _apiSeries = {
  'key': _newKey,
  'l': [1.0, 2.0, 3.0],
  'm': [10.0, 20.0, 30.0],
  's': [0.1, 0.2, 0.3],
};

/// Gömülüdeki mevcut bir anahtarı (wt_M) üzerine yazan veri.
final _overrideEmbedded = {
  'key': 'wt_M',
  'l': [9.9],
  'm': [99.9],
  's': [0.99],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late Directory tmp;
  late Map<String, WhoLms> savedGlobal;

  setUp(() async {
    savedGlobal = whoLms; // global anlık görüntü
    tmp = await Directory.systemTemp.createTemp('who_lms_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
  });

  tearDown(() async {
    whoLms = savedGlobal; // global geri yükle
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File cacheFile() => File('${tmp.path}/who_lms.json');

  group('load() — API başarılı', () {
    test('API verisi global tabloya uygulanır ve cache yazılır', () async {
      adapter.onGet('/content/who-lms', (s) => s.reply(200, [_apiSeries]));

      await WhoLmsRepository(api).load();

      // Yeni anahtar global tabloya eklendi.
      expect(whoLms.containsKey(_newKey), isTrue);
      expect(whoLms[_newKey]!.m, [10.0, 20.0, 30.0]);
      // Gömülü anahtarlar korunur (applyWhoLms gömülüden kopyalar).
      expect(whoLms.containsKey('wt_M'), isTrue);
      // Cache yazıldı.
      expect(await cacheFile().exists(), isTrue);
      expect(await cacheFile().readAsString(), contains(_newKey));
    });

    test('mevcut gömülü anahtarın üzerine API verisi yazılır', () async {
      adapter.onGet('/content/who-lms', (s) => s.reply(200, [_overrideEmbedded]));

      await WhoLmsRepository(api).load();

      expect(whoLms['wt_M']!.m, [99.9]);
    });
  });

  group('load() — ikinci açılış cache okur', () {
    test('API erişilemezse önceki cache global tabloya uygulanır', () async {
      // 1) API başarılı → cache yazıldı.
      adapter.onGet('/content/who-lms', (s) => s.reply(200, [_apiSeries]));
      await WhoLmsRepository(api).load();
      expect(await cacheFile().exists(), isTrue);

      // Global'i gömülüye sıfırla → cache yolunun gerçekten uyguladığını gör.
      whoLms = Map<String, WhoLms>.of(savedGlobal);
      expect(whoLms.containsKey(_newKey), isFalse);

      // 2) Yeni istemci + API hatası → cache'ten uygulamalı.
      final api2 = ApiClient(_FakeTokens());
      DioAdapter(dio: api2.dio)
          .onGet('/content/who-lms', (s) => s.reply(500, <String, dynamic>{}));
      await WhoLmsRepository(api2).load();

      expect(whoLms.containsKey(_newKey), isTrue);
      expect(whoLms[_newKey]!.s, [0.1, 0.2, 0.3]);
    });
  });

  group('load() — fallback davranışları', () {
    test('API boş liste + cache yok → gömülü tablo dokunulmaz, cache yazılmaz',
        () async {
      adapter.onGet('/content/who-lms', (s) => s.reply(200, const []));
      await WhoLmsRepository(api).load();

      expect(whoLms.containsKey(_newKey), isFalse);
      expect(whoLms.containsKey('wt_M'), isTrue); // gömülü duruyor
      expect(await cacheFile().exists(), isFalse);
    });

    test('API ağ hatası + cache yok → gömülü tablo korunur', () async {
      adapter.onGet(
          '/content/who-lms', (s) => s.reply(500, <String, dynamic>{}));
      await WhoLmsRepository(api).load();
      expect(whoLms.containsKey('wt_M'), isTrue);
      expect(whoLms.containsKey(_newKey), isFalse);
    });
  });

  group('load() — bozuk veri', () {
    test('eksik seri (s yok) atlanır; geçerli seri uygulanır', () async {
      adapter.onGet('/content/who-lms', (s) => s.reply(200, [
            {'key': 'wt_BAD', 'l': [1.0], 'm': [2.0]}, // s eksik
            _apiSeries,
          ]));
      await WhoLmsRepository(api).load();

      expect(whoLms.containsKey('wt_BAD'), isFalse);
      expect(whoLms.containsKey(_newKey), isTrue);
    });

    test('Map olmayan öğeler güvenle atlanır', () async {
      adapter.onGet('/content/who-lms', (s) => s.reply(200, [
            'saçma',
            42,
            _apiSeries,
          ]));
      await WhoLmsRepository(api).load();
      expect(whoLms.containsKey(_newKey), isTrue);
    });

    test('bozuk cache dosyası + API hatası → gömülü korunur (çökme yok)',
        () async {
      await cacheFile().writeAsString('}{ bozuk');
      adapter.onGet(
          '/content/who-lms', (s) => s.reply(500, <String, dynamic>{}));
      await WhoLmsRepository(api).load();
      expect(whoLms.containsKey('wt_M'), isTrue);
      expect(whoLms.containsKey(_newKey), isFalse);
    });
  });
}
