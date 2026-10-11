import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_guidance.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME C4 (karar S11): TTC'de ilişki sıklığı ipucu, folik asit kartı,
/// LH/servikal mukus notu; ttcStartedAt'tan 6. ayda "35 yaş ve üzerindeysen",
/// 12. ayda "bir yıldır (35 yaş üstünde 6 aydır)" hekim önerisi.
void main() {
  const year = 'Bir yıldır (35 yaş üstünde 6 aydır) deniyorsan hekimine danışmanı öneririz';
  const six = '35 yaş ve üzerindeysen ve 6 aydır deniyorsan hekimine danışmanı öneririz';

  test('ttcMonths: takvim ayı', () {
    final s = CycleSettings(ttcStartedAt: DateTime(2025, 10, 12));
    expect(ttcMonths(s, today: DateTime(2026, 10, 11)), 11);
    expect(ttcMonths(s, today: DateTime(2026, 10, 12)), 12);
    expect(ttcMonths(const CycleSettings(), today: DateTime(2026, 10, 11)), isNull);
  });

  CycleSettings ttc(int startedDaysAgo) => CycleSettings(
        firstPeriodDate: dayOffset(-104),
        breastfeeding: Breastfeeding.none,
        lifecycleMode: CycleLifecycleMode.ttc,
        ttcStartedAt: dayOffset(-startedDaysAgo),
      );
  final entries = periodEntries([-104, -76, -48, -20]);

  testWidgets('TTC: ipuçları her zaman; 2. ayda hekim kartı yok', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(), settings: ttc(60), entries: entries);
    expect(textHas('Doğurgan pencerede 1–2 günde bir ilişki önerilir'), findsOneWidget);
    expect(textHas('400 mikrogram folik asit'), findsOneWidget);
    expect(textHas('Ovülasyon testleri (LH) ve servikal mukus'), findsOneWidget);
    expect(textHas(year), findsNothing);
    expect(textHas(six), findsNothing);
  });

  testWidgets('TTC 7. ay: 35 yaş notu', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(), settings: ttc(215), entries: entries);
    expect(textHas(six), findsOneWidget);
    expect(textHas(year), findsNothing);
  });

  testWidgets('TTC 13. ay: bir yıl notu', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(), settings: ttc(400), entries: entries);
    expect(textHas(year), findsOneWidget);
  });

  testWidgets('TTC dışında ipuçları yok', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: ttc(400).copyWith(lifecycleMode: CycleLifecycleMode.tracking),
        entries: entries);
    expect(textHas('folik asit'), findsNothing);
    expect(textHas(year), findsNothing);
  });
}
