import 'package:shared_preferences/shared_preferences.dart';

/// Tüm API istek/yanıtlarının kalıcı halka-tampon kaydı (method · path · status ·
/// süre · hata). Dio interceptor'ı yazar (bkz [ApiClient]). HASSAS veri TUTMAZ:
/// yalnız method/path/durum/süre — gövde, header, token YOK. Android'de
/// `adb run-as ... cat shared_prefs/FlutterSharedPreferences.xml` ile, debug'da
/// /dev ekranındaki "API Log" bölümünden okunur. Son [_max] giriş tutulur.
class ApiLog {
  static const _key = 'api_log';
  static const _max = 150;

  /// Tek satır ekler ('MM-ddTHH:mm:ss ' damgalı). Asla patlamaz, asla bloklamaz.
  static Future<void> add(String line) async {
    try {
      // reload YOK: API çağrıları ön plan tek isolate → bellekteki kopya güncel.
      // Her istekte disk re-read maliyetinden kaçın (sık çağrılır).
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_key) ?? <String>[];
      final ts = DateTime.now().toIso8601String().substring(5, 19);
      list.add('$ts $line');
      if (list.length > _max) list.removeRange(0, list.length - _max);
      await p.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<List<String>> readAll() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      return p.getStringList(_key) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}
