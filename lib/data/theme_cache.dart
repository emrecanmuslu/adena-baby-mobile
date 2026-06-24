import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

/// Son seçilen tema modunu kalıcı saklar — açılışta ANINDA okunur, böylece splash
/// ve ilk frame doğru temada gelir (sistem koyu olsa bile 'Açık' seçiliyse açık).
/// API/sunucu değeri gelince güncellenir. Değerler: light | dark | auto.
///
/// Depo: SharedPreferences (iOS NSUserDefaults). Eskiden Keychain'deydi; soğuk
/// başlatmada Keychain takılıp koyu splash'te donmaya yol açabiliyordu → taşındı.
class ThemeCache {
  static const _kTheme = 'app_theme_mode';

  Future<ThemeMode> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final (v, _) = await LocalPrefs.migrateString(prefs, _kTheme);
      return _fromStr(v);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> write(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTheme, _toStr(mode));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTheme);
    } catch (_) {}
  }

  static ThemeMode _fromStr(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _toStr(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'auto',
      };
}
