import 'package:adena_baby/core/age.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prematüre / düzeltilmiş yaş saf mantığı (lib/core/age.dart).
/// Tüm testler sabit [now] enjekte eder (DateTime.now()'a bağlı değil).
void main() {
  Baby born({
    DateTime? birth,
    DateTime? due,
    int? gestWeeks,
    int gestDays = 0,
  }) =>
      Baby(
        id: 'b1',
        name: 'Bebe',
        status: BabyStatus.born,
        birthDate: birth,
        dueDate: due,
        gestationalWeeks: gestWeeks,
        gestationalDays: gestDays,
      );

  group('isPremature (model getter)', () {
    test('gebelik haftası yok → prematüre değil', () {
      expect(born(birth: DateTime(2026, 1, 1)).isPremature, isFalse);
    });
    test('40 hafta → prematüre değil', () {
      expect(born(birth: DateTime(2026, 1, 1), gestWeeks: 40).isPremature, isFalse);
    });
    test('37 hafta → prematüre değil (sınır)', () {
      expect(born(birth: DateTime(2026, 1, 1), gestWeeks: 37).isPremature, isFalse);
    });
    test('36 hafta → prematüre', () {
      expect(born(birth: DateTime(2026, 1, 1), gestWeeks: 36).isPremature, isTrue);
    });
    test('32 hafta → prematüre', () {
      expect(born(birth: DateTime(2026, 1, 1), gestWeeks: 32).isPremature, isTrue);
    });
  });

  group('prematureEarlyDays', () {
    test('term → 0', () {
      expect(prematureEarlyDays(born(birth: DateTime(2026, 1, 1))), 0);
      expect(prematureEarlyDays(born(birth: DateTime(2026, 1, 1), gestWeeks: 40)), 0);
    });
    test('null bebek → 0', () => expect(prematureEarlyDays(null), 0));
    test('32 hafta → 56 gün', () {
      expect(prematureEarlyDays(born(birth: DateTime(2026, 1, 1), gestWeeks: 32)), 56);
    });
    test('34 hafta 3 gün → 39 gün', () {
      expect(
          prematureEarlyDays(
              born(birth: DateTime(2026, 1, 1), gestWeeks: 34, gestDays: 3)),
          39);
    });
  });

  group('correctedAgeMonths', () {
    final now = DateTime(2026, 6, 1);
    test('bekleme → null', () {
      final b = Baby(id: 'x', name: 'X', status: BabyStatus.expecting, dueDate: now);
      expect(correctedAgeMonths(b, now: now), isNull);
    });
    test('null → null', () => expect(correctedAgeMonths(null, now: now), isNull));
    test('term → takvim yaşına eşit', () {
      final b = born(birth: DateTime(2026, 1, 1));
      expect(correctedAgeMonths(b, now: now), ageInMonths(b, now: now));
      expect(correctedAgeMonths(b, now: now), 5);
    });
    test('32 haftalık prematüre → düzeltilmiş 3 ay (takvim 5)', () {
      final b = born(birth: DateTime(2026, 1, 1), gestWeeks: 32); // 56g erken
      expect(ageInMonths(b, now: now), 5);
      // adj doğum = 2026-02-26 → 2026-06-01: 3 ay (gün 1<26)
      expect(correctedAgeMonths(b, now: now), 3);
    });
    test('24 ay üstünde düzeltme bırakılır (takvim döner)', () {
      final b = born(birth: DateTime(2023, 1, 1), gestWeeks: 30); // çok erken
      final chrono = ageInMonths(b, now: now)!; // ~41 ay
      expect(chrono >= 24, isTrue);
      expect(correctedAgeMonths(b, now: now), chrono);
    });
    test('düzeltilmiş yaş negatife düşmez (0 taban)', () {
      // Doğumdan hemen sonra, çok erken: düzeltilmiş < 0 olabilir → 0.
      final b = born(birth: DateTime(2026, 5, 25), gestWeeks: 28);
      expect(correctedAgeMonths(b, now: DateTime(2026, 6, 1)), 0);
    });
  });

  group('usesCorrectedAge', () {
    final now = DateTime(2026, 6, 1);
    test('term → false', () {
      expect(usesCorrectedAge(born(birth: DateTime(2026, 1, 1)), now: now), isFalse);
    });
    test('null → false', () => expect(usesCorrectedAge(null, now: now), isFalse));
    test('prematüre + 24 ay altı → true', () {
      expect(
          usesCorrectedAge(born(birth: DateTime(2026, 1, 1), gestWeeks: 32), now: now),
          isTrue);
    });
    test('prematüre + 24 ay üstü → false (düzeltme bitti)', () {
      expect(
          usesCorrectedAge(born(birth: DateTime(2023, 1, 1), gestWeeks: 30), now: now),
          isFalse);
    });
  });

  group('correctedAgeShort', () {
    final now = DateTime(2026, 6, 1);
    test('term → babyAgeShort ile aynı', () {
      final b = born(birth: DateTime(2026, 1, 1));
      expect(correctedAgeShort(b, now: now), babyAgeShort(b, now: now));
    });
    test('prematüre → düzeltilmiş etiket (ayrı)', () {
      final b = born(birth: DateTime(2026, 1, 1), gestWeeks: 32);
      // düzeltilmiş ~3 ay; takvim 5 ay → farklı olmalı
      expect(correctedAgeShort(b, now: now), isNot(babyAgeShort(b, now: now)));
      expect(correctedAgeShort(b, now: now), contains('ay'));
    });
    test('düzeltilmiş yaş negatifken (TDT gelmedi) takvim yaşına düşer — "Takip" değil', () {
      // Çok erken doğum (22 hf), doğum günü = bugün: düzeltilmiş doğum anı
      // gelecekte → eski davranış "Takip" gösteriyordu (ana ekran rozeti bug'ı).
      final b = born(birth: DateTime(2026, 6, 1), gestWeeks: 22);
      final s = correctedAgeShort(b, now: DateTime(2026, 6, 1));
      expect(s, babyAgeShort(b, now: DateTime(2026, 6, 1))); // "0 gün"
      expect(s, isNot('Takip'));
    });
  });

  group('dualAgeLabel', () {
    final now = DateTime(2026, 6, 1);
    test('term → sade takvim etiketi (düzeltilmiş yok)', () {
      final b = born(birth: DateTime(2026, 1, 1));
      final s = dualAgeLabel(b, now: now);
      expect(s, babyAgeShort(b, now: now));
      expect(s.contains('düzeltilmiş'), isFalse);
    });
    test('prematüre → çift etiket düzeltilmiş içerir', () {
      final b = born(birth: DateTime(2026, 1, 1), gestWeeks: 32);
      final s = dualAgeLabel(b, now: now);
      expect(s, contains('düzeltilmiş'));
      expect(s, startsWith(babyAgeShort(b, now: now)));
    });
  });

  group('gestationalAgeFromDue (otomatik türetme)', () {
    test('tam tahmini tarihinde doğum → null (term)', () {
      expect(gestationalAgeFromDue(DateTime(2026, 6, 1), DateTime(2026, 6, 1)), isNull);
    });
    test('tahminden sonra doğum → null (term/geç)', () {
      expect(gestationalAgeFromDue(DateTime(2026, 6, 10), DateTime(2026, 6, 1)), isNull);
    });
    test('56 gün erken → 32 hafta 0 gün', () {
      final r = gestationalAgeFromDue(DateTime(2026, 4, 6), DateTime(2026, 6, 1));
      expect(r, isNotNull);
      expect(r!.weeks, 32);
      expect(r.days, 0);
    });
    test('59 gün erken → 31 hafta 4 gün', () {
      final r = gestationalAgeFromDue(DateTime(2026, 4, 3), DateTime(2026, 6, 1));
      expect(r!.weeks, 31);
      expect(r.days, 4);
    });
  });
}
