import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

/// Son bilinen premium durumunu kalıcı saklar — açılışta ANINDA (flaş'sız) okunur,
/// API gelince güncellenir. Böylece premium kullanıcıya hiçbir ekranda rozet/kilit
/// flaş'ı görünmez.
///
/// Depo: SharedPreferences (iOS NSUserDefaults) — açılış yolunda Keychain takılması
/// olmasın diye taşındı (gizli değil; gerçek yetki RevenueCat/sunucudan doğrulanır).
class SubscriptionCache {
  static const _kPremium = 'sub_is_premium';

  Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final (v, _) = await LocalPrefs.migrateString(prefs, _kPremium);
      return v == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> write(bool isPremium) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPremium, isPremium ? '1' : '0');
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPremium);
    } catch (_) {}
  }
}
