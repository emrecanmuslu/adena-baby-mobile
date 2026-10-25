import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/features/cycle/cycle_widgets.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME B4 (karar S2): "durup koyulaşıp 4–7 gün sürerse muhtemelen
/// ilk adettir" yerine dengeli cümle + yeniden parlak kırmızı kanamada hekim.
void main() {
  const fresh = 'Kanama kesildikten sonra başlayan ve 4–7 gün süren düzenli bir '
      'kanama ilk âdetin olabilir. Yeniden parlak kırmızı ve yoğunlaşan '
      'kanamada hekimine başvur.';

  test('bilgi metni dengeli cümleyi taşır', () {
    expect(CycleInfo.lochiaVsPeriod, contains(fresh));
    expect(CycleInfo.lochiaVsPeriod, isNot(contains('muhtemelen ilk âdettir')));
  });

  testWidgets('loşia ekranı dengeli cümleyi gösterir', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
          birthDate: dayOffset(-10),
          breastfeeding: Breastfeeding.exclusive,
          lifecycleMode: CycleLifecycleMode.postpartum,
          predictionsHidden: true,
        ));
    expect(textHas(fresh), findsOneWidget);
    expect(textHas('muhtemelen ilk âdettir'), findsNothing);
  });
}
