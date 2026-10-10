import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_anchor.dart';
import 'package:adena_baby/models/cycle.dart';

/// K6 (BULGULAR.md): adet düzenleme takvimi çapayı tüm işaretli günlerin en
/// eskisine çekip doğum/kayıp sıfırlamasını geri alıyor ve patchSettings'in
/// otomatik "tracking" geçişini tetikliyordu. Saf çapa kuralları burada.
void main() {
  final birth = DateTime(2026, 2, 1);

  group('afterLatestReset', () {
    test('sıfırlama yoksa her gün geçerli', () {
      expect(afterLatestReset(DateTime(2020, 1, 1), const CycleSettings()), isTrue);
    });
    test('doğum günü ve öncesi geçersiz, sonrası geçerli', () {
      final s = CycleSettings(birthDate: birth);
      expect(afterLatestReset(DateTime(2026, 1, 31), s), isFalse);
      expect(afterLatestReset(birth, s), isFalse);
      expect(afterLatestReset(DateTime(2026, 2, 2), s), isTrue);
    });
    test('doğum + kayıp varsa en SON olay esas', () {
      final s = CycleSettings(birthDate: birth, lastLossDate: DateTime(2026, 4, 1));
      expect(afterLatestReset(DateTime(2026, 3, 1), s), isFalse);
      expect(afterLatestReset(DateTime(2026, 4, 2), s), isTrue);
    });
  });

  group('anchorCandidate', () {
    test('sıfırlama sonrası en eski adet günü', () {
      final s = CycleSettings(birthDate: birth);
      final days = [DateTime(2026, 1, 10), DateTime(2026, 3, 6), DateTime(2026, 3, 5)];
      expect(anchorCandidate(days, s), DateTime(2026, 3, 5));
    });
    test('sıfırlama sonrası gün yoksa null', () {
      final s = CycleSettings(birthDate: birth);
      expect(anchorCandidate([DateTime(2026, 1, 10)], s), isNull);
      expect(anchorCandidate(const [], s), isNull);
    });
    test('sıfırlama yoksa en eski gün (saat atılır)', () {
      expect(
          anchorCandidate(
              [DateTime(2026, 5, 3, 14), DateTime(2026, 5, 1, 9)], const CycleSettings()),
          DateTime(2026, 5, 1));
    });
  });

  group('anchorPatchForAdjust (düzenleme takvimi kaydı)', () {
    test('doğum öncesi geçmişi olan kullanıcı: çapa sıfırlama sonrası en eski gün, mod KORUNUR',
        () {
      final s = CycleSettings(
          birthDate: birth, lifecycleMode: CycleLifecycleMode.postpartum);
      final patch = anchorPatchForAdjust(
        marked: {DateTime(2026, 1, 10), DateTime(2026, 1, 11), DateTime(2026, 3, 5)},
        settings: s,
      );
      expect(patch, isNotNull);
      expect(patch!['first_period_date'], '2026-03-05');
      expect(patch['lifecycle_mode'], 'postpartum',
          reason: 'örtük tracking geçişi olmasın');
    });

    test('sıfırlama sonrası işaretli gün yoksa yama YOK (çapa değişmez)', () {
      final s = CycleSettings(
          birthDate: birth,
          firstPeriodDate: null,
          lifecycleMode: CycleLifecycleMode.postpartum);
      expect(anchorPatchForAdjust(marked: {DateTime(2026, 1, 10)}, settings: s), isNull);
      expect(anchorPatchForAdjust(marked: const {}, settings: s), isNull);
    });

    test('aday mevcut çapayla aynıysa yama yok', () {
      final s = CycleSettings(firstPeriodDate: DateTime(2026, 5, 1));
      expect(
          anchorPatchForAdjust(
              marked: {DateTime(2026, 5, 1), DateTime(2026, 5, 2)}, settings: s),
          isNull);
    });

    test('kayıp modunda da mod korunur', () {
      final s = CycleSettings(
          lastLossDate: DateTime(2026, 4, 1), lifecycleMode: CycleLifecycleMode.loss);
      final patch = anchorPatchForAdjust(marked: {DateTime(2026, 5, 2)}, settings: s);
      expect(patch!['lifecycle_mode'], 'loss');
      expect(patch['first_period_date'], '2026-05-02');
    });
  });
}
