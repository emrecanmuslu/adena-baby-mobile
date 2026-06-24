import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

/// Geliştirici ortam değiştirici (YALNIZ debug) — seçili API tabanını kalıcı
/// saklar. null/boş = derleme varsayılanı. Açılışta AppConfig'e uygulanır.
///
/// Depo: SharedPreferences (iOS NSUserDefaults) — açılış yolunda Keychain takılması
/// olmasın diye taşındı (gizli değil, yalnız debug seçimi).
class EnvCache {
  static const _kEnv = 'dev_api_base_url';

  Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final (v, _) = await LocalPrefs.migrateString(prefs, _kEnv);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEnv, url);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kEnv);
    } catch (_) {}
  }
}
