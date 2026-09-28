import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/record.dart';

/// Ana sayfa "Hızlı Giriş" / "Son Aktivite" özelleştirmesinin son bilinen halini
/// kalıcı saklar — açılışta ANINDA (flaş'sız) okunur, sunucudan gelen değer
/// gelince güncellenir. Böylece kullanıcının seçtiği kartlar yerine varsayılan
/// (beslenme·bez·uyku) bir an için gösterilip hemen değişmez.
///
/// Depo: SharedPreferences (iOS NSUserDefaults) — gizli değil, diğer *_cache.dart
/// dosyalarıyla aynı desen (bkz. ThemeCache, SubscriptionCache).
class HomeLayoutCache {
  static const _kQuick = 'home_layout_quick';
  static const _kLastActivity = 'home_layout_last_activity';

  Future<List<RecordType>?> readQuick() => _read(_kQuick);
  Future<List<RecordType>?> readLastActivity() => _read(_kLastActivity);

  Future<void> writeQuick(List<RecordType> types) => _write(_kQuick, types);
  Future<void> writeLastActivity(List<RecordType> types) =>
      _write(_kLastActivity, types);

  Future<List<RecordType>?> _read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final d = jsonDecode(raw);
      if (d is! List) return null;
      final out = <RecordType>[];
      for (final e in d) {
        if (e is! String) continue;
        for (final t in RecordType.values) {
          if (t.name == e) {
            out.add(t);
            break;
          }
        }
      }
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, List<RecordType> types) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(types.map((t) => t.name).toList()));
    } catch (_) {}
  }
}
