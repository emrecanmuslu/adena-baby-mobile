import 'package:adena_baby/models/vaccine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseVaccineName', () {
    void expectParts(String name, String p, String s, String d) {
      final r = parseVaccineName(name);
      expect([r.primary, r.secondary, r.dose], [p, s, d], reason: name);
    }

    test('kısaltma + açık ad + doz → açık ad büyük', () {
      expectParts('KPA (Pnömokok, 1. doz)', 'Pnömokok', 'KPA', '1. doz');
      expectParts('DaBT-İPA-Hib-HepB (Altılı Karma, 2. doz)', 'Altılı Karma',
          'DaBT-İPA-Hib-HepB', '2. doz');
      expectParts('BCG (Verem)', 'Verem', 'BCG', '');
      expectParts('Td (Tetanoz-Difteri, Rapel)', 'Tetanoz-Difteri', 'Td', 'Rapel');
      expectParts('KKK (Kızamık-Kızamıkçık-Kabakulak, 1. doz)',
          'Kızamık-Kızamıkçık-Kabakulak', 'KKK', '1. doz');
    });

    test('kısaltma olmayan ad büyük kalır, (ücretli) atılır', () {
      expectParts('Hepatit B (1. doz)', 'Hepatit B', '', '1. doz');
      expectParts('Suçiçeği (Rapel)', 'Suçiçeği', '', 'Rapel');
      expectParts('Rotavirüs (2. doz) (ücretli)', 'Rotavirüs', '', '2. doz');
      expectParts('Rotavirüs (3. doz, markaya göre) (ücretli)', 'Rotavirüs',
          'markaya göre', '3. doz');
      expectParts('Meningokok ACWY (A, C, W, Y Serogrupları) (ücretli)',
          'Meningokok ACWY', 'A, C, W, Y Serogrupları', '');
    });

    test('diğer diller', () {
      expectParts('DTaP (Diphtheria, Tetanus, Pertussis, 1st dose)',
          'Diphtheria, Tetanus, Pertussis', 'DTaP', '1st dose');
      expectParts('DTaP (2nd dose)', 'DTaP', '', '2nd dose');
      expectParts('Influenza (annual, from 6 months)', 'Influenza',
          'annual, from 6 months', '');
      expectParts('肺炎球菌疫苗（PCV，第1剂）', '肺炎球菌疫苗', 'PCV', '第1剂');
      expectParts('Hib (الجرعة الرابعة المعززة)', 'Hib', '', 'الجرعة الرابعة المعززة');
    });

    test('parantezsiz ad olduğu gibi', () {
      expectParts('Polio', 'Polio', '', '');
    });
  });

  group('VaccineSchedule.build', () {
    final birth = DateTime(2026, 5, 4);
    final today = DateTime(2026, 10, 12);
    Vaccine v(String k, int m, {bool done = false, bool opt = false}) => Vaccine(
        key: k,
        name: k,
        months: m,
        dueDate: DateTime(birth.year, birth.month + m, birth.day),
        done: done,
        doneDate: done ? DateTime(2026, 7, 6) : null,
        optional: opt);

    final list = [
      v('hepb1', 0, done: true),
      v('kpa1', 2, done: true),
      v('rota1', 2, done: true, opt: true),
      v('menb1', 2, opt: true),
      v('hexa2', 4, done: true),
      v('kpa2', 4),
      v('hexa3', 6),
      v('opa1', 6),
      v('rota3', 6, opt: true),
      v('kkk1', 12),
    ];

    test('durumlar, sıradaki grup, bekleyenler, sayılar', () {
      final s = VaccineSchedule.build(list, today);
      expect(s.groups.map((g) => g.months), [0, 2, 4, 6, 12]);
      expect(s.groups.map((g) => g.status), [
        VaccineGroupStatus.done,
        VaccineGroupStatus.done, // isteğe bağlı eksik olsa da zorunlular tamam
        VaccineGroupStatus.late,
        VaccineGroupStatus.next,
        VaccineGroupStatus.future,
      ]);
      expect(s.nextGroup!.months, 6);
      expect(s.late.map((x) => x.key), ['kpa2']);
      expect(s.statusOf(list[3]), VaccineStatus.optional);
      expect(s.statusOf(list[6]), VaccineStatus.next);
      expect(s.statusOf(list[9]), VaccineStatus.future);
      expect(s.groups[1].optional.length, 2);
      expect((s.done, s.total), (4, 10));
      expect((s.mandatoryDone, s.mandatoryTotal), (3, 7));
    });

    test('hepsi yapıldıysa sıradaki yok', () {
      final s = VaccineSchedule.build(
          [v('a', 0, done: true), v('b', 2, done: true), v('c', 2, opt: true)], today);
      expect(s.nextGroup, isNull);
      expect(s.mandatoryDone, s.mandatoryTotal);
    });

    test('bugün tarihli aşı gecikmiş değil sıradaki', () {
      final s = VaccineSchedule.build([
        Vaccine(key: 'x', name: 'x', months: 5, dueDate: today, done: false),
      ], today.add(const Duration(hours: 15)));
      expect(s.statusOf(s.groups.first.mandatory.first), VaccineStatus.next);
    });
  });
}
