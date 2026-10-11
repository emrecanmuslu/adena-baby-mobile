import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/models/cycle.dart';

/// ADET-INCELEME B1 (karar S7): döngü uzunluğu ortalama yerine MEDYAN; diğer
/// döngülerin medyanının 1,7 katını AŞAN ve 45 günden uzun döngü ("unutulmuş
/// kayıt") ortalamaya girmez, düşük güven + kullanıcıya sorulur; kullanıcı
/// "döngüm uzundu" derse (confirmedLongStarts) dahil edilir.
void main() {
  final today = DateTime(2026, 10, 11);
  DateTime d(int off) => DateTime(2026, 10, 11 + off);
  List<CycleEntry> periods(List<int> starts) => [
        for (final s in starts)
          for (var k = 0; k < 5; k++)
            CycleEntry(id: 'e$s$k', date: d(s + k), flow: FlowLevel.medium),
      ];
  CycleStatus run(List<int> starts, {Set<DateTime> confirmed = const {}}) =>
      computeStatus(CycleSettings(firstPeriodDate: d(starts.first)), periods(starts),
          today: today, confirmedLongStarts: confirmed);

  test('F1 unutulan ay (28, 56): 56 dışlanır, medyan 28, düşük güven, soru adayı', () {
    final s = run([-104, -76, -20]);
    expect(s.avgCycleLength, 28);
    expect(s.nextPeriod, d(8));
    expect(s.lowConfidence, isTrue);
    expect(s.suspectedMissedStarts, [d(-76)]);
  });

  test('F1 + kullanıcı "döngüm uzundu" → 56 dahil (medyan 42), soru yok', () {
    final s = run([-104, -76, -20], confirmed: {d(-76)});
    expect(s.avgCycleLength, 42);
    expect(s.suspectedMissedStarts, isEmpty);
  });

  test('F2 (28×5 + 56) → medyan 28', () {
    final s = run([-216, -188, -160, -132, -104, -76, -20]);
    expect(s.avgCycleLength, 28);
    expect(s.suspectedMissedStarts, [d(-76)]);
    expect(s.phase, CyclePhase.luteal, reason: 'gün 21 = luteal (eskiden "Doğurganlık")');
  });

  test('F3 gerçek 28 gün, gün 29 → adet bugün bekleniyor (eskiden "Yumurtlama")', () {
    final s = run([-112, -84, -28]);
    expect(s.daysToNextPeriod, 0);
    expect(s.phase, isNot(CyclePhase.ovulation));
  });

  test('45 günü aşmayan uzun döngü dışlanmaz (24,24,24,42 → 24)', () {
    final s = run([-134, -110, -86, -62, -20]);
    expect(s.avgCycleLength, 24);
    expect(s.suspectedMissedStarts, isEmpty);
  });

  test('medyan: 26,33,29,40 → 31 (ortalama 32 değil)', () {
    final s = run([-148, -122, -89, -60, -20]);
    expect(s.avgCycleLength, 31);
  });
}
