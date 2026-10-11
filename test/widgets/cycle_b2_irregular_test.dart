import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/features/cycle/cycle_stats_screen.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME B2 (karar S6): son döngülerde en kısa–en uzun farkı > 9 gün →
/// düzensiz: düşük güven + tek tarih yerine aralık. İstatistik pili koşullu.
void main() {
  final today = DateTime(2026, 10, 11);
  DateTime d(int off) => DateTime(2026, 10, 11 + off);
  List<CycleEntry> runs(List<int> starts) => [
        for (final s in starts)
          for (var k = 0; k < 5; k++)
            CycleEntry(id: 'e$s$k', date: d(s + k), flow: FlowLevel.medium),
      ];

  test('motor: 26/33/29/40 düzensiz → aralık son başlangıç + min..max', () {
    final s = computeStatus(CycleSettings(firstPeriodDate: d(-148)),
        runs([-148, -122, -89, -60, -20]), today: today);
    expect(s.irregular, isTrue);
    expect(s.lowConfidence, isTrue);
    expect(s.nextPeriodEarliest, d(-20 + 26));
    expect(s.nextPeriodLatest, d(-20 + 40));
  });

  test('motor: düzenli 28 → düzensiz değil, aralık yok', () {
    final s = computeStatus(CycleSettings(firstPeriodDate: d(-104)),
        runs([-104, -76, -48, -20]), today: today);
    expect(s.irregular, isFalse);
    expect(s.lowConfidence, isFalse);
    expect(s.nextPeriodEarliest, isNull);
  });

  test('motor: fark tam 9 gün → düzenli sayılır (eşik > 9)', () {
    final s = computeStatus(CycleSettings(firstPeriodDate: d(-111)),
        runs([-111, -85, -50, -20]), today: today); // 26, 35, 30
    expect(s.irregular, isFalse);
  });

  final irregular = CycleSettings(
      firstPeriodDate: dayOffset(-148), breastfeeding: Breastfeeding.none);
  final irregularEntries = periodEntries([-148, -122, -89, -60, -20]);

  testWidgets('bugün: düzensizde "Sonraki adet tahmini" aralığı', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: irregular, entries: irregularEntries);
    expect(textHas('SONRAKİ ADET TAHMİNİ'), findsOneWidget);
    expect(textHas('–'), findsWidgets);
  });

  testWidgets('istatistik: düzensizde "Değişken seyir — hekimine sorabilirsin"',
      (t) async {
    await pumpCycleScreen(t, const CycleStatsScreen(),
        settings: irregular, entries: irregularEntries);
    expect(textHas('Değişken seyir — hekimine sorabilirsin'), findsOneWidget);
    expect(textHas('Postpartum normal'), findsNothing);
  });

  testWidgets('istatistik: doğumdan 2 yıl sonra "Postpartum normal" yok', (t) async {
    await pumpCycleScreen(t, const CycleStatsScreen(),
        settings: CycleSettings(
            firstPeriodDate: dayOffset(-104),
            birthDate: dayOffset(-730),
            breastfeeding: Breastfeeding.none),
        entries: periodEntries([-104, -76, -48, -20]));
    expect(textHas('Postpartum normal'), findsNothing);
  });
}
