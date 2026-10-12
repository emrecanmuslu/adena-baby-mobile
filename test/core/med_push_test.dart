import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/push_service.dart';

/// İlaç v2 (A5) — `med_dose` / `access_removed` push yükünden yapılacak iş
/// (ağsız, DB'siz; Android bg isolate'ta da çalışır).
void main() {
  group('medDoseCancelTarget', () {
    test('verildi/atlandı + kimlik → o dozun bildirimi iptal edilir', () {
      for (final ev in ['given', 'skipped']) {
        final t = medDoseCancelTarget({
          'type': 'med_dose', 'event': ev, 'plan_uuid': 'p1',
          'dose_date': '2026-10-12', 'dose_time': '08:00',
        });
        expect(t, (plan: 'p1', date: '2026-10-12', time: '08:00'));
      }
    });

    test('geri alındı / sessiz güncelleme / PRN / kimliksiz → iptal yok', () {
      expect(medDoseCancelTarget({'type': 'med_dose', 'event': 'undone', 'plan_uuid': 'p1',
          'dose_date': '2026-10-12', 'dose_time': '08:00'}), isNull);
      expect(medDoseCancelTarget({'type': 'med_dose', 'event': 'updated', 'plan_uuid': 'p1',
          'dose_date': '2026-10-12', 'dose_time': '08:00'}), isNull);
      expect(medDoseCancelTarget({'type': 'med_dose', 'event': 'given', 'plan_uuid': 'p1',
          'dose_date': '2026-10-12'}), isNull);
      expect(medDoseCancelTarget({'type': 'med_dose', 'event': 'given', 'legacy': '1'}), isNull);
      expect(medDoseCancelTarget({'type': 'family_activity'}), isNull);
    });
  });

  test('V7: geri alındı ama doz başkasınca HÂLÂ verilmiş (still_given) → iptal (geri ekleme yok)', () {
    expect(
        medDoseCancelTarget({'type': 'med_dose', 'event': 'undone', 'still_given': '1',
            'plan_uuid': 'p1', 'dose_date': '2026-10-12', 'dose_time': '08:00'}),
        (plan: 'p1', date: '2026-10-12', time: '08:00'));
  });

  test('accessRemovedBabyId: yalnız access_removed + baby_id', () {
    expect(accessRemovedBabyId({'type': 'access_removed', 'baby_id': 'b1'}), 'b1');
    expect(accessRemovedBabyId({'type': 'access_removed'}), isNull);
    expect(accessRemovedBabyId({'type': 'baby_update', 'baby_id': 'b1'}), isNull);
  });
}
