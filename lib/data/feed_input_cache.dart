import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Beslenme formunda son girilen değerleri (tarih hariç) alt-tür bazında kalıcı
/// saklar — böylece Mama/Sağılmış/Katı için aynı miktarı tekrar tekrar girmek
/// gerekmez. Anne sütü (breast) HARİÇ: o kronometre/taraf bazlı, her seferinde değişir.
///
/// Senkron erişim için bellek-içi katman + secure storage yedeği. Açılışta
/// [ensureLoaded] ile belleğe alınır; form senkron [get] ile okur.
class FeedInputCache {
  static const _storage = FlutterSecureStorage();
  static const _subs = ['formula', 'pumped', 'solid'];
  static final Map<String, Map<String, String>> _mem = {};
  static bool _loaded = false;

  /// Uygulama açılışında bir kez çağrılır (main). Tekrar çağrı no-op.
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    for (final sub in _subs) {
      try {
        final raw = await _storage.read(key: 'feed_last_$sub');
        if (raw != null) {
          _mem[sub] = Map<String, String>.from(jsonDecode(raw) as Map);
        }
      } catch (_) {}
    }
  }

  /// Bir alt-türün son değerleri (yoksa boş). Senkron.
  static Map<String, String> get(String sub) => _mem[sub] ?? const {};

  /// Bir alt-türün son değerlerini sakla (breast yok sayılır).
  static Future<void> put(String sub, Map<String, String> fields) async {
    if (sub == 'breast' || !_subs.contains(sub)) return;
    _mem[sub] = fields;
    try {
      await _storage.write(key: 'feed_last_$sub', value: jsonEncode(fields));
    } catch (_) {}
  }

  static Future<void> clear() async {
    _mem.clear();
    for (final sub in _subs) {
      try {
        await _storage.delete(key: 'feed_last_$sub');
      } catch (_) {}
    }
  }
}
