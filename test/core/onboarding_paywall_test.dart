import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/onboarding_paywall.dart';

/// Premium Karşılama Ekranı'nın **tek-kez** ve **doğru zamanda** gösterimi.
/// Ürün kararı: kurulumun hemen ardından değil; ilk kayıttan sonra ya da
/// (kayıt yoksa) ertesi gün. Kullanıcı kapatırsa bir daha ASLA açılmaz.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final day1 = DateTime(2026, 10, 25, 10);
  final day1Late = DateTime(2026, 10, 25, 23, 50);
  final day2 = DateTime(2026, 10, 26, 8);

  test('sıraya alınmadan consume false döner (bebek kurulmadıysa açılmaz)',
      () async {
    expect(await OnboardingPaywall.consume(hasRecord: true, now: day1), isFalse);
  });

  test('kurulum günü kayıt yoksa AÇILMAZ (kurulumun hemen ardından değil)',
      () async {
    await OnboardingPaywall.markPending(now: day1);
    expect(await OnboardingPaywall.consume(hasRecord: false, now: day1), isFalse);
    expect(await OnboardingPaywall.consume(hasRecord: false, now: day1Late),
        isFalse);
  });

  test('ilk kayıttan sonra aynı gün açılır, bir kez', () async {
    await OnboardingPaywall.markPending(now: day1);
    expect(await OnboardingPaywall.consume(hasRecord: true, now: day1), isTrue);
    expect(await OnboardingPaywall.consume(hasRecord: true, now: day1), isFalse,
        reason: 'ikinci kez asla açılmamalı');
  });

  test('kayıt yapılmasa da ertesi günün ilk açılışında açılır', () async {
    await OnboardingPaywall.markPending(now: day1);
    expect(await OnboardingPaywall.consume(hasRecord: false, now: day2), isTrue);
  });

  test('eski sürümden kalan tarihsiz bekleyen bayrak hemen tüketilir', () async {
    SharedPreferences.setMockInitialValues({'onboarding_paywall_pending': true});
    expect(await OnboardingPaywall.consume(hasRecord: false, now: day1), isTrue);
  });

  test('gösterildikten sonra markPending yeniden sıraya ALMAZ', () async {
    await OnboardingPaywall.markPending(now: day1);
    await OnboardingPaywall.consume(hasRecord: true, now: day1);

    // İkinci bebek eklenince kurulum yine markPending çağırabilir —
    // ömür boyu tek gösterim kuralı bunu yutmalı.
    await OnboardingPaywall.markPending(now: day2);
    expect(await OnboardingPaywall.consume(hasRecord: true, now: day2), isFalse);
  });

  test('markShown bekleyen gösterimi iptal eder (premium kullanıcı)', () async {
    await OnboardingPaywall.markPending(now: day1);
    await OnboardingPaywall.markShown();

    expect(await OnboardingPaywall.consume(hasRecord: true, now: day2), isFalse,
        reason: 'premium kullanıcıya hiç gösterilmemeli');
  });

  test('bayraklar kalıcı: yeni "oturum" (yeni okuma) aynı sonucu verir',
      () async {
    await OnboardingPaywall.markPending(now: day1);
    expect(await OnboardingPaywall.consume(hasRecord: true, now: day1), isTrue);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(await OnboardingPaywall.consume(hasRecord: true, now: day2), isFalse);
  });

  test('kurulum anı ilk kez yazılır, sonra ezilmez', () async {
    expect(await OnboardingPaywall.onboardedAt(), isNull);
    await OnboardingPaywall.markOnboarded(now: day1);
    await OnboardingPaywall.markOnboarded(now: day2);
    expect(await OnboardingPaywall.onboardedAt(), day1);
  });
}
