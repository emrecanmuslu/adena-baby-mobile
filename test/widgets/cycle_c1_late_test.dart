import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/features/cycle/cycle_guidance.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME C1 (karar S8): gecikme dili "Beklenen tarihten {n} gün geçti";
/// ≥7 gün gebelik testi önerisi; uzun süre adet görmeme kartı: düzenli
/// döngüde ≥90 gün, kayıptan +8 hafta, emzirmeyen lohusada doğumdan +12 hafta;
/// emziren lohusada GÖSTERİLMEZ.
void main() {
  const card = 'Uzun süredir adet görmedin — hekimine danışmanı öneririz';
  final today = DateTime(2026, 10, 11);
  DateTime d(int off) => DateTime(2026, 10, 11 + off);
  List<CycleEntry> runs(List<int> starts) => [
        for (final s in starts)
          for (var k = 0; k < 5; k++)
            CycleEntry(id: 'e$s$k', date: d(s + k), flow: FlowLevel.medium),
      ];
  bool warn(CycleSettings s, List<CycleEntry> e) =>
      longAmenorrheaWarning(s, computeStatus(s, e, today: today), today: today);

  group('longAmenorrheaWarning', () {
    test('düzenli döngü, son adetten 95 gün → kart', () {
      final s = CycleSettings(firstPeriodDate: d(-151));
      expect(warn(s, runs([-151, -123, -95])), isTrue);
    });
    test('düzenli döngü, son adetten 60 gün → kart yok', () {
      final s = CycleSettings(firstPeriodDate: d(-116));
      expect(warn(s, runs([-116, -88, -60])), isFalse);
    });
    test('kayıptan +8 hafta, adet yok → kart; +3 hafta → yok', () {
      expect(
          warn(CycleSettings(
              lastLossDate: d(-57),
              lifecycleMode: CycleLifecycleMode.loss,
              predictionsHidden: true), const []),
          isTrue);
      expect(
          warn(CycleSettings(
              lastLossDate: d(-21),
              lifecycleMode: CycleLifecycleMode.loss,
              predictionsHidden: true), const []),
          isFalse);
    });
    test('emzirmeyen lohusa doğumdan +12 hafta → kart; emziren → yok', () {
      CycleSettings pp(Breastfeeding bf) => CycleSettings(
          birthDate: d(-90),
          breastfeeding: bf,
          lifecycleMode: CycleLifecycleMode.postpartum,
          predictionsHidden: true);
      expect(warn(pp(Breastfeeding.none), const []), isTrue);
      expect(warn(pp(Breastfeeding.exclusive), const []), isFalse);
      expect(warn(pp(Breastfeeding.mixed), const []), isFalse);
    });
    test('emziren lohusa aktif takipte 120 gün → yine gösterilmez', () {
      final s = CycleSettings(
          birthDate: d(-300),
          breastfeeding: Breastfeeding.exclusive,
          firstPeriodDate: d(-176));
      expect(warn(s, runs([-176, -148, -120])), isFalse);
    });
  });

  CycleSettings tracking(int anchor) =>
      CycleSettings(firstPeriodDate: dayOffset(anchor), breastfeeding: Breastfeeding.none);

  testWidgets('1 gün gecikme: "Beklenen tarihten 1 gün geçti", "gecikti" yok',
      (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: tracking(-113), entries: periodEntries([-113, -85, -57, -29]));
    expect(textHas('Beklenen tarihten 1 gün geçti'), findsWidgets);
    expect(textHas('gecikti'), findsNothing);
    expect(textHas('Gebelik testi yapmanı öneririz'), findsNothing);
  });

  testWidgets('8 gün gecikme: gebelik testi önerisi', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: tracking(-120), entries: periodEntries([-120, -92, -64, -36]));
    expect(textHas('Beklenen tarihten 8 gün geçti'), findsWidgets);
    expect(textHas('Gebelik testi yapmanı öneririz; negatifse birkaç gün sonra '
        'tekrarlayabilirsin.'), findsOneWidget);
  });

  testWidgets('bekleme · emzirmeyen lohusa 13. hafta → hekim kartı', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
            birthDate: dayOffset(-91),
            breastfeeding: Breastfeeding.none,
            lifecycleMode: CycleLifecycleMode.postpartum,
            predictionsHidden: true));
    expect(textHas(card), findsOneWidget);
  });

  testWidgets('kayıp modu +9 hafta → hekim kartı', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
            lastLossDate: dayOffset(-63),
            breastfeeding: Breastfeeding.none,
            lifecycleMode: CycleLifecycleMode.loss,
            predictionsHidden: true));
    expect(textHas(card), findsOneWidget);
  });
}
