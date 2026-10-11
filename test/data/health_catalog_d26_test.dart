import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';

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

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// D26 — sağlık kataloğu: önce PARSE sonra cache (bozuk API yanıtı cache'i
/// zehirlemesin); bozuk cache (geçerli JSON, yanlış şekil) asset'e düşer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ApiClient api;
  late DioAdapter adapter;
  late File cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('adena_d26');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    cache = File('${dir.path}/health_catalog_tr.json');
  });
  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  const good = {
    'vaccines': [
      {'key': 'BCG', 'months': 2, 'name': 'BCG'}
    ],
    'milestones': <Object>[],
    'teeth': <Object>[],
  };
  // Liste var ama kalem Map değil → fromJson `e as Map` ile fırlatır.
  const bad = {
    'vaccines': [1, 2],
  };

  test('API bozuk şekil döndürürse cache EZİLMEZ, mevcut cache kullanılır', () async {
    await cache.writeAsString(jsonEncode(good));
    adapter.onGet('/content/health-catalog', (s) => s.reply(200, bad));

    final cat = await HealthCatalogRepository(api).load();

    expect(cat.vaccines.map((v) => v.key), ['BCG'], reason: 'cache korunur');
    expect(jsonDecode(await cache.readAsString()), good, reason: 'bozuk yanıt cache\'e yazılmaz');
  });

  test('bozuk cache + API hatası → gömülü asset, fırlatma yok', () async {
    await cache.writeAsString(jsonEncode(bad));
    adapter.onGet('/content/health-catalog', (s) => s.reply(500, {}));

    final cat = await HealthCatalogRepository(api).load();

    expect(cat.vaccines, isNotEmpty, reason: 'assets/health_catalog_tr.json');
    // J16: varsayım yerine asset'in kendisi okunur — katalog değişse de doğru nedenle geçer.
    final asset = HealthCatalog.fromJson(jsonDecode(
            await rootBundle.loadString('assets/health_catalog_tr.json'))
        as Map<String, dynamic>);
    expect(cat.vaccines.map((v) => v.key).toSet(),
        asset.vaccines.map((v) => v.key).toSet(),
        reason: 'bozuk cache\'ten değil asset\'ten gelmeli');
  });

  // K5 (INCELEME-3): üç push yolu aşı kimliğini katalog ADI üzerinden gönderir
  // (sunucu `vaccine_name` ile eşler); pull ise sunucu adını `key` ile eşler
  // (I10). Bu yalnız asset'te key == name olduğu için tutarlıdır — değişirse
  // bu test uyarır (pull/push eşlemesi ayrışır).
  test('asset kataloglarında aşı key == name (TR ve EN)', () async {
    for (final lang in ['tr', 'en']) {
      final asset = HealthCatalog.fromJson(jsonDecode(
              await rootBundle.loadString('assets/health_catalog_$lang.json'))
          as Map<String, dynamic>);
      expect(asset.vaccines, isNotEmpty);
      for (final v in asset.vaccines) {
        expect(v.key, v.name, reason: '$lang: ${v.key} != ${v.name}');
      }
    }
  });

  test('geçerli API yanıtı parse edilir ve cache\'e yazılır (regresyon)', () async {
    adapter.onGet('/content/health-catalog', (s) => s.reply(200, good));
    final cat = await HealthCatalogRepository(api).load();
    expect(cat.vaccines.single.key, 'BCG');
    expect(jsonDecode(await cache.readAsString()), good);
  });
}
