import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_guidance.dart';
import 'package:adena_baby/features/cycle/cycle_setup_screen.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME A2 + A5 + C8 + D3 — emzirme/LAM metinleri:
/// LAM üç koşulla ve öneri olmadan; 6 ay/karışık/adet dönmesi → "artık
/// korunma sağlamaz"; emzirmeyene LAM yerine erken ovülasyon metni; "tamamen
/// normal" kesinlik dili yok; emzirme sorusu zorunlu (varsayılan yok).
void main() {
  final today = DateTime(2026, 10, 11);
  CycleSettings pp(Breastfeeding? bf, int birthDaysAgo, {DateTime? period}) =>
      CycleSettings(
        birthDate: DateTime(2026, 10, 11 - birthDaysAgo),
        breastfeeding: bf,
        firstPeriodDate: period,
      );

  group('lamState', () {
    test('tam emziren, 3. ay, adet yok → koşullar', () {
      expect(lamState(pp(Breastfeeding.exclusive, 90), today: today),
          LamState.conditions);
    });
    test('tam emziren ama 6 ay geçti → artık korumaz', () {
      expect(lamState(pp(Breastfeeding.exclusive, 200), today: today),
          LamState.notProtective);
    });
    test('karışık → artık korumaz', () {
      expect(lamState(pp(Breastfeeding.mixed, 40), today: today),
          LamState.notProtective);
    });
    test('adet döndü → artık korumaz', () {
      expect(
          lamState(pp(Breastfeeding.exclusive, 60, period: DateTime(2026, 10, 1)),
              today: today),
          LamState.notProtective);
    });
    test('emzirmiyor / bilinmiyor / doğum yok → gizli', () {
      expect(lamState(pp(Breastfeeding.none, 40), today: today), LamState.hidden);
      expect(lamState(pp(null, 40), today: today), LamState.hidden);
      expect(lamState(const CycleSettings(breastfeeding: Breastfeeding.exclusive),
              today: today),
          LamState.hidden);
    });
  });

  CycleSettings waitingPp(Breastfeeding? bf, int birthDaysAgo) => CycleSettings(
        birthDate: dayOffset(-birthDaysAgo),
        breastfeeding: bf,
        lifecycleMode: CycleLifecycleMode.postpartum,
        predictionsHidden: true,
      );

  testWidgets('bekleme · emzirmiyor (10. hf): erken ovülasyon metni, LAM yok',
      (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: waitingPp(Breastfeeding.none, 70));
    expect(textHas('Emzirmiyorsan adetin genellikle doğumdan sonraki 6–8 hafta'),
        findsOneWidget);
    expect(textHas('3–4. haftada'), findsOneWidget);
    expect(textHas('LAM'), findsNothing);
    expect(textHas('%2'), findsNothing);
    expect(textHas('tamamen normal'), findsNothing);
  });

  testWidgets('bekleme · tam emziren (3. ay): üç koşul + ilk adetten önce gebelik',
      (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: waitingPp(Breastfeeding.exclusive, 90));
    expect(textHas('üç koşulun hepsi'), findsOneWidget);
    expect(textHas('ilk 6 ay'), findsWidgets);
    expect(textHas('İlk adetini görmeden de gebe kalabilirsin'), findsOneWidget);
    expect(textHas('sık görülür'), findsOneWidget);
    expect(textHas('tamamen normal'), findsNothing);
    expect(textHas('%2'), findsNothing);
  });

  testWidgets('bekleme · tam emziren (7. ay): artık korumaz kartı', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: waitingPp(Breastfeeding.exclusive, 215));
    expect(textHas('Emzirme artık tek başına korunma sağlamaz'), findsOneWidget);
    expect(textHas('üç koşulun hepsi'), findsNothing);
  });

  testWidgets('loşia · emzirmiyor: LAM notu yok, erken ovülasyon metni var',
      (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: waitingPp(Breastfeeding.none, 10));
    expect(textHas('LAM'), findsNothing);
    expect(textHas('3–4. haftada'), findsOneWidget);
  });

  testWidgets('kurulum: emzirme seçimi zorunlu, "LAM geçerli olabilir" yok',
      (t) async {
    await pumpCycleScreen(t,
        CycleSetupView(
            initial: const CycleSettings(),
            babyBirthDate: DateTime(2026, 8, 1),
            onDone: () {}),
        settings: const CycleSettings());
    await t.tap(find.text('Devam'));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Emziriyor musun?'), findsOneWidget);
    expect(textHas('LAM geçerli olabilir'), findsNothing);
    expect(textHas('Adet daha geç dönebilir'), findsOneWidget);
    // Seçim yapmadan Devam → aynı adımda kalınır.
    await t.tap(find.text('Devam'));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Emziriyor musun?'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });
}
