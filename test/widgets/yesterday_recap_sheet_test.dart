import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/core/units.dart';
import 'package:adena_baby/core/yesterday_recap.dart';
import 'package:adena_baby/features/babies/family_settings.dart';
import 'package:adena_baby/features/home/yesterday_recap_sheet.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

final _day = DateTime(2026, 10, 4);
var _n = 0;

Record _r(RecordType t, int h, int m, Map<String, dynamic> data, {int day = 0}) => Record(
    id: 'r${_n++}',
    baby: 'b1',
    type: t,
    ts: _day.add(Duration(days: day, hours: h, minutes: m)),
    data: data);

Record _sleep(int day, int h, int m, int dur) => _r(RecordType.sleep, h, m, {
      'start_ts': _day.add(Duration(days: day, hours: h, minutes: m)).toUtc().toIso8601String(),
      'duration': dur,
    }, day: day);

/// Dolu bir gün: 3 katmanlı şerit, ilaç eksik, karşılaştırmalı uyku.
YesterdayRecap _rich() => buildYesterdayRecap(
      day: _day,
      history: [
        for (var d = -5; d <= -1; d++) ...[_sleep(d, 20, 0, 240), _sleep(d, 13, 0, 60)],
        _sleep(0, 0, 25, 290),
        _sleep(0, 9, 20, 80),
        _sleep(0, 13, 0, 90),
        _sleep(0, 22, 0, 240),
        for (final h in [0, 5, 8, 11, 14, 17, 19, 21])
          _r(RecordType.feed, h, 10, {'sub': 'breast', 'left_min': 7, 'right_min': 6}),
        _r(RecordType.diaper, 5, 45, {'sub': 'pee'}),
        _r(RecordType.diaper, 8, 10, {'sub': 'poo', 'stool': 'sarı, yumuşak'}),
        _r(RecordType.diaper, 14, 10, {'sub': 'poopee'}),
        _r(RecordType.medication, 8, 5, {'name': 'Demir şurubu', 'given': true}),
        _r(RecordType.appointment, 10, 30, {'title': '6. ay kontrolü'}, day: 1),
      ],
      plans: [
        MedicationPlan(
            id: 1,
            name: 'Demir şurubu',
            dose: '2,5 ml',
            times: const ['08:00', '20:00'],
            active: true,
            createdAt: DateTime(2026, 9, 1)),
      ],
    )!;

Future<void> _open(WidgetTester tester, YesterdayRecap recap,
    {TextDirection dir = TextDirection.ltr, bool dark = false}) async {
  tester.view.physicalSize = const Size(320, 640); // küçük telefon
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  AppColors.brightness = dark ? Brightness.dark : Brightness.light;
  addTearDown(() => AppColors.brightness = Brightness.light);
  await tester.pumpWidget(ProviderScope(
    overrides: [activeUnitsProvider.overrideWithValue(const Units())],
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (_, child) => Directionality(textDirection: dir, child: child!),
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: TextButton(
              onPressed: () => showYesterdayRecap(context, ref,
                  const Baby(id: 'b1', name: 'Defne'), (recap: recap, family: const [])),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1500)); // giriş animasyonu bitsin
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('dolu gün: başlık, şerit lejantı, öne çıkanlar, randevu, "Güne başla"',
      (tester) async {
    await _open(tester, _rich());
    expect(find.text('Defne dün 4 sa 50 dk aralıksız uyudu'), findsOneWidget);
    expect(find.text('DÜN · 4 EKİM PAZAR'), findsOneWidget);
    expect(find.text('En uzun · 4 sa 50 dk'), findsOneWidget);
    expect(find.text('8 beslenme'), findsOneWidget);
    expect(find.text('3 bez'), findsOneWidget);
    // İlaç: eksik doz "verilmedi" değil "kayıtlı değil" + ekle bağlantısı.
    expect(find.text('Demir şurubu · 1/2 doz'), findsOneWidget);
    expect(find.textContaining('20:00 dozu kayıtlı değil.', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('Verdiysen ekle', findRichText: true), findsOneWidget);
    expect(find.text('Bugün 10:30 · 6. ay kontrolü'), findsOneWidget);
    expect(find.text('Güne başla'), findsOneWidget);
    // Hiçbir yerde "0" yazmaz.
    expect(find.textContaining(RegExp(r'^0 ')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Güne başla'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Güne başla'), findsNothing);
  });

  testWidgets('tek kategori (yalnız uyku) + az veri notu', (tester) async {
    final recap = buildYesterdayRecap(
        day: _day, history: [_sleep(0, 20, 0, 200), _sleep(0, 13, 0, 50)])!;
    await _open(tester, recap);
    expect(find.text('Defne dün toplam 4 sa 10 dk uyudu'), findsOneWidget);
    expect(find.textContaining('beslenme'), findsNothing);
    expect(find.textContaining('bez'), findsNothing);
    expect(find.textContaining('Birkaç gün kayıt girdikçe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('koyu tema + RTL taşmaz', (tester) async {
    await _open(tester, _rich(), dir: TextDirection.rtl, dark: true);
    expect(find.text('Güne başla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
