import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

MedicationPlan _plan(
        {int id = 1, String name = 'D Vitamini', List<String> times = const ['09:00']}) =>
    MedicationPlan(
        id: id, name: name, dose: '1 damla', times: times, active: true, createdAt: DateTime(2026));

Record _rec(String name, DateTime ts) => Record(
      id: 'r$ts',
      baby: 'b1',
      type: RecordType.medication,
      ts: ts,
      data: {'name': name, 'given': true},
    );

void main() {
  group('todaysMedicationDoses', () {
    test('saat gelmeden ve kayıt yokken → upcoming', () {
      final now = DateTime(2026, 1, 1, 8, 0);
      final doses = todaysMedicationDoses([_plan()], [], now: now);
      expect(doses.single.status, MedicationDoseStatus.upcoming);
    });

    test('saat geçmiş ve kayıt yokken → overdue', () {
      final now = DateTime(2026, 1, 1, 10, 0);
      final doses = todaysMedicationDoses([_plan()], [], now: now);
      expect(doses.single.status, MedicationDoseStatus.overdue);
    });

    test('bugün eşleşen kayıt varsa → given (ad büyük/küçük harf duyarsız)', () {
      final now = DateTime(2026, 1, 1, 10, 0);
      final rec = _rec('d vitamini', DateTime(2026, 1, 1, 9, 5));
      final doses = todaysMedicationDoses([_plan()], [rec], now: now);
      expect(doses.single.status, MedicationDoseStatus.given);
      expect(doses.single.givenAt, rec.ts);
    });

    test('dünkü kayıt bugünü etkilemez (given sayılmaz)', () {
      final now = DateTime(2026, 1, 2, 10, 0);
      final rec = _rec('D Vitamini', DateTime(2026, 1, 1, 9, 5)); // dün
      final doses = todaysMedicationDoses([_plan()], [rec], now: now);
      expect(doses.single.status, MedicationDoseStatus.overdue);
    });

    test('günde 2 doz: ilk kayıt ilk dozu kapatır, ikinci doz hâlâ bekler', () {
      final plan = _plan(times: ['09:00', '21:00']);
      final now = DateTime(2026, 1, 1, 20, 0);
      final rec = _rec('D Vitamini', DateTime(2026, 1, 1, 9, 10));
      final doses = todaysMedicationDoses([plan], [rec], now: now);
      expect(doses.length, 2);
      expect(doses[0].status, MedicationDoseStatus.given);
      expect(doses[1].status, MedicationDoseStatus.upcoming); // 21:00 henüz gelmedi
    });

    test('pasif plan hiç doz üretmez', () {
      final plan = _plan().copyWith(active: false);
      final doses = todaysMedicationDoses([plan], [], now: DateTime(2026, 1, 1, 10, 0));
      expect(doses, isEmpty);
    });

    test('farklı ilaç adının kaydı bu planı etkilemez', () {
      final now = DateTime(2026, 1, 1, 10, 0);
      final rec = _rec('Demir', DateTime(2026, 1, 1, 9, 5));
      final doses = todaysMedicationDoses([_plan()], [rec], now: now);
      expect(doses.single.status, MedicationDoseStatus.overdue);
    });
  });
}
