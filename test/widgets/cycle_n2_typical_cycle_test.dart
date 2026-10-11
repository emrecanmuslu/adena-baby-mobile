import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/ad_widgets.dart';
import 'package:adena_baby/features/cycle/cycle_stats_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// Düzeltme turu 2 — N2: istatistikteki döngü değeri artık MEDYAN (B1) →
/// etiket "Ort. döngü" değil "Tipik döngü"; bilgi butonu medyanı açıklar.
void main() {
  testWidgets('istatistik: "Tipik döngü" + ortanca açıklaması', (t) async {
    await pumpCycleScreen(t, const CycleStatsScreen(),
        settings: CycleSettings(
            firstPeriodDate: dayOffset(-104), breastfeeding: Breastfeeding.none),
        entries: periodEntries([-104, -76, -48, -20]));
    expect(textHas('TİPİK DÖNGÜ'), findsOneWidget);
    expect(textHas('ORT. DÖNGÜ'), findsNothing);
    final dots = t.widgetList<AdInfoDot>(find.byType(AdInfoDot));
    expect(
        dots.any((d) => d.body.toLowerCase().contains('son döngülerin ortanca değeri') &&
            d.body.contains('tek seferlik uzun döngüler hesabı bozmaz')),
        isTrue);
  });
}
