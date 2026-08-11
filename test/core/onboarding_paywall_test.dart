import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/onboarding_paywall.dart';

/// Premium Karşılama Ekranı'nın **tek-kez** gösterim garantisi.
/// Ürün kararı: kullanıcı kapatırsa bir daha ASLA açılmaz — bu yüzden
/// tüketim (consume) idempotent olmalı ve kalıcı bayrağa yazmalı.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sıraya alınmadan consume false döner (bebek kurulmadıysa açılmaz)',
      () async {
    expect(await OnboardingPaywall.consume(), isFalse);
  });

  test('markPending sonrası ilk consume true, ikinci consume false', () async {
    await OnboardingPaywall.markPending();

    expect(await OnboardingPaywall.consume(), isTrue,
        reason: 'bebek kurulumu sonrası bir kez açılmalı');
    expect(await OnboardingPaywall.consume(), isFalse,
        reason: 'ikinci kez asla açılmamalı');
  });

  test('gösterildikten sonra markPending yeniden sıraya ALMAZ', () async {
    await OnboardingPaywall.markPending();
    await OnboardingPaywall.consume();

    // İkinci bebek eklenince kurulum ekranı yine markPending çağırır —
    // ömür boyu tek gösterim kuralı bunu yutmalı.
    await OnboardingPaywall.markPending();
    expect(await OnboardingPaywall.consume(), isFalse);
  });

  test('markShown bekleyen gösterimi iptal eder (premium kullanıcı)', () async {
    await OnboardingPaywall.markPending();
    await OnboardingPaywall.markShown();

    expect(await OnboardingPaywall.consume(), isFalse,
        reason: 'premium kullanıcıya hiç gösterilmemeli');
  });

  test('bayraklar kalıcı: yeni "oturum" (yeni okuma) aynı sonucu verir',
      () async {
    await OnboardingPaywall.markPending();
    expect(await OnboardingPaywall.consume(), isTrue);

    // Aynı prefs deposundan tekrar okunduğunda (uygulama yeniden açılmış gibi)
    // durum korunmalı — bayrak bellekte tutulmuyor, SharedPreferences'ta.
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(await OnboardingPaywall.consume(), isFalse);
  });
}
