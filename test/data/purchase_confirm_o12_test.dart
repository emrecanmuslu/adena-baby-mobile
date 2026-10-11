import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/models/subscription.dart';

class _MockSubRepo extends Mock implements SubscriptionRepository {}

/// O12 — satın alma RevenueCat'te doğrulandıysa backend `refresh` hatası
/// premium'u ENGELLEMEZ: son bilinen durum premium, kalıcı önbellek yazılır,
/// çağıran hata görmez (ekranlar "Premium etkinleştirildi" gösterir).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh fırlatsa da applyConfirmed tamamlanır; cachedPremium=true; önbellek 1',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = _MockSubRepo();
    when(() => repo.refresh()).thenThrow(Exception('500'));
    final c = ProviderContainer(overrides: [
      subscriptionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);

    await c.read(purchaseConfirmProvider).applyConfirmed();

    expect(c.read(cachedPremiumProvider), isTrue);
    expect((await SharedPreferences.getInstance()).getString('sub_is_premium'), '1');
    verify(() => repo.refresh()).called(1);
  });

  test('refresh başarılıysa yine premium (regresyon)', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = _MockSubRepo();
    when(() => repo.refresh()).thenAnswer((_) async => const Subscription(tier: 'premium', isPremium: true));
    final c = ProviderContainer(overrides: [
      subscriptionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    await c.read(purchaseConfirmProvider).applyConfirmed();
    expect(c.read(cachedPremiumProvider), isTrue);
  });
}
