import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

/// İlaç v2 (A2) — doz motoru: sıklık türleri, başlangıç/bitiş, duraklatma,
/// zamanlama çapası, kimlikle çözümleme, çift/çakışma, gece yarısı (M4),
/// yeniden adlandırma (M5), kimliksiz eski kayıt yakınlık eşlemesi, PRN.
MedicationPlan _p({
  int id = 1,
  String uuid = 'p1',
  String name = 'Demir',
  List<String> times = const ['08:00', '20:00'],
  MedFreq freq = MedFreq.daily,
  MedKind kind = MedKind.scheduled,
  int? intervalHours,
  int? everyNDays,
  List<int> weekdays = const [],
  DateTime? start,
  DateTime? end,
  bool active = true,
  List<MedPause> pauses = const [],
  DateTime? scheduleFrom,
  DateTime? createdAt,
  int? prnMin,
  int? prnMax,
}) =>
    MedicationPlan(
      id: id,
      uuid: uuid,
      name: name,
      dose: '1 ml',
      times: times,
      active: active,
      createdAt: createdAt ?? DateTime(2026, 10, 1),
      kind: kind,
      freq: freq,
      intervalHours: intervalHours,
      everyNDays: everyNDays,
      weekdays: weekdays,
      startDate: start ?? DateTime(2026, 10, 1),
      endDate: end,
      pauses: pauses,
      scheduleFrom: scheduleFrom,
      prnMinIntervalMin: prnMin,
      prnMaxPerDay: prnMax,
    );

int _n = 0;
Record _dose(String date, String? time,
        {String plan = 'p1',
        DateTime? ts,
        bool skipped = false,
        String? by,
        String kind = 'scheduled',
        String? reason}) =>
    Record(
      id: 'r${_n++}',
      baby: 'b1',
      type: RecordType.medication,
      ts: ts ?? DateTime.parse('${date}T${time ?? '12:00'}:00'),
      data: {
        'v': 2,
        'name': 'Demir',
        'plan_uuid': plan,
        'kind': kind,
        'dose_date': date,
        'dose_time': ?time,
        'given': !skipped,
        if (skipped) 'skipped': true,
        'skip_reason': ?reason,
      },
      createdBy: by,
    );

Record _legacy(String name, DateTime ts, {bool skipped = false}) => Record(
      id: 'l${_n++}',
      baby: 'b1',
      type: RecordType.medication,
      ts: ts,
      data: {'name': name, 'given': !skipped, if (skipped) 'skipped': true},
    );

