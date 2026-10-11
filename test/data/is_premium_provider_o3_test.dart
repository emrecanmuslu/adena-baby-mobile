import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/models/subscription.dart';
import 'package:adena_baby/models/user.dart';

class _MockSubRepo extends Mock implements SubscriptionRepository {}

class _LoggedIn extends AuthController {
  @override
  Future<User?> build() async => const User(id: 'u1', email: 'a@b.c', name: 'A');
}

/// O3 — `isPremiumProvider`: canlı abonelik bir kez premium geldiyse, sonraki
/// GET hatasında (çevrimdışı) açılıştaki SABİT cache'e değil SON BİLİNEN
/// duruma düşer (para ödemiş kullanıcı free görünmesin).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('premium yanıt → GET hatası → premium kalır (son bilinen durum)', () async {
    final repo = _MockSubRepo();
    var calls = 0;
    when(() => repo.get()).thenAnswer((_) async {
      calls++;
      if (calls == 1) return const Subscription(tier: 'premium', isPremium: true);
      throw Exception('offline');
    });
    final c = ProviderContainer(overrides: [
      subscriptionRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(_LoggedIn.new),
    ]);
    addTearDown(c.dispose);
    // Riverpod 3: `.future` dinleyicisiz kalır → canlı tut ve oturmasını bekle.
    c.listen(subscriptionProvider, (_, _) {});
    Future<void> settle() async {
      for (var i = 0; i < 50 && c.read(subscriptionProvider).isLoading; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    await c.read(authControllerProvider.future);
    await settle();
    expect(c.read(isPremiumProvider), isTrue);

    c.invalidate(subscriptionProvider);
    await settle();
    expect(c.read(subscriptionProvider).hasError, isTrue);
    expect(c.read(isPremiumProvider), isTrue,
        reason: 'açılış cache\'i false olsa da son bilinen canlı durum premium');
  });

  test('free yanıt son bilinen durumu false yapar', () async {
    final repo = _MockSubRepo();
    when(() => repo.get()).thenAnswer((_) async => const Subscription(tier: 'free'));
    final c = ProviderContainer(overrides: [
      subscriptionRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(_LoggedIn.new),
      cachedPremiumProvider.overrideWith(() => LastKnownPremium(true)),
    ]);
    addTearDown(c.dispose);
    c.listen(subscriptionProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    expect(c.read(isPremiumProvider), isTrue, reason: 'canlı gelene dek cache');
    for (var i = 0; i < 50 && c.read(subscriptionProvider).isLoading; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.read(isPremiumProvider), isFalse);
    expect(c.read(cachedPremiumProvider), isFalse);
  });
}
