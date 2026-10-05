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

  group('doz rolleri (yalnız sıradaki + son verilen dokunulabilir)', () {
    final plan = _plan(times: ['08:00', '14:00', '20:00']);

    test('hiç verilmemiş: ilk doz next, gerisi lock', () {
      final doses = todaysMedicationDoses([plan], [], now: DateTime(2026, 1, 1, 15));
      expect(doses.map((d) => d.role), [
        MedicationDoseRole.next,
        MedicationDoseRole.lock,
        MedicationDoseRole.lock,
      ]);
      // 14:00 da geçmiş ama sırası gelmedi → overdue görünür, dokunulamaz.
      expect(doses[1].status, MedicationDoseStatus.overdue);
    });

    test('biri verilmiş: o undo, sonraki next, sonuncu lock', () {
      final rec = _rec('D Vitamini', DateTime(2026, 1, 1, 8, 5));
      final doses = todaysMedicationDoses([plan], [rec], now: DateTime(2026, 1, 1, 9));
      expect(doses.map((d) => d.role), [
        MedicationDoseRole.undo,
        MedicationDoseRole.next,
        MedicationDoseRole.lock,
      ]);
    });

    test('hepsi verilmiş: yalnız sonuncu undo, next yok', () {
      final recs = [
        for (final h in [8, 14, 20]) _rec('D Vitamini', DateTime(2026, 1, 1, h, 1)),
      ];
      final doses = todaysMedicationDoses([plan], recs, now: DateTime(2026, 1, 1, 21));
      expect(doses.map((d) => d.role), [
        MedicationDoseRole.lock,
        MedicationDoseRole.lock,
        MedicationDoseRole.undo,
      ]);
    });

    test('plan saatinden fazla kayıt (plan dışı ek doz) taşmaz', () {
      final one = _plan();
      final recs = [
        _rec('D Vitamini', DateTime(2026, 1, 1, 9, 1)),
        _rec('D Vitamini', DateTime(2026, 1, 1, 11, 0)),
      ];
      final doses = todaysMedicationDoses([one], recs, now: DateTime(2026, 1, 1, 12));
      expect(doses.single.status, MedicationDoseStatus.given);
      expect(doses.single.role, MedicationDoseRole.undo);
      expect(doses.single.record, recs.first);
    });
  });

  group('medicationDay', () {
    final d = _plan(id: 1, name: 'D vitamini', times: ['09:00']);
    final fe = _plan(id: 2, name: 'Demir', times: ['08:00', '20:00']);
    final pr = _plan(id: 3, name: 'Probiyotik', times: ['12:00']);

    test('sayılar + sıralama: saati geçen → bekleyen → tamamlanan', () {
      final recs = [
        _rec('D vitamini', DateTime(2026, 1, 1, 9, 12)),
        _rec('Demir', DateTime(2026, 1, 1, 8, 5)),
      ];
      final day = medicationDay([d, fe, pr], recs, now: DateTime(2026, 1, 1, 14, 20));
      expect(day.total, 4);
      expect(day.done, 2);
      expect(day.overdue, 1);
      expect(day.allDone, isFalse);
      expect(day.rows.map((r) => r.plan.name), ['Probiyotik', 'Demir', 'D vitamini']);
      expect(day.timeline.map((x) => x.time), ['08:00', '09:00', '12:00', '20:00']);
      expect(day.firstTime, '08:00');
      expect(day.nextUpcoming, '20:00');
    });

    test('promote: saati geçmiş doz varsa', () {
      final day = medicationDay([pr], [], now: DateTime(2026, 1, 1, 12, 30));
      expect(day.promote, isTrue);
    });

    test('promote: sıradaki doza ≤60 dk kaldıysa; daha uzaksa değil', () {
      expect(medicationDay([pr], [], now: DateTime(2026, 1, 1, 11, 0)).promote, isTrue);
      expect(medicationDay([pr], [], now: DateTime(2026, 1, 1, 10, 59)).promote, isFalse);
    });

    test('hepsi verildi → allDone, promote yok', () {
      final recs = [_rec('Probiyotik', DateTime(2026, 1, 1, 12, 4))];
      final day = medicationDay([pr], recs, now: DateTime(2026, 1, 1, 13));
      expect(day.allDone, isTrue);
      expect(day.promote, isFalse);
      expect(day.rows.single.complete, isTrue);
    });

    test('atlanan doz: verilmiş sayılmaz ama beklemez (saati geçti/promote yok)', () {
      final skip = Record(
        id: 'skip',
        baby: 'b1',
        type: RecordType.medication,
        ts: DateTime(2026, 1, 1, 21, 30),
        data: {'name': 'Demir', 'given': false, 'skipped': true},
      );
      final recs = [_rec('Demir', DateTime(2026, 1, 1, 8, 5)), skip];
      final day = medicationDay([fe], recs, now: DateTime(2026, 1, 1, 22));
      final doses = day.rows.single.doses;
      expect(doses.map((x) => x.status),
          [MedicationDoseStatus.given, MedicationDoseStatus.skipped]);
      // Son işaretlenen (atlanan) geri alınabilir; önceki kilitli.
      expect(doses.map((x) => x.role), [MedicationDoseRole.lock, MedicationDoseRole.undo]);
      expect(day.done, 1);
      expect(day.total, 2);
      expect(day.overdue, 0);
      expect(day.allDone, isTrue);
      expect(day.promote, isFalse);
      expect(day.rows.single.lastResolved!.isSkipped, isTrue);
    });

    test('ilk doz atlanınca ikinci doz sıradaki olur', () {
      final skip = Record(
        id: 'skip',
        baby: 'b1',
        type: RecordType.medication,
        ts: DateTime(2026, 1, 1, 10),
        data: {'name': 'Demir', 'given': false, 'skipped': true},
      );
      final day = medicationDay([fe], [skip], now: DateTime(2026, 1, 1, 11));
      final doses = day.rows.single.doses;
      expect(doses[0].status, MedicationDoseStatus.skipped);
      expect(doses[1].status, MedicationDoseStatus.upcoming);
      expect(doses[1].role, MedicationDoseRole.next);
      expect(day.allDone, isFalse);
    });

    test('yalnız duraklatılmış plan: aktif satır yok ama planCount sayar', () {
      final day = medicationDay([pr.copyWith(active: false)], [],
          now: DateTime(2026, 1, 1, 13));
      expect(day.hasActive, isFalse);
      expect(day.planCount, 1);
      expect(day.total, 0);
      expect(day.allDone, isFalse);
      expect(day.promote, isFalse);
    });
  });
}
