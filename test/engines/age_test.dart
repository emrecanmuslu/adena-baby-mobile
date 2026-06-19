import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/age.dart';
import 'package:adena_baby/models/baby.dart';

/// Saf yaş hesapları (core/age.dart) — sabit referans an ile test edilebilir.
/// tr()/trp() varsayılan locale 'tr' altında kaynak anahtarı döndürdüğü için
/// etiketler doğrudan beklenen TR metinleridir.

Baby _born(DateTime birth, {String id = 'b1'}) =>
    Baby(id: id, name: 'Test', status: BabyStatus.born, birthDate: birth);

Baby _expecting({DateTime? due, String id = 'b1'}) =>
    Baby(id: id, name: 'Test', status: BabyStatus.expecting, dueDate: due);

Baby _premature(DateTime birth, {int weeks = 32, int days = 0, String id = 'b1'}) =>
    Baby(
        id: id,
        name: 'Test',
        status: BabyStatus.born,
        birthDate: birth,
        gestationalWeeks: weeks,
        gestationalDays: days);

void main() {
  group('ageInMonths', () {
    test('tam ay sınırında doğru ay', () {
      final now = DateTime(2025, 4, 15);
      expect(ageInMonths(_born(DateTime(2025, 1, 15)), now: now), 3);
    });

    test('now.day < bd.day → ay 1 azalır', () {
      final now = DateTime(2025, 4, 15);
      expect(ageInMonths(_born(DateTime(2025, 1, 20)), now: now), 2);
    });

    test('now.day >= bd.day → azalma yok', () {
      final now = DateTime(2025, 4, 15);
      expect(ageInMonths(_born(DateTime(2025, 1, 10)), now: now), 3);
    });

    test('gelecekteki doğum tarihi → 0', () {
      final now = DateTime(2025, 4, 15);
      expect(ageInMonths(_born(DateTime(2026, 1, 1)), now: now), 0);
    });

    test('bekleyen bebek → null', () {
      final now = DateTime(2025, 4, 15);
      expect(ageInMonths(_expecting(due: DateTime(2025, 9, 1)), now: now), null);
    });

    test('doğum tarihi yok → null', () {
      final now = DateTime(2025, 4, 15);
      final noBirth = Baby(id: 'b1', name: 'X', status: BabyStatus.born);
      expect(ageInMonths(noBirth, now: now), null);
    });

    test('null bebek → null', () {
      expect(ageInMonths(null, now: DateTime(2025, 4, 15)), null);
    });

    test('çok yıllı yaş ay olarak', () {
      final now = DateTime(2025, 6, 18);
      expect(ageInMonths(_born(DateTime(2022, 3, 10)), now: now), 39);
    });
  });

  group('babyAgeShort', () {
    test('1 aydan küçük → "{n} gün"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_born(DateTime(2026, 6, 13)), now: now), '5 gün');
    });

    test('24 aydan küçük, gün=0 → "{n} ay"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_born(DateTime(2025, 4, 18)), now: now), '14 ay');
    });

    test('24 aydan küçük, gün>0 → "{n} ay {d} gün"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_born(DateTime(2025, 4, 10)), now: now), '14 ay 8 gün');
    });

    test('24 ay ve üzeri, ay=0 → "{n} yaş"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_born(DateTime(2023, 6, 18)), now: now), '3 yaş');
    });

    test('24 ay ve üzeri, ay>0 → "{n} yaş {m} ay"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_born(DateTime(2023, 2, 18)), now: now), '3 yaş 4 ay');
    });

    test('gün ödünç alma (days<0) → ay azalır, gün önceki aydan eklenir', () {
      // birth 2026-01-31, now 2026-03-15: days=-16<0 → months-1, days+=28(Şubat)
      // = 12; totalMonths=1 → "1 ay 12 gün".
      final now = DateTime(2026, 3, 15);
      expect(babyAgeShort(_born(DateTime(2026, 1, 31)), now: now), '1 ay 12 gün');
    });

    test('bekleyen + dueDate → "{w}. hf"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_expecting(due: DateTime(2026, 8, 27)), now: now),
          '30. hf');
    });

    test('bekleyen, dueDate yok → "Bekliyor"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_expecting(), now: now), 'Bekliyor');
    });

    test('doğmuş ama doğum tarihi yok → "Takip"', () {
      final now = DateTime(2026, 6, 18);
      final noBirth = Baby(id: 'b1', name: 'X', status: BabyStatus.born);
      expect(babyAgeShort(noBirth, now: now), 'Takip');
    });

    test('doğum gelecekte → "Takip"', () {
      final now = DateTime(2026, 6, 18);
      expect(babyAgeShort(_born(DateTime(2026, 12, 1)), now: now), 'Takip');
    });
  });

  group('dualAgeLabel', () {
    test('term bebek → sade takvim yaşı (ikili etiket yok)', () {
      final now = DateTime(2026, 6, 18);
      // Term: babyAgeShort ile birebir aynı, "düzeltilmiş" geçmemeli.
      final b = _born(DateTime(2025, 4, 18));
      expect(dualAgeLabel(b, now: now), babyAgeShort(b, now: now));
      expect(dualAgeLabel(b, now: now).contains('düzeltilmiş'), false);
    });

    test('prematüre + düzeltme etkin → ikili etiket', () {
      // 32 hafta doğum = 8 hafta (56 gün) erken. now-birth ~ 5 ay; düzeltilmiş ~3 ay.
      final now = DateTime(2026, 6, 18);
      final b = _premature(DateTime(2026, 1, 18), weeks: 32);
      final label = dualAgeLabel(b, now: now);
      expect(label.contains('düzeltilmiş'), true);
      // takvim yaşı ile başlar, düzeltilmiş kısmı içerir.
      expect(label.startsWith(babyAgeShort(b, now: now)), true);
      expect(label.contains(correctedAgeShort(b, now: now)), true);
    });

    test('prematüre ama 24 ay üstü → düzeltme bırakılır (sade etiket)', () {
      final now = DateTime(2026, 6, 18);
      final b = _premature(DateTime(2024, 1, 18), weeks: 32);
      expect(dualAgeLabel(b, now: now).contains('düzeltilmiş'), false);
      expect(dualAgeLabel(b, now: now), babyAgeShort(b, now: now));
    });

    test('usesCorrectedAge: term=false, prematüre<24ay=true', () {
      final now = DateTime(2026, 6, 18);
      expect(usesCorrectedAge(_born(DateTime(2026, 1, 18)), now: now), false);
      expect(usesCorrectedAge(_premature(DateTime(2026, 1, 18)), now: now), true);
    });
  });

  group('pregnancyWeeks', () {
    test('uzak gelecekteki due → 0 (kırpma)', () {
      final now = DateTime(2026, 6, 18);
      expect(pregnancyWeeks(DateTime(2028, 1, 1), now: now), 0);
    });

    test('uzak geçmişteki due → 280 gün → 40 hafta (kırpma)', () {
      final now = DateTime(2026, 6, 18);
      expect(pregnancyWeeks(DateTime(2025, 1, 1), now: now), 40);
    });

    test('orta değer: hafta = gün ~/ 7', () {
      // due now+70g → daysPregnant=210 → 30 hafta.
      final now = DateTime(2026, 6, 18);
      expect(pregnancyWeeks(DateTime(2026, 8, 27), now: now), 30);
    });
  });
}
