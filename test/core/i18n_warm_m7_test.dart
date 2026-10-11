import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/i18n_warm.dart';
import 'package:adena_baby/data/local_prefs.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _FakePathProvider(this.root);
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// M7 (D17) — bg isolate girişinde prefs'teki dil + diskteki çeviri cache'i
/// ısıtılır → bildirim metinleri kullanıcının dilinde (ağ yok).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('i18n_warm');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    I18n.instance.apply('tr', const {});
  });

  tearDown(() async {
    I18n.instance.apply('tr', const {});
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('locale=en + cache → İngilizce bildirim metni', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    await File('${tmp.path}/i18n_en.json').writeAsString(jsonEncode({
      'version': 3,
      'strings': {'Kaydı unuttun mu?': 'Did you forget to log?', 'Ertele 10 dk': 'Snooze 10 min'}
    }));
    await warmI18nFromCache();
    expect(I18n.instance.locale, 'en');
    expect(tr('Kaydı unuttun mu?'), 'Did you forget to log?');
    expect(tr('Ertele 10 dk'), 'Snooze 10 min');
  });

  test('locale=en ama cache yok → Türkçe kalır, hata yok', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    await warmI18nFromCache();
    expect(tr('Kaydı unuttun mu?'), 'Kaydı unuttun mu?');
  });

  test('locale tr → tr', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'tr'});
    await warmI18nFromCache();
    expect(I18n.instance.locale, 'tr');
  });

  test('J13: prefs\'te dil yoksa Keychain göçü DENENMEZ (bg isolate takılmasın), tr kalır',
      () async {
    SharedPreferences.setMockInitialValues({});
    LocalPrefs.resetForTests();
    final kcCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
      kcCalls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), null));

    await warmI18nFromCache();

    expect(I18n.instance.locale, 'tr');
    expect(kcCalls, isEmpty, reason: 'bg\'de Keychain okuması yok');
  });
}
