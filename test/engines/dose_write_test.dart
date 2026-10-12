import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/core/medication/dose_write.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

/// İlaç v2 (A3) — doz kaydı kurucusu (kimlik alanları) ve K3 çift doz denetimi.
MedicationPlan _p({List<String> times = const ['08:00', '20:00'], MedKind kind = MedKind.scheduled,
        MedFreq freq = MedFreq.daily, int? interval, int? prnMin}) =>
    MedicationPlan(
      id: 1, uuid: 'p1', name: 'Demir', dose: '1 ml', times: times, active: true,
      createdAt: DateTime(2026, 10, 1), kind: kind, freq: freq, intervalHours: interval,
      prnMinIntervalMin: prnMin, startDate: DateTime(2026, 10, 1));

Record _given(DateTime ts, {String? by, String date = '2026-10-12', String? time = '08:00'}) =>
    Record(
      id: 'g$ts',
      baby: 'b1',
      type: RecordType.medication,
      ts: ts,
      data: {
        'v': 2, 'name': 'Demir', 'plan_uuid': 'p1', 'kind': 'scheduled',
        'dose_date': date, 'dose_time': ?time, 'given': true,
      },
      createdBy: by,
    );

void main() {
  group('medDoseRecord', () {
    test('planlı doz: kimlik + at_hm + v2; ts = işaret anı', () {
      final r = medDoseRecord(
        id: 'x', babyId: 'b1', plan: _p(),
        doseDate: DateTime(2026, 10, 12), doseTime: '22:00',
        at: DateTime(2026, 10, 13, 0, 20), skipped: false,
      );
      expect(r.type, RecordType.medication);
      expect(r.ts, DateTime(2026, 10, 13, 0, 20));
      expect(r.data, {
        'v': 2, 'name': 'Demir', 'dose': '1 ml', 'plan_uuid': 'p1',
        'kind': 'scheduled', 'dose_date': '2026-10-12', 'dose_time': '22:00',
        'given': true, 'at_hm': '00:20',
      });
    });

    test('atlandı + neden (diğer → kısa not, 80 karakter)', () {
      final r = medDoseRecord(
        id: 'x', babyId: 'b1', plan: _p(), doseDate: DateTime(2026, 10, 12),
        doseTime: '08:00', at: DateTime(2026, 10, 12, 8, 5), skipped: true,
        reason: MedSkipReason.other, note: 'x' * 100,
      );
      expect(r.data['given'], false);
      expect(r.data['skipped'], true);
      expect(r.data['skip_reason'], 'other');
      expect((r.data['skip_note'] as String).length, 80);
    });

    test('PRN: dose_time yok, dose_date = veriliş günü', () {
      final r = medDoseRecord(
        id: 'x', babyId: 'b1', plan: _p(kind: MedKind.prn, times: const []),
        doseDate: DateTime(2026, 10, 12), at: DateTime(2026, 10, 12, 14, 10), skipped: false,
      );
      expect(r.data['kind'], 'prn');
      expect(r.data.containsKey('dose_time'), isFalse);
      expect(r.data['dose_date'], '2026-10-12');
    });

    test('plan saatinde varsayılan kayıt (dün özeti) işaretlenir (M20)', () {
      final r = medDoseRecord(
        id: 'x', babyId: 'b1', plan: _p(), doseDate: DateTime(2026, 10, 11),
        doseTime: '08:00', at: DateTime(2026, 10, 11, 8), skipped: false, timeAssumed: true,
      );
      expect(r.data['time_assumed'], true);
    });
  });

  group('medMinGap', () {
    test('saat listesi: ardışık en kısa fark (gece sarması dahil)', () {
      expect(medMinGap(_p(times: ['08:00', '20:00'])), const Duration(hours: 12));
      expect(medMinGap(_p(times: ['08:00', '14:00', '22:00'])), const Duration(hours: 6));
      expect(medMinGap(_p(times: ['23:00', '01:00'])), const Duration(hours: 2));
      expect(medMinGap(_p(times: ['09:00'])), const Duration(hours: 24));
    });
    test('her X saatte: X', () {
      expect(medMinGap(_p(freq: MedFreq.interval, interval: 8, times: ['06:00'])),
          const Duration(hours: 8));
    });
  });

  group('medDuplicateCheck (K3)', () {
    final now = DateTime(2026, 10, 12, 8, 10);

    test('doz zaten verilmiş → ilk verenin kaydı', () {
      final g = _given(DateTime(2026, 10, 12, 7, 58), by: 'A');
      final d = resolveDoses([_p()], [g],
              from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 13), now: now)
          .first;
      final hit = medDuplicateCheck(_p(), d, [g], now: now);
      expect(hit?.record, g);
      expect(hit?.sameDose, isTrue);
    });

    test('gizli çift: başka doza bağlı ama yarım boşluk içinde verilmiş', () {
      // 08:00 dozu 07:30'da verilmiş (kayıt), kullanıcı 09:00 sonrası değişen
      // saatte (ör. eski saat kaydı) aynı ilacı yeniden işaretliyor.
      final g = _given(DateTime(2026, 10, 12, 7, 30), by: 'A', time: '06:00');
      final hit = medDuplicateCheck(_p(), null, [g], now: now);
      expect(hit?.record, g);
      expect(hit?.sameDose, isFalse);
    });

    test('yarım boşluk dışında → uyarı yok', () {
      final g = _given(DateTime(2026, 10, 11, 20, 0), date: '2026-10-11', time: '20:00');
      expect(medDuplicateCheck(_p(), null, [g], now: now), isNull);
    });

    test('atlanan ya da silinen kayıt çift sayılmaz', () {
      final s = Record(
          id: 's', baby: 'b1', type: RecordType.medication, ts: DateTime(2026, 10, 12, 8),
          data: const {'plan_uuid': 'p1', 'dose_date': '2026-10-12', 'dose_time': '08:00',
            'given': false, 'skipped': true});
      final del = Record(
          id: 'd', baby: 'b1', type: RecordType.medication, ts: DateTime(2026, 10, 12, 8),
          data: const {'plan_uuid': 'p1', 'dose_date': '2026-10-12', 'dose_time': '08:00',
            'given': true},
          isDeleted: true);
      expect(medDuplicateCheck(_p(), null, [s, del], now: now), isNull);
    });

    test('PRN: kullanıcı aralığı dolmadıysa uyarı (aralık yoksa yok)', () {
      final prn = _p(kind: MedKind.prn, times: const [], prnMin: 360);
      final g = _given(DateTime(2026, 10, 12, 6), time: null);
      expect(medDuplicateCheck(prn, null, [g], now: now)?.record, g);
      final noMin = _p(kind: MedKind.prn, times: const []);
      expect(medDuplicateCheck(noMin, null, [g], now: now), isNull);
    });
  });
}
