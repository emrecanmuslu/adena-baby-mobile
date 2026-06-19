import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/pregnancy_repository.dart';
import 'package:adena_baby/data/pregnancy_weeks.dart';

/// PregnancyRepository: önce API → cache yaz, sonraki açılışta cache,
/// ikisi de yoksa gömülü tablo (PregnancyWeeksData.embedded).
///
/// Repo `getApplicationSupportDirectory()` (path_provider) ile diske JSON
/// cache yazar; testte platform her test için izole bir temp dizine
/// yönlendirilir → cache durumu testler arası sızmaz.

/// Token okunmasın diye kanlı (canned) sahte; gerçek arayüzü taklit eder.
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

/// path_provider'ı testte izole bir geçici dizine yönlendiren sahte platform.
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

const _validApi = [
  {'week': 10, 'fruit': 'apiMeyve', 'emoji': '🍇', 'size': '~9 cm', 'note': 'api notu 10'},
  {'week': 20, 'fruit': 'apiMuz', 'emoji': '🍌', 'size': '~25 cm', 'note': 'api notu 20'},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('preg_repo_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File cacheFile() => File('${tmp.path}/pregnancy_weeks.json');

  group('load() — API başarılı', () {
    test('API verisi parse edilir ve cache dosyasına yazılır', () async {
      adapter.onGet('/content/pregnancy-weeks', (s) => s.reply(200, _validApi));
      final repo = PregnancyRepository(api);

      final data = await repo.load();

      expect(data.stageFor(10).fruit, 'apiMeyve');
      expect(data.stageFor(20).fruit, 'apiMuz');
      expect(data.noteFor(10), 'api notu 10');
      // Cache yazıldı mı?
      expect(await cacheFile().exists(), isTrue);
      expect(await cacheFile().readAsString(), contains('apiMeyve'));
    });
  });

  group('load() — ikinci açılış cache okur', () {
    test('API erişilemezse önceden yazılan cache kullanılır', () async {
      // 1) İlk yükleme: API başarılı → cache yazılır.
      adapter.onGet('/content/pregnancy-weeks', (s) => s.reply(200, _validApi));
      await PregnancyRepository(api).load();
      expect(await cacheFile().exists(), isTrue);

      // 2) İkinci yükleme: yeni istemci + API hatası → cache'ten okumalı.
      final api2 = ApiClient(_FakeTokens());
      DioAdapter(dio: api2.dio)
          .onGet('/content/pregnancy-weeks', (s) => s.reply(500, <String, dynamic>{}));
      final data = await PregnancyRepository(api2).load();

      expect(data.stageFor(10).fruit, 'apiMeyve');
      expect(data.stageFor(20).fruit, 'apiMuz');
    });
  });

  group('load() — fallback davranışları', () {
    test('API boş liste döner + cache yok → gömülü tabloya düşer', () async {
      adapter.onGet('/content/pregnancy-weeks', (s) => s.reply(200, const []));
      final data = await PregnancyRepository(api).load();

      // Gömülü değer (muz @20). Boş liste cache'e YAZILMAMALI.
      expect(data.stageFor(20).fruit, 'muz');
      expect(await cacheFile().exists(), isFalse,
          reason: 'boş liste cache yazmamalı');
    });

    test('API ağ hatası + cache yok → gömülü tablo', () async {
      adapter.onGet(
          '/content/pregnancy-weeks', (s) => s.reply(500, <String, dynamic>{}));
      final data = await PregnancyRepository(api).load();
      expect(data.stageFor(20).fruit, 'muz');
    });

    test('gömülü fallback PregnancyWeeksData.embedded ile birebir', () async {
      adapter.onGet('/content/pregnancy-weeks', (s) => s.reply(200, const []));
      final data = await PregnancyRepository(api).load();
      for (var w = 4; w <= 40; w++) {
        expect(data.stageFor(w).fruit,
            PregnancyWeeksData.embedded.stageFor(w).fruit);
      }
    });
  });

  group('load() — bozuk veri', () {
    test('week alanı olmayan kayıtlar atlanır; hepsi geçersizse gömülü', () async {
      adapter.onGet('/content/pregnancy-weeks', (s) => s.reply(200, const [
            {'fruit': 'gecersiz'},
            {'emoji': '❌'},
          ]));
      final data = await PregnancyRepository(api).load();
      // Liste boş değil → cache yazılır, ama parse sonrası gömülüye düşer.
      expect(data.stageFor(20).fruit, 'muz');
    });

    test('geçerli + geçersiz karışık → geçerliler okunur', () async {
      adapter.onGet('/content/pregnancy-weeks', (s) => s.reply(200, const [
            {'week': 12, 'fruit': 'karisik12', 'emoji': '🍋', 'size': '~5 cm'},
            'saçma',
            42,
          ]));
      final data = await PregnancyRepository(api).load();
      expect(data.stageFor(12).fruit, 'karisik12');
    });

    test('bozuk cache dosyası + API hatası → güvenle gömülüye düşer', () async {
      await cacheFile().writeAsString('}{ bozuk json');
      adapter.onGet(
          '/content/pregnancy-weeks', (s) => s.reply(500, <String, dynamic>{}));
      final data = await PregnancyRepository(api).load();
      expect(data.stageFor(20).fruit, 'muz');
    });
  });
}
