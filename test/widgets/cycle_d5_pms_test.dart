import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME D5: geri sayım mini kartı "PMS olası" → "PMS belirtileri olabilir".
void main() {
  testWidgets('geri sayımda "PMS belirtileri olabilir"', (t) async {
    // 28 günlük döngü, bugün 24. gün → 4 gün kaldı (geri sayım).
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
            firstPeriodDate: dayOffset(-107), breastfeeding: Breastfeeding.none),
        entries: periodEntries([-107, -79, -51, -23]));
    expect(textHas('PMS BELİRTİLERİ OLABİLİR'), findsOneWidget);
    expect(textHas('PMS OLASI'), findsNothing);
  });
}
