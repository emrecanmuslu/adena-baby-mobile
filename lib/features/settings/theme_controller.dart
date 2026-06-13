import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../data/auth_repository.dart';
import '../../data/theme_cache.dart';
import '../auth/auth_controller.dart';

/// Açılışta cache'ten okunan tema (main.dart bu provider'ı override eder).
/// themeController henüz yüklenmeden ilk frame (splash) doğru temada gelsin diye
/// fallback olarak bunu kullanırız — sistem yerine son seçilen tema.
final cachedThemeProvider = Provider<ThemeMode>((_) => ThemeMode.system);

/// Tema modu — UserSettings.theme'den yüklenir, değişince sunucuya + cache'e kaydedilir.
/// API değerleri: light | dark | auto.
class ThemeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    // Oturum yoksa son seçilen yerel temayı kullan (system'e düşme → splash flaş'ı yok).
    final cached = ref.read(cachedThemeProvider);
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) return cached;
    try {
      final s = await ref.read(authRepositoryProvider).settings();
      final mode = _fromApi(s['theme'] as String?);
      unawaited(ThemeCache().write(mode)); // sonraki açılış için sakla
      return mode;
    } catch (_) {
      return cached;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = AsyncData(mode);
    unawaited(ThemeCache().write(mode)); // açılışta flaş'sız okunsun
    try {
      await ref.read(authRepositoryProvider).updateSettings({'theme': _toApi(mode)});
    } catch (_) {
      // Çevrimdışı/hata — yerel seçim korunur, sonraki açılışta sunucudan gelir.
    }
  }

  static ThemeMode _fromApi(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _toApi(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'auto',
      };

  static String label(ThemeMode m) => switch (m) {
        ThemeMode.light => tr('Açık'),
        ThemeMode.dark => tr('Koyu'),
        ThemeMode.system => tr('Sistem'),
      };
}

final themeControllerProvider =
    AsyncNotifierProvider<ThemeController, ThemeMode>(ThemeController.new);
