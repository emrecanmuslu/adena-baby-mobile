import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/features/records/record_form.dart';
import 'package:adena_baby/models/record.dart';

/// ILAC-INCELEME-2 V34 / M15: zaman akışından plan kaynaklı (kimlikli) doz
/// kaydı düzenlenirken ad ve doz KİLİTLİ (plan ekranından yönetilir); elle
/// girilmiş (kimliksiz) ilaç kaydında ad alanı düzenlenebilir.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<void> open(WidgetTester t, Record existing) async {
    t.view.physicalSize = const Size(400, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showRecordForm(context, ref, 'b1', RecordType.medication, existing: existing),
                child: const Text('aç')),
          ),
        ),
      ),
    ));
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
  }

  testWidgets('plan kaydı: ad/doz kilitli, açıklama notu görünür', (t) async {
    await open(
        t,
        Record(id: 'r1', baby: 'b1', type: RecordType.medication, ts: DateTime(2026, 10, 12, 8, 3),
            data: const {
              'v': 2, 'name': 'Demir', 'dose': '1 ml', 'plan_uuid': 'u1', 'kind': 'scheduled',
              'dose_date': '2026-10-12', 'dose_time': '08:00', 'given': true,
            }));
    expect(
        find.text('Plan kaydı — adı ve dozu ilaç ekranından yönetilir; '
            'burada yalnız saati düzeltebilirsin.'),
        findsOneWidget);
    expect(find.text('Demir · 1 ml'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Demir'), findsNothing);
  });

  testWidgets('elle girilmiş (kimliksiz) ilaç kaydında ad düzenlenebilir', (t) async {
    await open(
        t,
        Record(id: 'r2', baby: 'b1', type: RecordType.medication, ts: DateTime(2026, 10, 12, 8, 3),
            data: const {'name': 'Demir', 'dose': '1 ml', 'given': true}));
    expect(find.textContaining('Plan kaydı'), findsNothing);
    expect(find.widgetWithText(TextField, 'Demir'), findsOneWidget);
  });
}
