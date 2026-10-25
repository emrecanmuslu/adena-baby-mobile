import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/features/onboarding/onboarding_draft.dart';

/// Yarım kalan kurulum taslağı — uygulama kapanınca kullanıcı kaldığı forma,
/// girdikleriyle döner; kurulum bitince / bilerek geri dönünce silinir.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('taslak yokken null', () async {
    expect(await OnboardingDraft.read(), isNull);
  });

  test('hedef seçilince rota kaydedilir, alanlar sonra eklenir', () async {
    await OnboardingDraft.start('/onboarding/baby/born');
    await OnboardingDraft.saveFields('/onboarding/baby/born',
        {'name': 'Defne', 'date': OnboardingDraft.day(DateTime(2026, 10, 5))});

    final d = await OnboardingDraft.read();
    expect(d!.route, '/onboarding/baby/born');
    expect(d.fields['name'], 'Defne');
    expect(OnboardingDraft.parseDay(d.fields['date']), DateTime(2026, 10, 5));
  });

  test('başka daldaki form taslağı ezmez', () async {
    await OnboardingDraft.start('/onboarding/cycle/ttc');
    await OnboardingDraft.saveFields('/onboarding/baby/born', {'name': 'X'});
    final d = await OnboardingDraft.read();
    expect(d!.route, '/onboarding/cycle/ttc');
    expect(d.fields, isEmpty);
  });

  test('clear sonrası null (kurulum bitti / bilerek geri)', () async {
    await OnboardingDraft.start('/onboarding/baby/expecting');
    await OnboardingDraft.clear();
    expect(await OnboardingDraft.read(), isNull);
  });

  test('onboarding dışı / bozuk değer yok sayılır', () async {
    SharedPreferences.setMockInitialValues(
        {'onboarding_draft_v1': '{"route":"/home","fields":{}}'});
    expect(await OnboardingDraft.read(), isNull);
    SharedPreferences.setMockInitialValues({'onboarding_draft_v1': 'bozuk'});
    expect(await OnboardingDraft.read(), isNull);
  });
}
