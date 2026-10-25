import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/features/cycle/cycle_guidance.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME C2 (karar S10): süren adet ≥9 gün, ortalama adet süresi > 8
/// gün ya da ardışık ≥7 gün "yoğun" akış → "Adetin 8 günden uzun sürüyor —
/// hekimine danışmanı öneririz".
void main() {
  const note = 'Âdetin 8 günden uzun sürüyor — hekimine danışmanı öneririz';
  final today = DateTime(2026, 10, 11);
  DateTime d(int off) => DateTime(2026, 10, 11 + off);
  List<CycleEntry> runs(List<int> starts,
          {int len = 5, Map<int, int>? lenFor, FlowLevel flow = FlowLevel.medium}) =>
      [
        for (final s in starts)
          for (var k = 0; k < (lenFor?[s] ?? len); k++)
            CycleEntry(id: 'e$s$k', date: d(s + k), flow: flow),
      ];
  bool warn(CycleSettings s, List<CycleEntry> e) =>
      longPeriodWarning(e, computeStatus(s, e, today: today));

  test('G1: son âdet 11 gün (süren) → uyarı', () {
    final s = CycleSettings(firstPeriodDate: d(-95));
    expect(warn(s, runs([-95, -67, -39, -11], lenFor: {-11: 11})), isTrue);
  });
  test('G2: her âdet 10 gün (ortalama > 8) → uyarı', () {
    final s = CycleSettings(firstPeriodDate: d(-104));
    expect(warn(s, runs([-104, -76, -48, -20], len: 10)), isTrue);
  });
  test('ardışık 7 gün yoğun akış → uyarı', () {
    final s = CycleSettings(firstPeriodDate: d(-104));
    expect(warn(s, runs([-104, -76, -48, -20], len: 7, flow: FlowLevel.heavy)), isTrue);
  });
  test('normal 5 günlük âdet → uyarı yok; 8 gün → yok (sınır)', () {
    final s = CycleSettings(firstPeriodDate: d(-104));
    expect(warn(s, runs([-104, -76, -48, -20])), isFalse);
    expect(warn(s, runs([-104, -76, -48, -20], len: 8)), isFalse);
  });

  testWidgets('bugün ekranı: 11 günlük âdette uyarı notu', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
            firstPeriodDate: dayOffset(-95), breastfeeding: Breastfeeding.none),
        entries: periodEntries([-95, -67, -39, -11], lenFor: {-11: 11}));
    expect(textHas(note), findsOneWidget);
  });
}
