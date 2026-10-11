import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME §6 S12 (senaryo K1): "ovülasyon ~2 hafta içinde dönebilir"
/// bilgisi ERKEN kayıplar için geçerli — ifade buna göre daraltıldı.
void main() {
  testWidgets('kayıp ekranı: "Erken kayıplarda" ifadesi', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
            lastLossDate: dayOffset(-14),
            breastfeeding: Breastfeeding.none,
            lifecycleMode: CycleLifecycleMode.loss,
            predictionsHidden: true));
    expect(textHas('Erken kayıplarda ovülasyon genellikle ~2 hafta içinde dönebilir'),
        findsOneWidget);
  });
}
