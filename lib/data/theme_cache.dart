import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Son seçilen tema modunu kalıcı saklar — açılışta ANINDA okunur, böylece splash
/// ve ilk frame doğru temada gelir (sistem koyu olsa bile 'Açık' seçiliyse açık).
/// API/sunucu değeri gelince güncellenir. Değerler: light | dark | auto.
class ThemeCache {
  static const _storage = FlutterSecureStorage();
  static const _kTheme = 'app_theme_mode';

  Future<ThemeMode> read() async {
    try {
      return _fromStr(await _storage.read(key: _kTheme));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> write(ThemeMode mode) async {
    try {
      await _storage.write(key: _kTheme, value: _toStr(mode));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kTheme);
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
