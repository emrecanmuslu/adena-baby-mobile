import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/core/session_end.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/auth_repository.dart';
import 'package:adena_baby/data/initial_import.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/auth/login_screen.dart';

class _MockRepo extends Mock implements AuthRepository {}

class _MockImport extends Mock implements InitialImportService {}

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

const _superseded =
    'Hesabına başka bir cihazdan giriş yapıldı; bu cihazdaki oturum kapatıldı.';
const _expired = 'Oturumun sona erdi. Lütfen tekrar giriş yap.';

/// O1 — giriş ekranı "oturum sona erdi" banner'ı: provider'dan ya da (başka
/// isolate/süreç düşürdüyse) prefs'ten BİR KEZ gösterilir; gösterince ikisi de
/// temizlenir. Neden yoksa banner yok.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    I18n.instance.apply('tr', const {});
    SharedPreferences.setMockInitialValues({});
  });

  Widget app(ProviderContainer c) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
      );

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_MockRepo()),
      tokenStorageProvider.overrideWithValue(_NoTokens()),
      initialImportProvider.overrideWithValue(_MockImport()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('provider nedeni → banner gösterilir, provider + prefs temizlenir',
      (tester) async {
    await SessionEndCache.write(SessionEndReason.superseded);
    final c = container();
    c.read(sessionEndReasonProvider.notifier).set(SessionEndReason.superseded);

    await tester.pumpWidget(app(c));
    await tester.pump();

    expect(find.text(_superseded), findsOneWidget);
    expect(c.read(sessionEndReasonProvider), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SessionEndCache.key), isNull);
  });

  testWidgets('yalnız prefs nedeni (bg isolate düşürdü) → banner yine çıkar',
      (tester) async {
    await SessionEndCache.write(SessionEndReason.expired);
    final c = container();

    await tester.pumpWidget(app(c));
    await tester.pump();
    await tester.pump();

    expect(find.text(_expired), findsOneWidget);
    expect(await SessionEndCache.read(), isNull);
  });

  testWidgets('neden yok → banner yok', (tester) async {
    final c = container();
    await tester.pumpWidget(app(c));
    await tester.pump();
    await tester.pump();
    expect(find.text(_superseded), findsNothing);
    expect(find.text(_expired), findsNothing);
  });
}
