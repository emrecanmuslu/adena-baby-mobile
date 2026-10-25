import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_calendar_screen.dart';
import 'package:adena_baby/features/cycle/cycle_settings_screen.dart';
import 'package:adena_baby/features/cycle/cycle_setup_screen.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME A1 + C5 — adet takvimi doğum kontrol yöntemi değildir:
/// gebe kalma olasılığı yalnız TTC'de; TTC'de kalıcı "korunma için
/// kullanılamaz" notu; TTC dışında doğurganlık kartı nötr.
void main() {
  const noContra = 'Bu bir tahmindir; gebelikten korunma için kullanılamaz.';
  const disclaimer =
      'Âdet takvimi tahmine dayalıdır ve bir doğum kontrol yöntemi değildir.';

  // 28 günlük düzenli döngü; bugün 15. gün = tahmini ovülasyon.
  CycleSettings base(
          {CycleLifecycleMode mode = CycleLifecycleMode.tracking, int anchor = -98}) =>
      CycleSettings(
        firstPeriodDate: dayOffset(anchor),
        breastfeeding: Breastfeeding.none,
        lifecycleMode: mode,
      );
  final ovuEntries = periodEntries([-98, -70, -42, -14]);
  // Aynı döngüde bugün 11. gün = pencere içi (ov−4).
  final fertileEntries = periodEntries([-94, -66, -38, -10]);

  testWidgets('takvim: TTC dışında gebe kalma olasılığı satırı yok', (t) async {
    await pumpCycleScreen(t, const CycleCalendarScreen(),
        settings: base(), entries: ovuEntries);
    expect(textHas('Gebe kalma olasılığı'), findsNothing);
  });

  testWidgets('takvim: TTC\'de olasılık + korunma notu', (t) async {
    await pumpCycleScreen(t, const CycleCalendarScreen(),
        settings: base(mode: CycleLifecycleMode.ttc), entries: ovuEntries);
    expect(textHas('Gebe kalma olasılığı'), findsOneWidget);
    expect(textHas(noContra), findsWidgets);
  });

  testWidgets('bugün: TTC dışında ovülasyon kartı nötr + korunma notu', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: base(), entries: ovuEntries);
    expect(textHas('Bugün gebelik şansı en yüksek dönemde'), findsNothing);
    expect(textHas('Doğurgan pencere (tahmini)'), findsWidgets);
    expect(textHas(noContra), findsWidgets);
  });

  testWidgets('bugün: TTC\'de gebelik şansı metni + olasılık altında not', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: base(mode: CycleLifecycleMode.ttc), entries: ovuEntries);
    expect(textHas('Bugün gebelik şansı en yüksek dönemde'), findsOneWidget);
    expect(textHas('Çok yüksek'), findsOneWidget);
    expect(textHas(noContra), findsWidgets);
  });

  testWidgets('bugün: TTC dışında doğurgan pencere notu nötr', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: base(anchor: -94), entries: fertileEntries);
    expect(textHas('gebelik şansı artıyor'), findsNothing);
    expect(textHas('Doğurgan pencere (tahmini)'), findsWidgets);
    expect(textHas(noContra), findsWidgets);
  });

  testWidgets('âdet ayarları: kalıcı doğum kontrolü uyarı satırı', (t) async {
    await pumpCycleScreen(t, const CycleSettingsScreen(), settings: base());
    expect(textHas(disclaimer), findsOneWidget);
  });

  testWidgets('kurulumun son adımı: doğum kontrolü uyarısı', (t) async {
    await pumpCycleScreen(t,
        CycleSetupView(initial: const CycleSettings(), onDone: () {}, cycleFirst: true),
        settings: const CycleSettings());
    await t.tap(find.text('Devam'));
    await t.pump(const Duration(milliseconds: 50));
    expect(textHas(disclaimer), findsOneWidget);
  });
}
