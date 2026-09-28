import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/data/auth_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/home/home_layout.dart';
import 'package:adena_baby/models/record.dart';
import 'package:adena_baby/models/user.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// Gerçek AuthController LocalSession/RevenueCat/token storage'a bağımlı —
/// bu testler yalnız HomeLayoutController'ın auth durumuna nasıl tepki
/// verdiğini ölçtüğü için build() burada sabit bir sonuca gölgelenir.
class _LoggedOutAuth extends AuthController {
  @override
  Future<User?> build() async => null;
}

class _LoggedInAuth extends AuthController {
  @override
  Future<User?> build() async => User(id: 'u1', email: 'a@b.com', name: 'Ada');
}

/// homeLayoutControllerProvider.future, iç içe AsyncNotifier watch zincirinde
/// (bu provider authControllerProvider'ı watch ediyor) riverpod'da bazen
/// sonsuza kadar 'loading'de takılıyor — aynı bilinen sorun için bkz.
/// async_providers_test.dart'taki drain() yardımcısı. Burada da dinleyip
/// pollüyoruz, `.future`'a güvenmiyoruz.
Future<HomeLayout> settle(ProviderContainer c) async {
  final sub = c.listen(homeLayoutControllerProvider, (prev, next) {});
  var v = sub.read();
  for (var i = 0; i < 200 && v.isLoading; i++) {
    await Future<void>.delayed(Duration.zero);
    v = sub.read();
  }
  sub.close();
  return v.value!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthRepository auth;

  setUp(() {
    auth = MockAuthRepository();
    SharedPreferences.setMockInitialValues({});
  });

  Future<String?> pref(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  ProviderContainer makeContainer({
    required bool loggedIn,
    HomeLayout cached = HomeLayout.fallback,
  }) {
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      authControllerProvider
          .overrideWith(loggedIn ? _LoggedInAuth.new : _LoggedOutAuth.new),
      cachedHomeLayoutProvider.overrideWithValue(cached),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('build', () {
    test('oturum yok → sabit varsayılana değil, cache\'teki yerleşime döner',
        () async {
      const cached = HomeLayout(
        quick: [RecordType.growth, RecordType.bath],
        lastActivity: [RecordType.medication],
      );
      final c = makeContainer(loggedIn: false, cached: cached);

      final layout = await settle(c);

      expect(layout.quick, cached.quick);
      expect(layout.lastActivity, cached.lastActivity);
      verifyNever(() => auth.settings());
    });

    test('sunucudan başarıyla yüklenince o değeri döner ve cache\'i günceller',
        () async {
      when(() => auth.settings()).thenAnswer((_) async => {
            'quick_actions': ['feed', 'diaper'],
            'home_cards': ['growth'],
          });
      final c = makeContainer(loggedIn: true);

      final layout = await settle(c);
      await Future<void>.delayed(Duration.zero); // unawaited cache yazımı otursun

      expect(layout.quick, [RecordType.feed, RecordType.diaper]);
      expect(layout.lastActivity, [RecordType.growth]);
      expect(await pref('home_layout_quick'), '["feed","diaper"]');
      expect(await pref('home_layout_last_activity'), '["growth"]');
    });

    test('sunucu hatası → sabit varsayılana değil, cache\'teki yerleşime düşer',
        () async {
      const cached = HomeLayout(
        quick: [RecordType.medication],
        lastActivity: [RecordType.bath],
      );
      when(() => auth.settings()).thenThrow(Exception('offline'));
      final c = makeContainer(loggedIn: true, cached: cached);

      final layout = await settle(c);

      expect(layout.quick, cached.quick);
      expect(layout.lastActivity, cached.lastActivity);
    });
  });

  group('setQuick / setLastActivity', () {
    test('yükleme bitmeden çağrılırsa cache tabanlı state\'ten türetir', () async {
      const cached = HomeLayout(
        quick: [RecordType.growth],
        lastActivity: [RecordType.bath],
      );
      final settingsCompleter = Completer<Map<String, dynamic>>();
      when(() => auth.settings()).thenAnswer((_) => settingsCompleter.future);
      when(() => auth.updateSettings(any())).thenAnswer((_) async {});
      final c = makeContainer(loggedIn: true, cached: cached);
      final ctrl = c.read(homeLayoutControllerProvider.notifier);

      await ctrl.setQuick([RecordType.feed]);

      final state = c.read(homeLayoutControllerProvider).value!;
      expect(state.quick, [RecordType.feed]);
      expect(state.lastActivity, cached.lastActivity); // korunur
      settingsCompleter.complete({}); // testi temiz bitir
    });

    test('sunucuya kaydeder + cache\'e yazar', () async {
      when(() => auth.settings()).thenAnswer((_) async => {});
      when(() => auth.updateSettings(any())).thenAnswer((_) async {});
      final c = makeContainer(loggedIn: true);
      await settle(c);
      final ctrl = c.read(homeLayoutControllerProvider.notifier);

      await ctrl.setQuick([RecordType.bath, RecordType.growth]);
      await Future<void>.delayed(Duration.zero);

      verify(() => auth
          .updateSettings({'quick_actions': ['bath', 'growth']})).called(1);
      expect(await pref('home_layout_quick'), '["bath","growth"]');
    });

    test('sunucu hatası sessizce yutulur, yerel seçim korunur', () async {
      when(() => auth.settings()).thenAnswer((_) async => {});
      when(() => auth.updateSettings(any())).thenThrow(Exception('offline'));
      final c = makeContainer(loggedIn: true);
      await settle(c);
      final ctrl = c.read(homeLayoutControllerProvider.notifier);

      await ctrl.setLastActivity([RecordType.medication]);

      expect(c.read(homeLayoutControllerProvider).value!.lastActivity,
          [RecordType.medication]);
      expect(await pref('home_layout_last_activity'), '["medication"]');
    });
  });
}
