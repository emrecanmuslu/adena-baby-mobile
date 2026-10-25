import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/features/cycle/cycle_entry_sheet.dart';
import 'package:adena_baby/features/cycle/cycle_setup_screen.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

class _MockRepo extends Mock implements CycleRepository {}

/// ADET-INCELEME A3 + B5 — kayıt sayfası: doğum+43..56 günde loşia rengi
/// seçilmeden akış girilirse "loşia mı, ilk adet mi?" sorulur; seçime göre
/// kaydedilir. Loşia rengi alanı doğum sonrası 56 güne kadar her modda açık.
void main() {
  setUpAll(() => registerFallbackValue(CycleEntry(id: '', date: DateTime(2026))));

  late _MockRepo repo;
  final calls = <bool>[];
  setUp(() {
    repo = _MockRepo();
    calls.clear();
    when(() => repo.saveEntry(any(),
            confirmedFirstPeriod: any(named: 'confirmedFirstPeriod')))
        .thenAnswer((inv) async {
      calls.add(inv.namedArguments[#confirmedFirstPeriod] as bool);
      return inv.positionalArguments.first as CycleEntry;
    });
  });

  Future<void> open(WidgetTester t, {required int birthDaysAgo}) async {
    final settings = CycleSettings(
      birthDate: dayOffset(-birthDaysAgo),
      breastfeeding: Breastfeeding.none,
      lifecycleMode: CycleLifecycleMode.postpartum,
      predictionsHidden: true,
    );
    await pumpCycleScreen(t,
        Consumer(builder: (context, ref, _) => TextButton(
            onPressed: () => showCycleEntrySheet(context, ref),
            child: const Text('AÇ'))),
        settings: settings,
        overrides: [cycleRepositoryProvider.overrideWithValue(repo)]);
    await t.tap(find.text('AÇ'));
    await t.pumpAndSettle();
  }

  testWidgets('doğum+50: loşia rengi alanı açık; akış → soru → "İlk âdetim"',
      (t) async {
    await open(t, birthDaysAgo: 50);
    expect(textHas('LOHUSALIK KANAMASI RENGİ'), findsOneWidget);
    await t.tap(find.text('Orta'));
    await t.pump();
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    expect(textHas('Bu loşia (lohusa kanaması) mı, ilk âdetin mi?'), findsOneWidget);
    await t.tap(find.text('İlk âdetim'));
    await t.pumpAndSettle();
    expect(calls, [true]);
  });

  testWidgets('doğum+50: "Loşia" seçilirse onaysız kaydedilir', (t) async {
    await open(t, birthDaysAgo: 50);
    await t.tap(find.text('Orta'));
    await t.pump();
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    await t.tap(find.text('Loşia'));
    await t.pumpAndSettle();
    expect(calls, [false]);
  });

  testWidgets('doğum+20: soru sorulmaz, onaysız (loşia) kaydedilir', (t) async {
    await open(t, birthDaysAgo: 20);
    await t.tap(find.text('Orta'));
    await t.pump();
    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    expect(textHas('ilk âdetin mi?'), findsNothing);
    expect(calls, [false]);
  });

  testWidgets('loşia ekranı: süre metni + 6 hafta sonrası hekim notu', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
          birthDate: dayOffset(-50),
          breastfeeding: Breastfeeding.none,
          lifecycleMode: CycleLifecycleMode.postpartum,
          predictionsHidden: true,
        ),
        entries: [
          CycleEntry(id: 'l', date: dayOffset(-1), lochiaColor: LochiaColor.brown),
        ]);
    expect(textHas('0–6 hafta'), findsNothing);
    expect(textHas('8 haftaya uzayabilir'), findsWidgets);
    expect(textHas('hekimine söyle'), findsOneWidget);
  });

  testWidgets('kurulum adım 1: loşia süresi "4–6 hafta, 8 haftaya uzayabilir"',
      (t) async {
    await pumpCycleScreen(t,
        CycleSetupView(
            initial: const CycleSettings(),
            babyBirthDate: DateTime(2026, 8, 1),
            onDone: () {}),
        settings: const CycleSettings());
    expect(textHas('~6 hafta'), findsNothing);
    expect(textHas('8 haftaya uzayabilir'), findsOneWidget);
  });
}
