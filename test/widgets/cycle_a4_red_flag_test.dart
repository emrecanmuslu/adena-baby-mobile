import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/features/cycle/cycle_entry_sheet.dart';
import 'package:adena_baby/features/cycle/cycle_widgets.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

/// ADET-INCELEME A4 + C6 (karar S3) — kırmızı bayraklar iki kademe:
/// ACİL (beklemeden acil servis / 112) ve AYNI GÜN HEKİM. "Tanı değildir"
/// notu kalır; kayıt sayfasındaki bilgi butonu bu açıklamaya bağlı.
void main() {
  test('kademe: acil ve aynı gün listeleri, eski anahtar geriye uyumlu', () {
    expect(redFlagLevel(['rf_flood']), RedFlagLevel.urgent);
    expect(redFlagLevel(['rf_clot']), RedFlagLevel.urgent);
    expect(redFlagLevel(['rf_faint']), RedFlagLevel.urgent);
    expect(redFlagLevel(['rf_fever']), RedFlagLevel.sameDay);
    expect(redFlagLevel(['rf_odor']), RedFlagLevel.sameDay);
    expect(redFlagLevel(['rf_pain']), RedFlagLevel.sameDay);
    expect(redFlagLevel(['rf_rebleed']), RedFlagLevel.sameDay);
    expect(redFlagLevel(['rf_odor_fever']), RedFlagLevel.sameDay);
    expect(redFlagLevel(['rf_pain', 'rf_flood']), RedFlagLevel.urgent);
    expect(redFlagLevel(['cramp']), isNull);
    for (final k in ['rf_faint', 'rf_fever', 'rf_odor', 'rf_rebleed', 'rf_odor_fever']) {
      expect(redFlagSymptoms, contains(k));
    }
    expect(CycleInfo.redFlags, contains('112'));
    expect(CycleInfo.redFlags, contains('38°C'));
  });

  Future<void> openDialog(WidgetTester t, List<String> flags) async {
    await pumpCycleScreen(t,
        Builder(builder: (c) => TextButton(
            onPressed: () => showCycleRedFlag(c, flags), child: const Text('AÇ'))),
        settings: const CycleSettings());
    await t.tap(find.text('AÇ'));
    await t.pumpAndSettle();
  }

  testWidgets('acil belirti → beklemeden acil servis / 112', (t) async {
    await openDialog(t, ['rf_flood']);
    expect(textHas('112'), findsWidgets);
    expect(textHas('Beklemeden'), findsWidgets);
    expect(textHas('Bu bir tanı değil'), findsOneWidget);
  });

  testWidgets('aynı gün belirtisi → bugün hekim, 112 yok', (t) async {
    await openDialog(t, ['rf_fever']);
    expect(textHas('112'), findsNothing);
    expect(textHas('Bugün bir hekime başvurmanı öneririz'), findsOneWidget);
    expect(textHas('38°C ve üzeri ateş'), findsOneWidget);
  });

  testWidgets('kayıt sayfası: yeni bayrak çipleri listelenir', (t) async {
    await pumpCycleScreen(t,
        Consumer(builder: (context, ref, _) => TextButton(
            onPressed: () => showCycleEntrySheet(context, ref),
            child: const Text('AÇ'))),
        settings: const CycleSettings());
    await t.tap(find.text('AÇ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Belirtiler'));
    await t.pumpAndSettle();
    expect(textHas('baş dönmesi, bayılma hissi ya da çarpıntı'), findsOneWidget);
    expect(textHas('yeniden parlak kırmızı'), findsOneWidget);
  });
}
