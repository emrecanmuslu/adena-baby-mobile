import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

/// İlk-giriş tanıtım turlarının "görüldü" durumunu kalıcı saklar. Ekran başına
/// bir anahtar; tur bir kez gösterilir. Tek bir CSV değerinde tutulur.
///
/// Depo: SharedPreferences (iOS NSUserDefaults). Eskiden Keychain'deydi; iOS'ta
/// push/warm-resume ile uyanışta Keychain okuması GEÇİCİ fırlatıp boş set
/// döndürüyordu (errSecInteractionNotAllowed) → tur, "Anladım" denmesine rağmen
/// her FCM push'tan sonra yeniden açılıyordu. Açılış-kritik gizli-olmayan veri
/// olduğundan prefs'e taşındı; eski Keychain değeri tek seferlik göç edilir.
class TourCache {
  static const _k = 'tour_seen_v1';

  Future<Set<String>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final (s, _) = await LocalPrefs.migrateString(prefs, _k);
      if (s == null || s.isEmpty) return <String>{};
      return s.split(',').where((e) => e.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> add(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cur = await read()
        ..add(key);
      await prefs.setString(_k, cur.join(','));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_k);
    } catch (_) {}
  }
}
