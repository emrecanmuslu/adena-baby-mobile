import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../data/auth_repository.dart';
import '../auth/auth_controller.dart';

/// Tema modu — UserSettings.theme'den yüklenir, değişince sunucuya kaydedilir.
/// API değerleri: light | dark | auto.
class ThemeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) return ThemeMode.system;
    try {
      final s = await ref.read(authRepositoryProvider).settings();
      return _fromApi(s['theme'] as String?);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = AsyncData(mode);
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
