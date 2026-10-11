import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_dial.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME D1: iyileşme/gebelik halkasında yay ve "bugün" boncuğu AYNI
/// ölçekte (iyileşme /42 gün, gebelik /40 hafta); boncuk 28 günlük döngü
/// formülüyle hesaplanmıyor.
void main() {
  test('heal açısı: yay ve boncuk aynı ölçek, 360°de kırpılır', () {
    expect(dialHealDegrees(21, 42), closeTo(180, 1e-9));
    expect(dialHealDegrees(20, 40), closeTo(180, 1e-9));
    expect(dialHealDegrees(60, 42), 360);
    expect(dialHealDegrees(0, 42), 0);
  });

  testWidgets('loşia halkası /42', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
            birthDate: dayOffset(-30),
            breastfeeding: Breastfeeding.none,
            lifecycleMode: CycleLifecycleMode.postpartum,
            predictionsHidden: true));
    expect(t.widget<CycleDial>(find.byType(CycleDial)).healSpan, 42);
  });

  testWidgets('gebelik halkası /40', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
            firstPeriodDate: dayOffset(-70),
            breastfeeding: Breastfeeding.none,
            lifecycleMode: CycleLifecycleMode.pregnant));
    expect(t.widget<CycleDial>(find.byType(CycleDial)).healSpan, 40);
  });
}
