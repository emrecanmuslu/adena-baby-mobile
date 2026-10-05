import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/features/health/medication_widgets.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

MedicationPlan _plan(int id, String name, List<String> times, {String dose = '3 damla'}) =>
    MedicationPlan(
        id: id, name: name, dose: dose, times: times, active: true, createdAt: DateTime(2026));

// createdBy null → "kim verdi" çözümü hiçbir provider'a dokunmaz.
Record _rec(String name, int h, int m) => Record(
      id: '$name-$h-$m',
      baby: 'b1',
      type: RecordType.medication,
      ts: DateTime(2026, 1, 1, h, m),
      data: {'name': name, 'given': true},
    );

final _plans = [
  _plan(1, 'D vitamini', ['09:00']),
  _plan(2, 'Demir şurubu', ['08:00', '20:00'], dose: '2,5 ml'),
  _plan(3, 'Probiyotik', ['12:00'], dose: '5 damla'),
];

/// Dar telefonda (320dp) kartı çizer; taşma (overflow) testi düşürür.
Future<void> _pump(WidgetTester tester, MedicationDay day,
    {TextDirection dir = TextDirection.ltr, bool dark = false}) async {
  tester.view.physicalSize = const Size(320, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Directionality(
        textDirection: dir,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MedSectionHeader(title: 'İlaç & Vitamin', day: day, onPlans: () {}),
                MedDayCard(babyId: 'b1', day: day),
                Wrap(children: [
                  for (final r in day.rows)
                    for (final d in r.doses) MedTimeChip(babyId: 'b1', dose: d),
                ]),
              ],
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // fmtTime ("Verildi · 09:12") intl tarih sembollerini ister.
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('saati geçmiş doz: şerit + satırlar + sayaç', (tester) async {
    final day = medicationDay(
        _plans, [_rec('D vitamini', 9, 12), _rec('Demir şurubu', 8, 5)],
        now: DateTime(2026, 1, 1, 14, 20));
    await _pump(tester, day);
    expect(find.text('2/4'), findsOneWidget);
    expect(find.text('1 dozun saati geçti — verdiysen dokun'), findsOneWidget);
    expect(find.text('Saati geçti · 12:00'), findsOneWidget);
    expect(find.text('Sıradaki · 20:00 · 1/2'), findsOneWidget);
    expect(find.text('Verildi · 09:12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saati geçen satırda "Atla"; atlanan doz "Atlandı" görünür', (tester) async {
    final skip = Record(
      id: 'skip',
      baby: 'b1',
      type: RecordType.medication,
      ts: DateTime(2026, 1, 1, 13),
      data: {'name': 'Probiyotik', 'given': false, 'skipped': true},
    );
    // Probiyotik atlandı; D vitamini (09:00) saati geçmiş, bekliyor.
    final day = medicationDay(_plans, [skip], now: DateTime(2026, 1, 1, 14, 20));
    await _pump(tester, day);
    expect(find.text('Atlandı · 12:00'), findsOneWidget);
    // Yalnız saati geçmiş iki satırda (D vitamini, Demir) "Atla" çıkar.
    expect(find.text('Atla'), findsNWidgets(2));
    expect(find.text('0/4'), findsOneWidget); // atlanan "verildi" sayılmaz
    expect(tester.takeException(), isNull);
  });

  testWidgets('verilen doza dokun → saat düzeltme sayfası; sıradakine uzun bas → atla seçeneği',
      (tester) async {
    final day = medicationDay(_plans, [_rec('Demir şurubu', 8, 5)],
        now: DateTime(2026, 1, 1, 8, 30));
    await _pump(tester, day);

    // Verilmiş 08:00 dozu (Demir şurubu satırının ilk düğmesi).
    final given = find.byWidgetPredicate(
        (w) => w is MedDoseButton && w.dose.isGiven && w.dose.time == '08:00');
    await tester.tap(given);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Demir şurubu · 08:00 dozu'), findsOneWidget);
    expect(find.text('VERİLDİĞİ SAAT'), findsOneWidget);
    expect(find.text('08:05'), findsOneWidget);
    expect(find.text('Kaydı geri al'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10)); // sayfayı kapat
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Sıradaki (D vitamini 09:00) → uzun bas.
    final next = find.byWidgetPredicate((w) =>
        w is MedDoseButton && w.dose.plan.name == 'D vitamini' && w.dose.time == '09:00');
    await tester.longPress(next);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('D vitamini · 09:00 dozu'), findsOneWidget);
    expect(find.text('Verildi olarak işaretle'), findsOneWidget);
    expect(find.text('Bu dozu atla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hepsi verildi → tek satır; dokununca açılır, "Daha az göster"', (tester) async {
    final day = medicationDay(
        _plans,
        [
          _rec('D vitamini', 9, 12),
          _rec('Demir şurubu', 8, 5),
          _rec('Demir şurubu', 20, 4),
          _rec('Probiyotik', 12, 4),
        ],
        now: DateTime(2026, 1, 1, 21, 10));
    await _pump(tester, day);
    expect(find.text('Bugünün dozları tamam'), findsOneWidget);
    expect(find.text('4/4 verildi · yarın ilk doz 08:00'), findsOneWidget);
    expect(find.byType(MedDoseButton), findsNothing);

    await tester.tap(find.text('Bugünün dozları tamam'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MedDoseButton), findsNWidgets(4));
    expect(find.text('Daha az göster'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5 plan: tamamlananlar "+N plan" satırında toplanır', (tester) async {
    final plans = [
      ..._plans,
      _plan(4, 'Multivitamin', ['10:00'], dose: '1 ölçek'),
      _plan(5, 'Gaz damlası', ['08:00', '14:00', '20:00'], dose: '10 damla'),
    ];
    final day = medicationDay(
        plans,
        [
          _rec('D vitamini', 9, 12),
          _rec('Probiyotik', 12, 4),
          _rec('Multivitamin', 10, 10),
          _rec('Demir şurubu', 8, 5),
          _rec('Gaz damlası', 8, 2),
          _rec('Gaz damlası', 14, 6),
        ],
        now: DateTime(2026, 1, 1, 17, 10));
    await _pump(tester, day);
    expect(find.text('+3 plan · bugün tamam'), findsOneWidget);
    expect(find.text('Multivitamin'), findsNothing);
    await tester.tap(find.text('+3 plan · bugün tamam'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Multivitamin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uzun ad + 4 doz (alt satıra geçer) + RTL + koyu tema taşmaz', (tester) async {
    final plans = [
      _plan(1, 'Vitamine D3 + K2 en gouttes (flacon bleu)', ['09:00'],
          dose: '3 gouttes après le biberon'),
      _plan(2, 'Sirop de fer', ['06:00', '10:00', '14:00', '20:00'], dose: '2,5 ml'),
      _plan(3, 'Probiotique', ['08:00', '14:00', '20:00'], dose: '5 gouttes'),
    ];
    final day = medicationDay(plans, [_rec('Sirop de fer', 6, 5)],
        now: DateTime(2026, 1, 1, 14, 20));
    await _pump(tester, day, dir: TextDirection.rtl, dark: true);
    expect(find.byType(MedDoseButton), findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });
}
