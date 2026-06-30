import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

/// Beslenme formunda son girilen değerleri (tarih hariç) alt-tür bazında kalıcı
/// saklar — böylece Mama/Sağılmış/Katı için aynı miktarı tekrar tekrar girmek
/// gerekmez. Anne sütü (breast) HARİÇ: o kronometre/taraf bazlı, her seferinde değişir.
///
/// Senkron erişim için bellek-içi katman + SharedPreferences yedeği. Açılışta
/// [ensureLoaded] ile belleğe alınır; form senkron [get] ile okur. (Eskiden
/// Keychain'deydi; iOS Keychain quirk'lerinden kaçınmak için prefs'e taşındı.)
class FeedInputCache {
  static const _subs = ['formula', 'pumped', 'solid'];
  static final Map<String, Map<String, String>> _mem = {};
  static bool _loaded = false;

  /// Uygulama açılışında bir kez çağrılır (main). Tekrar çağrı no-op.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final sub in _subs) {
        try {
          final (raw, _) = await LocalPrefs.migrateString(prefs, 'feed_last_$sub');
          if (raw != null && raw.isNotEmpty) {
            _mem[sub] = Map<String, String>.from(jsonDecode(raw) as Map);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Bir alt-türün son değerleri (yoksa boş). Senkron.
  static Map<String, String> get(String sub) => _mem[sub] ?? const {};

  /// Bir alt-türün son değerlerini sakla (breast yok sayılır).
  static Future<void> put(String sub, Map<String, String> fields) async {
    if (sub == 'breast' || !_subs.contains(sub)) return;
    _mem[sub] = fields;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('feed_last_$sub', jsonEncode(fields));
    } catch (_) {}
  }

  static Future<void> clear() async {
    _mem.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final sub in _subs) {
        try {
          await prefs.remove('feed_last_$sub');
        } catch (_) {}
      }
    } catch (_) {}
  }
}
