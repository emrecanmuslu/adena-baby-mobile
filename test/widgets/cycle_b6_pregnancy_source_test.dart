import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/age.dart';
import 'package:adena_baby/core/dates.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME B6: adet modülünün "gebelik" ekranı haftayı ve tahmini doğum
/// tarihini ana gebelik modülüyle AYNI kaynaktan (Baby.dueDate, TDT−280) okur;
/// TDT ultrasonla düzeltilince iki ekran aynı haftayı gösterir.
void main() {
  testWidgets('TDT ultrasonla düzeltildi → hafta TDT\'den (SAT\'tan değil)', (t) async {
    // SAT 70 gün önce → SAT'a göre 10. hafta. Ultrason TDT'yi bugün+196'ya
    // çekti → 84 gün = 12. hafta (ana modül).
    final due = dayOffset(196);
    final baby = Baby(
        id: 'b1', name: 'Bebek', status: BabyStatus.expecting, dueDate: due);
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
          firstPeriodDate: dayOffset(-70),
          breastfeeding: Breastfeeding.none,
          lifecycleMode: CycleLifecycleMode.pregnant,
          babyId: 'b1',
        ),
        babies: [baby]);
    expect(pregnancyWeeks(due), 12);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('10'), findsNothing);
    expect(textHas(fmtDayMonthYear(due)), findsOneWidget);
    expect(textHas('son âdetinden hesaplanır'), findsNothing);
  });

  testWidgets('bebek yoksa SAT\'tan hesaplanır (eski davranış)', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
          firstPeriodDate: dayOffset(-70),
          breastfeeding: Breastfeeding.none,
          lifecycleMode: CycleLifecycleMode.pregnant,
        ));
    expect(find.text('10'), findsOneWidget);
    expect(textHas('son âdetinden hesaplanır'), findsOneWidget);
  });
}
