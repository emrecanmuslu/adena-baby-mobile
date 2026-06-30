import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

/// Son seçilen dili kalıcı saklar — açılışta ANINDA okunur (sunucu beklemeden).
/// Dil değişiminde uygulama yeniden başlatıldığı için, doğru dilin restart
/// sonrasında ve çevrimdışıyken de korunması bu cache'e bağlıdır. Sunucu değeri
/// gelince güncellenir. Değerler: 'tr' | 'en' | ...
///
/// Depo: SharedPreferences (iOS NSUserDefaults). Eskiden Keychain'deydi; iOS'ta
/// soğuk başlatma/warm-resume sırasında Keychain takılıp dil sıfırlanabiliyordu
/// → prefs'e taşındı (eski Keychain değeri tek seferlik göç edilir).
class LocaleCache {
  static const _kLocale = 'app_locale';

  Future<String?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final (v, _) = await LocalPrefs.migrateString(prefs, _kLocale);
      final t = v?.trim();
      return (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLocale, locale);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLocale);
    } catch (_) {}
  }
}
