import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/leaps.dart';

/// Saf gelişim atağı hesapları (core/leaps.dart).
void main() {
  group('leapPhase', () {
    test('huzursuz penceresinden önce → future', () {
      expect(leapPhase(3, 8, 1), LeapPhase.future);
    });

    test('huzursuz penceresi içinde → fussy', () {
      // weekStart=8, fussyWeeksBefore=1 → fussyStart=7.
      expect(leapPhase(7, 8, 1), LeapPhase.fussy);
    });

    test('atak haftasında → peak', () {
      expect(leapPhase(8, 8, 1), LeapPhase.peak);
    });

    test('zirve + 1 hafta hâlâ peak (peakEnd = weekStart+1)', () {
      expect(leapPhase(9, 8, 1), LeapPhase.peak);
    });

    test('peakEnd sonrası → past', () {
      expect(leapPhase(10, 8, 1), LeapPhase.past);
    });

    test('kesirli fussyWeeksBefore doğru yuvarlanır', () {
      // weekStart=12, fussyWeeksBefore=1.5 → fussyStart=10.5 → 10 hâlâ future.
      expect(leapPhase(10, 12, 1.5), LeapPhase.future);
      expect(leapPhase(11, 12, 1.5), LeapPhase.fussy);
    });
  });

  group('leapReminderDate', () {
    test('huzursuz penceresinin başlangıç tarihini döner (09:00)', () {
      final anchor = DateTime(2026, 1, 1);
      // weekStart=8, fussyWeeksBefore=1 → fussyStartWeek=7 → 49 gün sonra.
      final at = leapReminderDate(anchor, 8, 1);
      expect(at, DateTime(2026, 2, 19, 9));
    });

    test('kesirli fussyWeeksBefore gün sayısına yuvarlanır', () {
      final anchor = DateTime(2026, 1, 1);
      // weekStart=12, fussyWeeksBefore=1.5 → 10.5 hafta = 73.5 gün → round=74.
      final at = leapReminderDate(anchor, 12, 1.5);
      final expected = anchor.add(const Duration(days: 74));
      expect(at, DateTime(expected.year, expected.month, expected.day, 9));
    });
  });
}
