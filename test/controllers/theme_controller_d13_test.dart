import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/data/auth_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/settings/theme_controller.dart';

class _NoTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => null;
  @override
  Future<String?> get refreshToken async => null;
  @override
  Future<bool> get hasSession async => false;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

class _MockAuthRepo extends Mock implements AuthRepository {}

/// D13 — misafirde seçilen tema, auth state her değişince (yanlış şifre →
/// AsyncError, sosyal iptal) açılış cache'ine geri dönmesin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setMode(dark) → auth yeniden yüklenince tema dark kalır', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = _MockAuthRepo();
    when(() => repo.updateSettings(any())).thenAnswer((_) async => <String, dynamic>{});
    final c = ProviderContainer(overrides: [
      tokenStorageProvider.overrideWithValue(_NoTokens()),
      authRepositoryProvider.overrideWithValue(repo),
      cachedThemeProvider.overrideWithValue(ThemeMode.light),
    ]);
    addTearDown(c.dispose);
    c.listen(themeControllerProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    expect(await c.read(themeControllerProvider.future), ThemeMode.light);

    await c.read(themeControllerProvider.notifier).setMode(ThemeMode.dark);
    expect(c.read(themeControllerProvider).value, ThemeMode.dark);

    c.invalidate(authControllerProvider); // yanlış şifre / iptal → auth emit
    await c.read(authControllerProvider.future);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.read(themeControllerProvider).value, ThemeMode.dark,
        reason: 'kullanıcının seçimi açılış cache\'ine (light) geri dönmemeli');
  });
}
