import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/core/session_end.dart';
import 'package:adena_baby/core/revenuecat_service.dart';
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
    SharedPreferences.setMockInitialValues({}); // LocalSession önbelleği için temiz depo
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

    test(
        'gerçek auth reddi → interceptor token\'ları siler (hasSession false) → null',
        () async {
      // Üretimde geçersiz refresh → api_client._refresh clear() çağırır; bu yüzden
      // build() catch\'ine gelindiğinde token gitmiştir. me() bunu modeller.
      tokens.access = 'BAD';
      when(() => repo.me()).thenAnswer((_) async {
        await tokens.clear(); // interceptor\'ın gerçek reddi sildi
        throw Exception('401');
      });

      final c = makeContainer();
      final user = await c.read(authControllerProvider.future);

      expect(user, isNull);
      expect(tokens.clearCount, 1);
    });

    test(
        'geçici ağ hatası + önbellek YOK → token KORUNUR, null (login ama veri kaybı yok)',
        () async {
      // me() ağ hatasıyla patlar; interceptor token\'ı silmez → hasSession true.
      // Önbellek de yok → null döner AMA token silinmez (sonraki açılış düzelir).
      tokens.access = 'ACC';
      when(() => repo.me()).thenThrow(Exception('network'));

      final c = makeContainer();
      final user = await c.read(authControllerProvider.future);

      expect(user, isNull);
      expect(tokens.clearCount, 0, reason: 'geçici hatada oturum korunmalı');
      expect(tokens.access, 'ACC');
    });

    test(
        'geçici ağ hatası + önbellek VAR → önbellekteki kullanıcıyla devam (offline)',
        () async {
      // Daha önce başarılı /auth/me kullanıcıyı önbelleğe almış olsun.
      await LocalSession.cacheAuthUser(_user(id: 'cached1').toJson());
      tokens.access = 'ACC';
      when(() => repo.me()).thenThrow(Exception('network'));

      final c = makeContainer();
      final user = await c.read(authControllerProvider.future);

      expect(user, isNotNull);
      expect(user!.id, 'cached1');
      expect(LocalSession.activeAccountId, 'cached1');
      expect(tokens.clearCount, 0);
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

  // ───────── K9: arka plan isolate'inde yan isler baslamasin ─────────
  group('K9 — runningInBackgroundProvider', () {
    late List<String> rcIdentified;

    setUp(() {
      LocalSession.resetForTests();
      rcIdentified = [];
      RevenueCatService.instance.identifyHook = rcIdentified.add;
    });

    tearDown(() {
      RevenueCatService.instance.identifyHook = null;
      LocalSession.resetForTests();
    });

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('bg=true: önbellekli kullanıcı döner; /auth/me, initialImport, RC identify, exitGuest HİÇ başlamaz',
        () async {
      await LocalSession.enterGuest(); // bayat misafir bayrağı (bg'de dokunulmamalı)
      await LocalSession.cacheAuthUser(_user(id: 'bg1').toJson());
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'bg1'));

      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(tokens),
        initialImportProvider.overrideWithValue(import),
        runningInBackgroundProvider.overrideWithValue(true),
      ]);
      addTearDown(c.dispose);

      final user = await c.read(authControllerProvider.future);
      await settle();

      expect(user!.id, 'bg1');
      expect(LocalSession.activeAccountId, 'bg1', reason: 'DB kapsamı bg\'de kurulmalı');
      verifyNever(() => repo.me());
      verifyNever(() => import.runIfNeeded());
      expect(rcIdentified, isEmpty);
      expect(LocalSession.guest, isTrue, reason: 'exitGuest bg\'de çağrılmamalı');
    });

    test('bg=false (varsayılan): önbellek yolu /auth/me + initialImport + RC + exitGuest başlatır',
        () async {
      await LocalSession.enterGuest();
      await LocalSession.cacheAuthUser(_user(id: 'fg1').toJson());
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'fg1'));

      final c = makeContainer();
      final user = await c.read(authControllerProvider.future);
      await settle();

      expect(user!.id, 'fg1');
      verify(() => repo.me()).called(1);
      verify(() => import.runIfNeeded()).called(1);
      expect(rcIdentified, contains('fg1'));
      expect(LocalSession.guest, isFalse);
    });

    test('bg=true + önbellek yok: /auth/me beklenir (zorunlu) ama initialImport/RC yine başlamaz',
        () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'bg2'));
      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(tokens),
        initialImportProvider.overrideWithValue(import),
        runningInBackgroundProvider.overrideWithValue(true),
      ]);
      addTearDown(c.dispose);
      final user = await c.read(authControllerProvider.future);
      await settle();
      expect(user!.id, 'bg2');
      verify(() => repo.me()).called(1);
      verifyNever(() => import.runIfNeeded());
      expect(rcIdentified, isEmpty);
    });
  });

  // ───────── O34: logout ile arka plan /auth/me yarışı (epoch) ─────────
  group('O34 — logout sonrası geç gelen /auth/me oturumu geri getirmez', () {
    setUp(() => LocalSession.resetForTests());
    tearDown(() => LocalSession.resetForTests());

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('_refreshInBackground: me() çıkıştan SONRA dönerse state/cache/kapsam/import dokunulmaz',
        () async {
      await LocalSession.cacheAuthUser(_user(id: 'r1').toJson());
      tokens.access = 'ACC';
      final gate = Completer<User>();
      when(() => repo.me()).thenAnswer((_) => gate.future);
      when(() => repo.logout()).thenAnswer((_) async {});

      final c = makeContainer();
      final u = await c.read(authControllerProvider.future);
      expect(u!.id, 'r1');

      await c.read(authControllerProvider.notifier).logout();
      expect(c.read(authControllerProvider).value, isNull);

      gate.complete(_user(id: 'r1')); // geç gelen /auth/me
      await settle();

      expect(c.read(authControllerProvider).value, isNull,
          reason: 'çıkış sonrası oturum geri gelmemeli');
      expect(await LocalSession.cachedAuthUser(), isNull,
          reason: 'önbellek yeniden yazılmamalı');
      expect(LocalSession.activeAccountId, isNull);
      verifyNever(() => import.runIfNeeded());
    });

    test('updateName: çıkıştan sonra dönen yanıt state\'i geri getirmez', () async {
      tokens.access = 'ACC';
      await LocalSession.cacheAuthUser(_user(id: 'n1').toJson());
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'n1'));
      when(() => repo.logout()).thenAnswer((_) async {});
      final gate = Completer<User>();
      when(() => repo.updateName('Yeni')).thenAnswer((_) => gate.future);

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      await settle();
      final ctrl = c.read(authControllerProvider.notifier);
      final pending = ctrl.updateName('Yeni');
      await ctrl.logout();
      gate.complete(User(id: 'n1', email: 'a@b.com', name: 'Yeni'));
      await pending;
      expect(c.read(authControllerProvider).value, isNull);
    });
  });

  group('O1 — sessionExpired / verifySession / kanca ömrü', () {
    setUp(() => LocalSession.resetForTests());
    tearDown(() => LocalSession.resetForTests());

    Future<String?> prefsReason() async =>
        (await SharedPreferences.getInstance()).getString(SessionEndCache.key);

    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test(
        'sessionExpired: state null, token/önbellek/kapsam/abonelik temiz; repo.logout YOK; slot haritası dokunulmaz',
        () async {
      SharedPreferences.setMockInitialValues({
        'baby_notif_slots': '{"b1":3}',
        'sub_is_premium': true,
      });
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'e1'));
      when(() => repo.logout()).thenAnswer((_) async {});

      final c = makeContainer();
      await c.read(authControllerProvider.future);
      expect(LocalSession.activeAccountId, 'e1');

      await c
          .read(authControllerProvider.notifier)
          .sessionExpired(SessionEndReason.superseded);

      expect(c.read(authControllerProvider).value, isNull);
      expect(await tokens.hasSession, isFalse);
      expect(LocalSession.activeAccountId, isNull);
      expect(await LocalSession.cachedAuthUser(), isNull);
      expect(c.read(sessionEndReasonProvider), SessionEndReason.superseded);
      expect(await prefsReason(), 'superseded');
      verifyNever(() => repo.logout()); // yetki yok → POST /auth/logout atılmaz
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('baby_notif_slots'), '{"b1":3}',
          reason: 'SlotRegistry korunur (yerel hatırlatıcılar sürer)');
      expect(prefs.getBool('sub_is_premium'), isNull,
          reason: 'abonelik önbelleği temizlenir');
    });

    test(
        'verifySession: state User ama token yok → prefs nedeniyle zorunlu çıkış',
        () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'v1'));
      final c = makeContainer();
      await c.read(authControllerProvider.future);

      // Başka isolate (bg turu) refresh reddi aldı: token sildi + prefs yazdı.
      tokens.access = null;
      await SessionEndCache.write(SessionEndReason.expired);

      await c.read(authControllerProvider.notifier).verifySession();

      expect(c.read(authControllerProvider).value, isNull);
      expect(c.read(sessionEndReasonProvider), SessionEndReason.expired);
      expect(LocalSession.activeAccountId, isNull);
    });

    test('verifySession: token varsa no-op', () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'v2'));
      final c = makeContainer();
      await c.read(authControllerProvider.future);

      await c.read(authControllerProvider.notifier).verifySession();

      expect(c.read(authControllerProvider).value?.id, 'v2');
      expect(c.read(sessionEndReasonProvider), isNull);
    });

    test('kanca: build atar; ApiClient çağırınca zorunlu çıkış; dispose sıfırlar',
        () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'h1'));
      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final api = c.read(apiClientProvider);
      expect(api.onSessionRejected, isNotNull);

      api.onSessionRejected!(SessionEndReason.superseded);
      await settle();
      expect(c.read(authControllerProvider).value, isNull);
      expect(c.read(sessionEndReasonProvider), SessionEndReason.superseded);

      c.dispose();
      expect(api.onSessionRejected, isNull,
          reason: 'eski notifier RestartWidget sonrası çağrılmamalı');
    });

    test('kanca: invalidate (RestartWidget) sonrası yeni notifier kancası durur',
        () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'h2'));
      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final api = c.read(apiClientProvider);
      final first = api.onSessionRejected;

      c.invalidate(authControllerProvider);
      await c.read(authControllerProvider.future);

      expect(api.onSessionRejected, isNotNull);
      expect(identical(api.onSessionRejected, first), isFalse);
    });

    test('kanca: oturum yokken (misafir/çıkmış) çağrı no-op', () async {
      final c = makeContainer();
      await c.read(authControllerProvider.future);
      final api = c.read(apiClientProvider);

      api.onSessionRejected!(SessionEndReason.unknown);
      await settle();

      expect(c.read(authControllerProvider).value, isNull);
      expect(c.read(sessionEndReasonProvider), isNull);
    });

    test('bg=true: kanca ATANMAZ', () async {
      tokens.access = 'ACC';
      when(() => repo.me()).thenAnswer((_) async => _user(id: 'h3'));
      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStorageProvider.overrideWithValue(tokens),
        initialImportProvider.overrideWithValue(import),
        runningInBackgroundProvider.overrideWithValue(true),
      ]);
      addTearDown(c.dispose);
      await c.read(authControllerProvider.future);
      expect(c.read(apiClientProvider).onSessionRejected, isNull);
    });

    test('prefs nedeni: başarılı giriş ve kullanıcı çıkışı temizler', () async {
      await SessionEndCache.write(SessionEndReason.superseded);
      when(() => repo.login(
              email: any(named: 'email'), password: any(named: 'password')))
          .thenAnswer((_) async => _user(id: 'p1'));
      when(() => repo.logout()).thenAnswer((_) async {});
      final c = makeContainer();
      await c.read(authControllerProvider.future);
      c.read(sessionEndReasonProvider.notifier).set(SessionEndReason.superseded);

      await c
          .read(authControllerProvider.notifier)
          .login(email: 'a@b.c', password: 'x');
      expect(await prefsReason(), isNull, reason: 'giriş eski nedeni siler');
      expect(c.read(sessionEndReasonProvider), isNull);

      await SessionEndCache.write(SessionEndReason.expired);
      tokens.access = 'ACC';
      await c.read(authControllerProvider.notifier).logout();
      expect(await prefsReason(), isNull,
          reason: 'kullanıcı çıkışı neden bırakmaz');
    });
  });
}