List<String> _keys(List<PlannedDose> ds) =>
    [for (final d in ds) '${medDateToWire(d.doseDate)} ${d.doseTime}'];

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('generateDoses — sıklık türleri', () {
    final from = DateTime(2026, 10, 12), to = DateTime(2026, 10, 15);

    test('her gün: saat listesi', () {
      expect(_keys(generateDoses(_p(), from: from, to: to)), [
        '2026-10-12 08:00', '2026-10-12 20:00',
        '2026-10-13 08:00', '2026-10-13 20:00',
        '2026-10-14 08:00', '2026-10-14 20:00',
      ]);
    });

    test('N günde bir: başlangıçtan itibaren her N gün', () {
      final p = _p(freq: MedFreq.everyNDays, everyNDays: 2, times: ['09:00'],
          start: DateTime(2026, 10, 11));
      expect(_keys(generateDoses(p, from: from, to: DateTime(2026, 10, 18))),
          ['2026-10-13 09:00', '2026-10-15 09:00', '2026-10-17 09:00']);
    });

    test('haftalık: seçili günler (ISO) × saatler', () {
      // 12 Eki 2026 Pazartesi.
      final p = _p(freq: MedFreq.weekly, weekdays: [1, 3], times: ['08:00']);
      expect(_keys(generateDoses(p, from: from, to: DateTime(2026, 10, 20))),
          ['2026-10-12 08:00', '2026-10-14 08:00', '2026-10-19 08:00']);
    });

    test('her X saatte: çapa başlangıç + ilk saat, gece yarısını geçer', () {
      final p = _p(freq: MedFreq.interval, intervalHours: 8, times: ['06:00'],
          start: DateTime(2026, 10, 12));
      expect(_keys(generateDoses(p, from: from, to: DateTime(2026, 10, 14))), [
        '2026-10-12 06:00', '2026-10-12 14:00', '2026-10-12 22:00',
        '2026-10-13 06:00', '2026-10-13 14:00', '2026-10-13 22:00',
      ]);
    });

    test('her X saatte (24 bölmeyen): 5 saatte bir çapadan kesintisiz', () {
      final p = _p(freq: MedFreq.interval, intervalHours: 5, times: ['10:00'],
          start: DateTime(2026, 10, 12));
      expect(_keys(generateDoses(p, from: DateTime(2026, 10, 13), to: DateTime(2026, 10, 14))),
          ['2026-10-13 01:00', '2026-10-13 06:00', '2026-10-13 11:00',
           '2026-10-13 16:00', '2026-10-13 21:00']);
    });

    test('PRN doz üretmez', () {
      expect(generateDoses(_p(kind: MedKind.prn, times: const []), from: from, to: to), isEmpty);
    });

    test('başlangıçtan önce ve bitişten (dahil) sonra doz yok', () {
      final p = _p(start: DateTime(2026, 10, 13), end: DateTime(2026, 10, 14), times: ['08:00']);
      expect(_keys(generateDoses(p, from: from, to: DateTime(2026, 10, 17))),
          ['2026-10-13 08:00', '2026-10-14 08:00']);
    });

    test('plan oluşturulmadan önceki saatler üretilmez', () {
      final p = _p(createdAt: DateTime(2026, 10, 12, 10), times: ['08:00', '20:00']);
      expect(_keys(generateDoses(p, from: from, to: DateTime(2026, 10, 13))),
          ['2026-10-12 20:00']);
    });

    test('zamanlama çapasından ÖNCEKİ günler üretilmez, o gün üretilir', () {
      final p = _p(scheduleFrom: DateTime(2026, 10, 13, 10), times: ['08:00']);
      expect(_keys(generateDoses(p, from: from, to: DateTime(2026, 10, 15))),
          ['2026-10-13 08:00', '2026-10-14 08:00']);
    });

    test('duraklatma aralığındaki dozlar ve süren duraklatma sonrası üretilmez', () {
      final p = _p(times: ['08:00'], active: false, pauses: [
        MedPause(DateTime(2026, 10, 12, 12), DateTime(2026, 10, 13, 12)),
        MedPause(DateTime(2026, 10, 14, 12)),
      ]);
      expect(_keys(generateDoses(p, from: from, to: DateTime(2026, 10, 17))),
          ['2026-10-12 08:00', '2026-10-14 08:00']);
    });

    test('duraklatılmış ve geçmişi olmayan (v16 öncesi) plan hiç üretmez', () {
      final p = _p(active: false);
      expect(generateDoses(p, from: from, to: to), isEmpty);
    });
  });

  group('DST ve saat dilimi (doz yerel duvar saatiyle)', () {
    test('saat listesi DST gününde duvar saatini korur (yerel DateTime kurucusu)', () {
      // Yerel saat dilimi testte ne olursa olsun: dueAt = o günün 08:00'i.
      final p = _p(times: ['08:00']);
      for (final d in generateDoses(p, from: DateTime(2026, 3, 28), to: DateTime(2026, 4, 2))) {
        expect((d.dueAt.hour, d.dueAt.minute), (8, 0));
      }
    });

    test('her X saatte mutlak süre: ardışık dozlar arası tam X saat', () {
      final p = _p(freq: MedFreq.interval, intervalHours: 8, times: ['06:00'],
          start: DateTime(2026, 3, 27));
      final ds = generateDoses(p, from: DateTime(2026, 3, 27), to: DateTime(2026, 4, 2));
      for (var i = 1; i < ds.length; i++) {
        expect(ds[i].dueAt.difference(ds[i - 1].dueAt), const Duration(hours: 8));
      }
    });
  });

  group('resolveDoses — kimlikle çözümleme', () {
    final now = DateTime(2026, 10, 12, 21, 0);
    final from = DateTime(2026, 10, 12), to = DateTime(2026, 10, 13);

    MedicationDose at(List<MedicationDose> ds, String time) =>
        ds.firstWhere((d) => d.time == time && medDateToWire(d.doseDate) == '2026-10-12');

    test('S2: aynı doza iki "verildi" → givenMultiple, 20:00 açık kalır', () {
      final recs = [
        _dose('2026-10-12', '08:00', ts: DateTime(2026, 10, 12, 7, 58), by: 'A'),
        _dose('2026-10-12', '08:00', ts: DateTime(2026, 10, 12, 8, 3), by: 'B'),
      ];
      final ds = resolveDoses([_p()], recs, from: from, to: to, now: now);
      final d8 = at(ds, '08:00');
      expect(d8.status, MedicationDoseStatus.given);
      expect(d8.multiple, isTrue);
      expect(d8.givenRecords.map((r) => r.createdBy), ['A', 'B']);
      expect(at(ds, '20:00').status, MedicationDoseStatus.overdue);
    });

    test('S3: verildi + atlandı aynı doz → verildi kazanır + çakışma; 20:00 etkilenmez', () {
      final recs = [
        _dose('2026-10-12', '08:00', ts: DateTime(2026, 10, 12, 7, 58), by: 'A'),
        _dose('2026-10-12', '08:00', ts: DateTime(2026, 10, 12, 8, 5), skipped: true, by: 'B'),
      ];
      final ds = resolveDoses([_p()], recs, from: from, to: to, now: now);
      final d8 = at(ds, '08:00');
      expect(d8.status, MedicationDoseStatus.given);
      expect(d8.conflict, isTrue);
      expect(d8.skippedRecords.single.createdBy, 'B');
      expect(at(ds, '20:00').status, MedicationDoseStatus.overdue);
    });

    test('M4: dünkü 22:00 dozu 00:20\'de işaretlenir → dünün dozu, bugünün 08:00\'i açık', () {
      final p = _p(times: ['08:00', '22:00']);
      final rec = _dose('2026-10-12', '22:00', ts: DateTime(2026, 10, 13, 0, 20));
      final ds = resolveDoses([p], [rec],
          from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 14),
          now: DateTime(2026, 10, 13, 9));
      String st(String date, String t) => ds
          .firstWhere((d) => medDateToWire(d.doseDate) == date && d.time == t)
          .status
          .name;
      expect(st('2026-10-12', '22:00'), 'given');
      expect(st('2026-10-13', '08:00'), 'overdue');
    });

    test('M5: plan yeniden adlandırılsa da kimlikli kayıt bağlı kalır', () {
      final recs = [_dose('2026-10-12', '08:00')];
      final ds = resolveDoses([_p(name: 'Demir şurubu')], recs, from: from, to: to, now: now);
      expect(at(ds, '08:00').status, MedicationDoseStatus.given);
    });

    test('başka planın kaydı bu planı etkilemez (aynı ad olsa bile)', () {
      final recs = [_dose('2026-10-12', '08:00', plan: 'p2')];
      final ds = resolveDoses([_p()], recs, from: from, to: to, now: now);
      expect(at(ds, '08:00').isResolved, isFalse);
      expect(at(ds, '08:00').records, isEmpty);
    });

    test('saat değişikliği: eski saatteki kayıt yakın yeni doza bağlanır (gizli çift önlenir)', () {
      final p = _p(times: ['09:00'], scheduleFrom: DateTime(2026, 10, 12, 8, 30));
      final recs = [_dose('2026-10-12', '08:00', ts: DateTime(2026, 10, 12, 8, 1))];
      final ds = resolveDoses([p], recs, from: from, to: to, now: now);
      final d9 = at(ds, '09:00');
      expect(d9.status, MedicationDoseStatus.given);
      expect(d9.record, recs.single);
    });

    test('durumlar: yaklaşan / açık (<12 sa) / kaçırıldı (≥12 sa)', () {
      final ds = resolveDoses([_p()], const [],
          from: DateTime(2026, 10, 11), to: DateTime(2026, 10, 13),
          now: DateTime(2026, 10, 12, 21));
      String st(String date, String t) => ds
          .firstWhere((d) => medDateToWire(d.doseDate) == date && d.time == t)
          .status
          .name;
      expect(st('2026-10-11', '08:00'), 'missed');
      expect(st('2026-10-11', '20:00'), 'missed'); // 25 sa
      expect(st('2026-10-12', '08:00'), 'missed'); // 13 sa
      expect(st('2026-10-12', '20:00'), 'overdue'); // 1 sa → açık
    });

    test('roller: çözülen undo; ≤2 sa sonrası next; daha ileri early (S9)', () {
      final ds = resolveDoses([_p(times: ['08:00', '14:00', '20:00'])],
          [_dose('2026-10-12', '08:00')],
          from: from, to: to, now: DateTime(2026, 10, 12, 12, 30));
      expect(ds.map((d) => d.role), [
        MedicationDoseRole.undo,
        MedicationDoseRole.next,
        MedicationDoseRole.early,
      ]);
    });
  });

  group('kimliksiz eski kayıtlar (yakınlık eşlemesi)', () {
    test('ada göre plan, saate göre en yakın doz; gece yarısı sonrası dünün dozuna', () {
      final p = _p(times: ['08:00', '22:00']);
      final recs = [
        _legacy('demir', DateTime(2026, 10, 12, 8, 10)),
        _legacy('DEMİR', DateTime(2026, 10, 13, 0, 20)),
      ];
      final ds = resolveDoses([p], recs,
          from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 14),
          now: DateTime(2026, 10, 13, 9));
      final byKey = {
        for (final d in ds) '${medDateToWire(d.doseDate)} ${d.time}': d
      };
      expect(byKey['2026-10-12 08:00']!.status, MedicationDoseStatus.given);
      expect(byKey['2026-10-12 22:00']!.status, MedicationDoseStatus.given);
      expect(byKey['2026-10-13 08:00']!.status, MedicationDoseStatus.overdue);
      expect(byKey['2026-10-12 08:00']!.legacy, isTrue);
    });

    test('farklı adlı kimliksiz kayıt eşlenmez', () {
      final ds = resolveDoses([_p(times: ['08:00'])], [_legacy('D vit', DateTime(2026, 10, 12, 8))],
          from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 13),
          now: DateTime(2026, 10, 12, 9));
      expect(ds.single.status, MedicationDoseStatus.overdue);
    });
  });

  group('PRN', () {
    final prn = _p(kind: MedKind.prn, times: const [], prnMin: 360, prnMax: 3, uuid: 'prn');

    test('son veriliş, geçen süre, en kısa aralık dolmadı uyarısı, günlük sayı', () {
      final recs = [
        _dose('2026-10-12', null, plan: 'prn', kind: 'prn', ts: DateTime(2026, 10, 12, 6), by: 'A'),
        _dose('2026-10-12', null, plan: 'prn', kind: 'prn', ts: DateTime(2026, 10, 12, 14, 10), by: 'B'),
        _dose('2026-10-12', null, plan: 'prn', kind: 'prn', ts: DateTime(2026, 10, 12, 15), skipped: true),
      ];
      final s = prnStatus(prn, recs, now: DateTime(2026, 10, 12, 17, 30));
      expect(s.last!.createdBy, 'B');
      expect(s.sinceLast, const Duration(hours: 3, minutes: 20));
      expect(s.countToday, 2);
      expect(s.tooSoon, isTrue);
      expect(s.remaining, const Duration(hours: 2, minutes: 40));
      expect(s.atDailyMax, isFalse);
      final later = prnStatus(prn, recs, now: DateTime(2026, 10, 12, 20, 30));
      expect(later.tooSoon, isFalse);
    });

    test('günlük üst sınıra ulaşıldı', () {
      final recs = [
        for (final h in [1, 8, 15])
          _dose('2026-10-12', null, plan: 'prn', kind: 'prn', ts: DateTime(2026, 10, 12, h)),
      ];
      expect(prnStatus(prn, recs, now: DateTime(2026, 10, 12, 22)).atDailyMax, isTrue);
    });

    test('aralık girilmemişse uyarı yok, yalnız geçen süre', () {
      final p = _p(kind: MedKind.prn, times: const [], uuid: 'prn');
      final s = prnStatus(p,
          [_dose('2026-10-12', null, plan: 'prn', kind: 'prn', ts: DateTime(2026, 10, 12, 20))],
          now: DateTime(2026, 10, 12, 21));
      expect(s.tooSoon, isFalse);
      expect(s.sinceLast, const Duration(hours: 1));
    });
  });

  group('medicationDay (kart) — dünün açık dozu', () {
    test('dünün çözülmemiş son dozu 12 saat boyunca kartta, sonra düşer', () {
      final p = _p(times: ['08:00', '22:00']);
      final day = medicationDay([p], const [], now: DateTime(2026, 10, 13, 7));
      final y = day.rows.single.doses.where((d) => d.fromYesterday).toList();
      expect(y.map((d) => d.time), ['22:00']);
      expect(y.single.status, MedicationDoseStatus.overdue);
      final later = medicationDay([p], const [], now: DateTime(2026, 10, 13, 10, 1));
      expect(later.rows.single.doses.any((d) => d.fromYesterday), isFalse);
    });

    test('PRN planları kartta ayrı listede', () {
      final prn = _p(kind: MedKind.prn, times: const [], uuid: 'prn', id: 9);
      final day = medicationDay([_p(), prn], const [], now: DateTime(2026, 10, 12, 9));
      expect(day.prn.single.plan.id, 9);
      expect(day.rows.single.plan.id, 1);
    });

    test('kürü biten plan kartta yok', () {
      final p = _p(end: DateTime(2026, 10, 11));
      final day = medicationDay([p], const [], now: DateTime(2026, 10, 12, 9));
      expect(day.rows, isEmpty);
      expect(day.planCount, 1);
    });
  });

  group('medicationHistory (K11)', () {
    test('günlere göre: verildi/atlandı(neden)/kaçırıldı/çift; duraklatma ve çapa öncesi', () {
      final p = _p(times: ['08:00'], scheduleFrom: DateTime(2026, 10, 8, 7),
          pauses: [MedPause(DateTime(2026, 10, 10, 0), DateTime(2026, 10, 11, 0))]);
      final recs = [
        _dose('2026-10-09', '08:00', by: 'A'),
        _dose('2026-10-09', '08:00', by: 'B'),
        _dose('2026-10-11', '08:00', skipped: true, reason: 'vomited'),
        _dose('2026-10-07', '08:00'), // çapa öncesi: kayıt görünür, beklenen yok
      ];
      final h = medicationHistory(p, recs,
          from: DateTime(2026, 10, 6), to: DateTime(2026, 10, 12),
          now: DateTime(2026, 10, 12, 21));
      String day(String d) {
        final x = h.days.firstWhere((e) => medDateToWire(e.day) == d);
        if (x.paused) return 'paused';
        if (x.doses.isEmpty) return x.extra.isNotEmpty ? 'records-only' : 'none';
        return x.doses.map((d) => d.multiple ? 'multiple' : d.status.name).join(',');
      }

      expect(day('2026-10-07'), 'records-only');
      expect(day('2026-10-08'), 'missed');
      expect(day('2026-10-09'), 'multiple');
      expect(day('2026-10-10'), 'paused');
      expect(day('2026-10-11'), 'skipped');
      expect(day('2026-10-12'), 'missed'); // 13 sa geçti
      expect(h.given, 1);
      expect(h.skipped, 1);
      expect(h.missed, 2);
      expect(h.multiple, 1);
      expect(h.days.first.day, DateTime(2026, 10, 12)); // en yeni üstte
    });
  });

  // ILAC-INCELEME-2 V1: önceki güne ait kayıt bugünün dozunu "verildi" yapmamalı.
  group('V1 — gün sınırı (önceki günün kaydı bugünün dozunu kapatmaz)', () {
    test('saat 21:00→09:00 (scheduleFrom bugün): dünkü kimlikli kayıt bugünün 09:00\'ını kapatmaz', () {
      final p = _p(times: ['09:00'], scheduleFrom: DateTime(2026, 10, 12, 7));
      final recs = [_dose('2026-10-11', '21:00', ts: DateTime(2026, 10, 11, 21, 2))];
      final today = todaysMedicationDoses([p], recs, now: DateTime(2026, 10, 12, 7, 30));
      expect(today.single.status, MedicationDoseStatus.upcoming);
      expect(today.single.records, isEmpty);
      final open = todaysMedicationDoses([p], recs, now: DateTime(2026, 10, 12, 10));
      expect(open.single.status, MedicationDoseStatus.overdue);
    });

    test('bugün oluşturulan plan: dünkü kimliksiz kayıt bugünün dozunu kapatmaz', () {
      final p = _p(times: ['09:00'], createdAt: DateTime(2026, 10, 12, 7), start: DateTime(2026, 10, 12));
      final recs = [_legacy('Demir', DateTime(2026, 10, 11, 21, 2))];
      final today = todaysMedicationDoses([p], recs, now: DateTime(2026, 10, 12, 7, 30));
      expect(today.single.status, MedicationDoseStatus.upcoming);
      expect(today.single.records, isEmpty);
    });

    test('kimliksiz kayıt: üretilmeyen (oluşturma öncesi) komşu doz kaydı "emer"', () {
      // Tek günlük kür, plan 19:00'da oluşturuldu → 08:00 üretilmez. 08:05'teki elle girilmiş
      // kayıt 20:00 dozuna 12 sa'ten az uzakta olsa da ona bağlanmaz: ham
      // takvimde en yakını (üretilmeyen) 08:00.
      final p = _p(times: ['08:00', '20:00'], createdAt: DateTime(2026, 10, 11, 19),
          start: DateTime(2026, 10, 11), end: DateTime(2026, 10, 11));
      final recs = [_legacy('Demir', DateTime(2026, 10, 11, 8, 5))];
      final ds = resolveDoses([p], recs,
          from: DateTime(2026, 10, 11), to: DateTime(2026, 10, 12),
          now: DateTime(2026, 10, 11, 19, 30));
      expect(ds.single.time, '20:00');
      expect(ds.single.records, isEmpty);
    });

    // ILAC-INCELEME-3 W5: ham takvim güncel saatlerle kurulur (tarihsel saatler
    // bilinmez) → kimliksiz kayıtta bağlanma eşiği en çok 3 sa.
    test('W5: 23:00→07:00 (bugün 00:20) + kimliksiz 00:30 kaydı bugünün 07:00 dozunu kapatmaz', () {
      final p = _p(times: ['07:00'], scheduleFrom: DateTime(2026, 10, 12, 0, 20));
      final recs = [_legacy('Demir', DateTime(2026, 10, 12, 0, 30))];
      final today = todaysMedicationDoses([p], recs, now: DateTime(2026, 10, 12, 0, 40));
      expect(today.single.time, '07:00');
      expect(today.single.status, MedicationDoseStatus.upcoming);
      expect(today.single.records, isEmpty);
    });

    test('W5: kimliksiz kayıt en çok 3 sa uzaktaki doza bağlanır (sınır dahil)', () {
      final p = _p(times: ['09:00']);
      DateTime? attached(DateTime ts) {
        final ds = resolveDoses([p], [_legacy('Demir', ts)],
            from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 13),
            now: DateTime(2026, 10, 12, 13));
        final d = ds.single;
        return d.records.isEmpty ? null : d.dueAt;
      }

      expect(attached(DateTime(2026, 10, 12, 12)), DateTime(2026, 10, 12, 9));
      expect(attached(DateTime(2026, 10, 12, 6)), DateTime(2026, 10, 12, 9));
      expect(attached(DateTime(2026, 10, 12, 12, 1)), isNull);
      expect(attached(DateTime(2026, 10, 12, 5, 59)), isNull);
    });

    test('kimlikli yetim yalnız aynı dose_date\'in dozuna bağlanır', () {
      final p = _p(times: ['09:00'], scheduleFrom: DateTime(2026, 10, 12, 7));
      final recs = [_dose('2026-10-11', '22:00', ts: DateTime(2026, 10, 11, 22, 1))];
      final ds = resolveDoses([p], recs,
          from: DateTime(2026, 10, 11), to: DateTime(2026, 10, 13),
          now: DateTime(2026, 10, 12, 8));
      expect(ds.every((d) => d.records.isEmpty), isTrue);
    });
  });

  // ILAC-INCELEME-2 V3: aktif plan + kapanmamış duraklatma aralığı (ör. eski
  // sürümdeki üye "devam ettir" dedi, pauses göndermedi) doz kaybettirmemeli.
  test('V3: aktif planda kapanmamış duraklatma aralığı kapanmış sayılır — dozlar üretilir', () {
    final p = _p(times: ['09:00'], active: true, pauses: [MedPause(DateTime.utc(2026, 10, 10))]);
    final ds = generateDoses(p, from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 13));
    expect(_keys(ds), ['2026-10-12 09:00']);
    // Duraklatılmış (active=false) planda aynı açık aralık dozları keser.
    final paused = _p(times: ['09:00'], active: false, pauses: [MedPause(DateTime.utc(2026, 10, 10))]);
    expect(generateDoses(paused, from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 13)), isEmpty);
  });

  test('V16: büyük harfli plan_uuid\'li kimlikli kayıt planın dozuna bağlanır', () {
    final p = _p(uuid: 'abcdef01-2345-4678-9abc-def012345678', times: ['08:00']);
    final recs = [
      _dose('2026-10-12', '08:00',
          plan: 'ABCDEF01-2345-4678-9ABC-DEF012345678', ts: DateTime(2026, 10, 12, 8, 1)),
    ];
    final ds = todaysMedicationDoses([p], recs, now: DateTime(2026, 10, 12, 9));
    expect(ds.single.status, MedicationDoseStatus.given);
  });
}
