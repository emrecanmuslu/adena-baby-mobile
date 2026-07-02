import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_pregnancy_bridge.dart';

/// Gebelik köprüsü (F4) saf matematik testleri — LMP'den gebelik haftası + TDT.
/// Naegele: TDT = son adet (LMP) + 280 gün. Hafta = LMP'den tamamlanan hafta.
void main() {
  group('pregnancyFromLmp (Naegele)', () {
    test('LMP 20 Haz, bugün 2 Tem → 1 hafta 5 gün + TDT = LMP+280g', () {
      final lmp = DateTime(2026, 6, 20);
      final info = pregnancyFromLmp(lmp, today: DateTime(2026, 7, 2));
      expect(info, isNotNull);
      expect(info!.weeks, 1);
      expect(info.days, 5); // 12 gün = 1 hafta 5 gün
      expect(info.dueDate, lmp.add(const Duration(days: 280)));
    });

    test('tam 40 hafta (280 gün) → hafta 40, gün 0', () {
      final lmp = DateTime(2026, 1, 1);
      final info =
          pregnancyFromLmp(lmp, today: lmp.add(const Duration(days: 280)));
      expect(info!.weeks, 40);
      expect(info.days, 0);
    });

    test('LMP null → null', () {
      expect(pregnancyFromLmp(null), isNull);
    });

    test('gelecekte LMP veya makul aralık dışı → null', () {
      final lmp = DateTime(2026, 6, 20);
      // Bugün LMP\'den önce (negatif) → null.
      expect(pregnancyFromLmp(lmp, today: DateTime(2026, 6, 10)), isNull);
      // 300 günden fazla → null (gebelik aralığı dışı).
      expect(
          pregnancyFromLmp(lmp, today: lmp.add(const Duration(days: 320))),
          isNull);
    });
  });
}
