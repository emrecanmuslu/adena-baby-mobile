import 'package:shared_preferences/shared_preferences.dart';

/// Ana sayfada günde-en-fazla-bir-kez gösterilen dürtmeler (ör. "ilaç verdin
/// mi?" snackbar'ı, "dünün özeti" popup'ı) için cihaz-yerel "bugün gösterildi
/// mi" bayrağı. Anahtar başına bir tarih (yyyy-MM-dd) tutar; gün değişince
/// otomatik "gösterilmedi" sayılır.
class HomeNudgePrefs {
  HomeNudgePrefs._();
  static final HomeNudgePrefs instance = HomeNudgePrefs._();

  static String _key(String id) => 'home_nudge_$id';
  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<bool> shownToday(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(id)) == _today();
    } catch (_) {
      return true; // okunamazsa gösterme (tekrar tekrar çıkmasın)
    }
  }

  Future<void> markShownToday(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(id), _today());
    } catch (_) {}
  }

  // ── Kalıcı kapatma (gün-bazlı değil) — ör. ana sayfa İlaç & Vitamin keşif
  // kartı: kullanıcı X ile kapatınca bir daha çıkmaz. Cihaz-yerel UI tercihi;
  // senkron edilmez, veri modeline girmez.
  static String _dismissKey(String id) => 'home_dismissed_$id';

  Future<bool> dismissed(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_dismissKey(id)) ?? false;
    } catch (_) {
      return true; // okunamazsa gösterme
    }
  }

  Future<void> dismiss(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissKey(id), true);
    } catch (_) {}
  }
}
