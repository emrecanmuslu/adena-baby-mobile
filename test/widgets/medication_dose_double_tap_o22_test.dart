import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/features/health/medication_widgets.dart';
import 'package:adena_baby/features/records/record_controller.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

class _MockActions extends Mock implements RecordActions {}

/// O22 — sıradaki doza hızlı çift dokunuş tek "verildi" kaydı üretir.
void main() {
  setUpAll(() {
    initializeDateFormatting('tr_TR');
    registerFallbackValue(Record(
        id: 'x', baby: 'b', type: RecordType.medication, ts: DateTime(2026), data: const {}));
  });

  testWidgets('aynı doza iki dokunuş → upsertQuiet bir kez', (tester) async {
    final actions = _MockActions();
    when(() => actions.upsertQuiet(any())).thenAnswer((_) async {});
    final plan = MedicationPlan(
        id: 41, name: 'D vitamini', dose: '1 damla', times: const ['20:00'],
        active: true, createdAt: DateTime(2026));
    final day = medicationDay([plan], const [], now: DateTime(2026, 1, 1, 14));
    final dose = day.rows.single.doses.single;
    expect(dose.role, MedicationDoseRole.next);

    await tester.pumpWidget(ProviderScope(
      overrides: [recordActionsProvider.overrideWithValue(actions)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: MedTimeChip(babyId: 'b1', dose: dose))),
      ),
    ));
    await tester.pump();

    final chip = find.byType(MedTimeChip);
    await tester.tap(chip);
    await tester.tap(chip); // akış henüz güncellenmedi, aynı dose nesnesi
    await tester.pump();
    verify(() => actions.upsertQuiet(any())).called(1);

    // Koruma süresi dolunca (akış artık güncellenmiş olur) yeniden dokunulabilir.
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(chip);
    await tester.pump();
    verify(() => actions.upsertQuiet(any())).called(1);
    await tester.pump(const Duration(seconds: 5));
  });
}
