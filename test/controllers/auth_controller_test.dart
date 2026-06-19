import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/auth_repository.dart';
import 'package:adena_baby/data/initial_import.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/social_auth_service.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/models/user.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockInitialImportService extends Mock implements InitialImportService {}

class MockSocialAuthService extends Mock implements SocialAuthService {}

/// In-memory [TokenStorage] stand-in so [AuthController.build] can decide whether
/// there is a session without touching flutter_secure_storage.
class _FakeTokens implements TokenStorage {
  String? access;
  String? refresh;
  int clearCount = 0;

  @override
  Future<String?> get accessToken async => access;
  @override
  Future<String?> get refreshToken async => refresh;
  @override
  Future<bool> get hasSession async => access != null;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    this.access = access;
    if (refresh != null) this.refresh = refresh;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    access = null;
    refresh = null;
  }
}

/// PushService.unregister + RevenueCatService + SubscriptionCache touch native
/// channels (Firebase, secure storage). All are individually wrapped in
/// try/catch in production, but RevenueCat is a no-op while unconfigured and we
/// stub the secure-storage channel here so logout/deleteAccount stay quiet.
void _installSecureStorageMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => null,
  );
}

User _user({String id = 'u1', bool consentRequired = false}) => User(
      id: id,
      email: 'a@b.com',
      name: 'Ada',
      consentRequired: consentRequired,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_user());
  });

  late MockAuthRepository repo;
  late MockInitialImportService import;
  late _FakeTokens tokens;

  setUp(() {
    _installSecureStorageMock();
    repo = MockAuthRepository();
    import = MockInitialImportService();
    tokens = _FakeTokens();
    when(() => import.runIfNeeded()).thenAnswer((_) async {});
    LocalSession.setActiveAccount(null);
  });

  tearDown(() {
    LocalSession.setActiveAccount(null);
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(tokens),
      initialImportProvider.overrideWithValue(import),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('build (initial state)', () {
    test('no session → null user, no /auth/me call', () async {
      // tokens.access stays null → hasSession false.
      final c = makeContainer();
      final user = await c.read(authControllerProvider.future);

      expect(user, isNull);
      verifyNever(() => repo.me());
    });

    test('valid session → resolves user from repo.me() + activates account',
        () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'me1'));

      final c = makeContainer();
      final user = await c.read(authControllerProvider.future);

      expect(user!.id, 'me1');
      expect(LocalSession.activeAccountId, 'me1');
      verify(() => repo.me()).called(1);
      verify(() => import.runIfNeeded()).called(1);
    });

    test('invalid token → me() throws → clears tokens, falls to null', () async {
      tokens.access = 'BAD';
      when(() => repo.me()).thenThrow(Exception('401'));

      final c = makeContainer();
      final user = await c.read(authControllerProvider.future);

      expect(user, isNull);
      expect(tokens.clearCount, 1);
    });
  });

  group('login', () {
    test('success → state holds user, repo called with email/password', () async {
      when(() => repo.login(email: 'a@b.com', password: 'pw'))
          .thenAnswer((_) async => _user(id: 'lg1'));

      final c = makeContainer();
      await c.read(authControllerProvider.future); // resolve build → null
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.login(email: 'a@b.com', password: 'pw');

      expect(c.read(authControllerProvider).value!.id, 'lg1');
      expect(LocalSession.activeAccountId, 'lg1');
      verify(() => repo.login(email: 'a@b.com', password: 'pw')).called(1);
      verify(() => import.runIfNeeded()).called(1);
    });

    test('failure → state becomes AsyncError (loading surfaced first)',
        () async {
      when(() => repo.login(email: any(named: 'email'), password: any(named: 'password')))
          .thenThrow(Exception('bad creds'));

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.login(email: 'a@b.com', password: 'x');

      expect(c.read(authControllerProvider).hasError, isTrue);
      // No account activated on failure.
      expect(LocalSession.activeAccountId, isNull);
    });
  });

  group('register', () {
    test('success → state holds user + import runs', () async {
      when(() => repo.register(
              email: 'a@b.com', password: 'pw', name: 'Ada'))
          .thenAnswer((_) async => _user(id: 'rg1'));

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.register(email: 'a@b.com', password: 'pw', name: 'Ada');

      expect(c.read(authControllerProvider).value!.id, 'rg1');
      verify(() => repo.register(email: 'a@b.com', password: 'pw', name: 'Ada'))
          .called(1);
      verify(() => import.runIfNeeded()).called(1);
    });
  });

  group('socialLogin', () {
    test('google success → exchanges idToken via repo.social, sets user',
        () async {
      final social = MockSocialAuthService();
      when(() => social.google()).thenAnswer((_) async => 'idtok');
      when(() => repo.social(provider: 'google', idToken: 'idtok'))
          .thenAnswer((_) async => _user(id: 'soc1'));

      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(tokens),
        initialImportProvider.overrideWithValue(import),
        socialAuthServiceProvider.overrideWithValue(social),
      ]);
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.socialLogin('google');

      expect(c.read(authControllerProvider).value!.id, 'soc1');
      verify(() => repo.social(provider: 'google', idToken: 'idtok')).called(1);
    });

    test('user cancels provider screen → idToken null → stays logged out',
        () async {
      final social = MockSocialAuthService();
      when(() => social.google()).thenAnswer((_) async => null);

      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(tokens),
        initialImportProvider.overrideWithValue(import),
        socialAuthServiceProvider.overrideWithValue(social),
      ]);
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.socialLogin('google');

      expect(c.read(authControllerProvider).value, isNull);
      verifyNever(() => repo.social(
          provider: any(named: 'provider'), idToken: any(named: 'idToken')));
    });
  });

  group('recordConsent', () {
    test('writes consent then clears consentRequired on the user', () async {
      tokens.access = 'ACC';
      when(() => repo.me())
          .thenAnswer((_) async => _user(id: 'c1', consentRequired: true));
      when(() => repo.recordConsent()).thenAnswer((_) async {});

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final ctrl = c.read(authControllerProvider.notifier);

      expect(c.read(authControllerProvider).value!.consentRequired, isTrue);
      await ctrl.recordConsent();

      verify(() => repo.recordConsent()).called(1);
      expect(c.read(authControllerProvider).value!.consentRequired, isFalse);
    });
  });

  group('updateName', () {
    test('replaces state with repo-returned user', () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'n1'));
      when(() => repo.updateName('Yeni'))
          .thenAnswer((_) async => User(id: 'n1', email: 'a@b.com', name: 'Yeni'));

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.updateName('Yeni');

      expect(c.read(authControllerProvider).value!.name, 'Yeni');
      verify(() => repo.updateName('Yeni')).called(1);
    });
  });

  group('logout', () {
    test('calls repo.logout, clears active account, state → null', () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'out1'));
      when(() => repo.logout()).thenAnswer((_) async {});

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      expect(LocalSession.activeAccountId, 'out1');
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.logout();

      verify(() => repo.logout()).called(1);
      expect(c.read(authControllerProvider).value, isNull);
      expect(LocalSession.activeAccountId, isNull);
    });
  });

  group('deleteAccount', () {
    test('calls repo.deleteAccount, state → null', () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'd1'));
      when(() => repo.deleteAccount()).thenAnswer((_) async {});

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final ctrl = c.read(authControllerProvider.notifier);

      await ctrl.deleteAccount();

      verify(() => repo.deleteAccount()).called(1);
      expect(c.read(authControllerProvider).value, isNull);
    });
  });

  group('activeAccountIdProvider', () {
    test('mirrors the logged-in user id, null when logged out', () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'acc1'));
      when(() => repo.logout()).thenAnswer((_) async {});

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      expect(c.read(activeAccountIdProvider), 'acc1');

      await c.read(authControllerProvider.notifier).logout();
      expect(c.read(activeAccountIdProvider), isNull);
    });
  });
}
