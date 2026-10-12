import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/exact_alarm_prompt.dart';
import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/core/modal_gate.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/features/health/medication_widgets.dart';
import 'package:adena_baby/models/medication_plan.dart';

/// İlaç v2 (M14): plan bu cihaza senkronla gelse de (planı oluşturan cihaz
/// değil) ana sayfanın ilaç bölümü kesin alarm açıklamasını BİR KEZ gösterir;
/// öncelikli bir modal (paywall/tur) kapıyı tutarken göstermez.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  late int shown;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetMedExactPromptForTest();
    ModalGate.resetForTest();
    shown = 0;
    medExactPromptFactory = (ref) => ExactAlarmPrompt(
          isAndroid: true,
          canSchedule: () async => false,
          request: () async {
            shown++;
            return false;
          },
        );
  });

  Future<void> pump(WidgetTester tester, MedicationDay day) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [medicationDayProvider('b1').overrideWithValue(day)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: SingleChildScrollView(child: MedHomeSection(babyId: 'b1'))),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  MedicationDay dayWithPlan() => medicationDay([
        MedicationPlan(
            id: 1, uuid: 'u1', name: 'D vitamini', dose: '', times: const ['09:00'],
            active: true, createdAt: DateTime(2026, 1, 1)),
      ], const [], now: DateTime(2026, 1, 2, 8));

  testWidgets('planlı doz varsa açıklama bir kez gösterilir; izin ver → sistem isteği', (t) async {
    await pump(t, dayWithPlan());
    expect(find.text('Tam zamanında bildirim'), findsOneWidget);
    await t.tap(find.text('İzin ver'));
    await t.pumpAndSettle();
    expect(shown, 1);
    // Aynı oturumda tekrar çizilse de yeniden sorulmaz.
    await pump(t, dayWithPlan());
    expect(find.text('Tam zamanında bildirim'), findsNothing);
  });

  testWidgets('öncelikli modal kapıyı tutarken gösterilmez', (t) async {
    ModalGate.acquire();
    await pump(t, dayWithPlan());
    expect(find.text('Tam zamanında bildirim'), findsNothing);
    ModalGate.release();
  });

  testWidgets('planı olmayan bebekte gösterilmez', (t) async {
    await pump(t, medicationDay(const [], const [], now: DateTime(2026, 1, 2, 8)));
    expect(find.text('Tam zamanında bildirim'), findsNothing);
  });
}
