import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/data/auth_repository.dart';
import 'package:adena_baby/data/i18n_repository.dart';
import 'package:adena_baby/data/initial_import.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/settings/locale_controller.dart';
import 'package:adena_baby/models/user.dart';

class MockI18nRepository extends Mock implements I18nRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockInitialImportService extends Mock implements InitialImportService {}

/// In-memory [TokenStorage] so the real AuthController.build can resolve the
/// session state synchronously (set [access] for "logged in").
class _FakeTokens implements TokenStorage {
  String? access;
  @override
  Future<String?> get accessToken async => access;
  @override
  Future<String?> get refreshToken async => null;
  @override
  Future<bool> get hasSession async => access != null;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    this.access = access;
  }

  @override
  Future<void> clear() async => access = null;
}

/// In-memory backing for flutter_secure_storage so LocaleCache round-trips.
final Map<String, String> _store = {};

void _installSecureStorageMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'read':
          return _store[args['key'] as String];
        case 'write':
          _store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          _store.remove(args['key'] as String);
          return null;
        default:
          return null;
      }
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockI18nRepository i18n;
  late MockAuthRepository auth;
  late MockInitialImportService import;
  late _FakeTokens tokens;

  setUp(() {
    _store.clear();
    _installSecureStorageMock();
    i18n = MockI18nRepository();
    auth = MockAuthRepository();
    import = MockInitialImportService();
    tokens = _FakeTokens();
    when(() => i18n.report(any())).thenAnswer((_) async {});
    when(() => i18n.readCache(any()))
        .thenAnswer((_) async => (0, <String, String>{}));
    when(() => i18n.sync(any()))
        .thenAnswer((_) async => <String, String>{'Selam': 'Hi'});
    when(() => auth.settings()).thenAnswer((_) async => <String, dynamic>{});
    when(() => auth.updateSettings(any())).thenAnswer((_) async {});
    when(() => auth.me()).thenAnswer((_) async => _user());
    when(() => import.runIfNeeded()).thenAnswer((_) async {});
    LocalSession.setActiveAccount(null);
  });

  tearDown(() {
    LocalSession.setActiveAccount(null);
    // Reset shared singleton so other suites are unaffected.
    I18n.instance.apply('tr', const {});
  });

  /// [loggedIn] drives the real AuthController via a faked token store.
  Future<ProviderContainer> makeContainer({required bool loggedIn}) async {
    if (loggedIn) tokens.access = 'ACC';
    final c = ProviderContainer(overrides: [
      i18nRepositoryProvider.overrideWithValue(i18n),
      authRepositoryProvider.overrideWithValue(auth),
      tokenStorageProvider.overrideWithValue(tokens),
      initialImportProvider.overrideWithValue(import),
    ]);
    addTearDown(c.dispose);
    // Settle the auth session first so LocaleController.build sees a stable user.
    await c.read(authControllerProvider.future);
    return c;
  }

  group('build (initial state)', () {
    test('logged out + cached locale → uses cache, activates I18n', () async {
      _store['app_locale'] = 'en';

      final c = await makeContainer(loggedIn: false);
      final locale = await c.read(localeControllerProvider.future);

      expect(locale, 'en');
      expect(I18n.instance.locale, 'en');
      // Logged out path must not hit the server settings endpoint.
      verifyNever(() => auth.settings());
    });

    test('logged in, no cache → reads saved language from server settings',
        () async {
      when(() => auth.settings())
          .thenAnswer((_) async => <String, dynamic>{'language': 'en'});

      final c = await makeContainer(loggedIn: true);
      final locale = await c.read(localeControllerProvider.future);

      expect(locale, 'en');
      verify(() => auth.settings()).called(1);
    });
  });

  group('setLocale', () {
    test('updates state, writes cache, persists to server', () async {
      _store['app_locale'] = 'tr';
      final c = await makeContainer(loggedIn: true);
      await c.read(localeControllerProvider.future);
      final ctrl = c.read(localeControllerProvider.notifier);

      await ctrl.setLocale('en');

      expect(c.read(localeControllerProvider).value, 'en');
      expect(_store['app_locale'], 'en'); // written to LocaleCache
      expect(I18n.instance.locale, 'en'); // i18n applied
      verify(() => auth.updateSettings({'language': 'en'})).called(1);
    });

    test('en locale syncs the translation bundle and applies it', () async {
      _store['app_locale'] = 'tr';
      final c = await makeContainer(loggedIn: true);
      await c.read(localeControllerProvider.future);
      final ctrl = c.read(localeControllerProvider.notifier);

      await ctrl.setLocale('en');

      verify(() => i18n.sync('en')).called(1);
      // Synced bundle is live in the singleton.
      expect(I18n.instance.tr('Selam'), 'Hi');
    });

    test('server failure is swallowed; local selection still set', () async {
      when(() => auth.updateSettings(any())).thenThrow(Exception('offline'));
      _store['app_locale'] = 'tr';
      final c = await makeContainer(loggedIn: true);
      await c.read(localeControllerProvider.future);
      final ctrl = c.read(localeControllerProvider.notifier);

      await ctrl.setLocale('en');

      expect(c.read(localeControllerProvider).value, 'en');
      expect(_store['app_locale'], 'en');
    });

    test('switching to tr applies tr without syncing a bundle', () async {
      _store['app_locale'] = 'en';
      final c = await makeContainer(loggedIn: true);
      await c.read(localeControllerProvider.future);
      clearInteractions(i18n);
      final ctrl = c.read(localeControllerProvider.notifier);

      await ctrl.setLocale('tr');

      expect(c.read(localeControllerProvider).value, 'tr');
      expect(I18n.instance.locale, 'tr');
      verifyNever(() => i18n.sync(any()));
    });
  });

  group('label', () {
    test('maps locale codes to display names', () {
      expect(LocaleController.label('en'), 'English');
      expect(LocaleController.label('tr'), 'Türkçe');
      expect(LocaleController.label('xx'), 'Türkçe'); // default branch
    });
  });
}

User _user({String id = 'u1'}) => User(id: id, email: 'a@b.com', name: 'Ada');
