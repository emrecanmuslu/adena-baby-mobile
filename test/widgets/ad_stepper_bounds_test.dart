import 'package:adena_baby/core/ad_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// AdStepper min/max sınırı (gebelik haftası gibi alanlarda kafasına göre değer
/// girilememeli).
void main() {
  Widget wrap(TextEditingController c, {double? min, double? max}) => MaterialApp(
        home: Scaffold(
          body: AdStepper(controller: c, unit: 'hf', min: min, max: max),
        ),
      );

  testWidgets('+ butonu üst sınırı (max) aşmaz', (tester) async {
    final c = TextEditingController(text: '40');
    await tester.pumpWidget(wrap(c, min: 22, max: 41));
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(c.text, '41');
    await tester.tap(find.text('+')); // 41'de takılı kalmalı
    await tester.pump();
    expect(c.text, '41');
  });

  testWidgets('− butonu alt sınırın (min) altına inmez', (tester) async {
    final c = TextEditingController(text: '23');
    await tester.pumpWidget(wrap(c, min: 22, max: 41));
    await tester.tap(find.text('−'));
    await tester.pump();
    expect(c.text, '22');
    await tester.tap(find.text('−')); // 22'de takılı
    await tester.pump();
    expect(c.text, '22');
  });

  testWidgets('klavyeden max üstü değer reddedilir', (tester) async {
    final c = TextEditingController(text: '30');
    await tester.pumpWidget(wrap(c, min: 22, max: 41));
    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();
    // 99 > 41 → reddedildi (eski değer korunur, 99 yazılmaz)
    expect(c.text == '99', isFalse);
    final v = int.tryParse(c.text);
    if (v != null) expect(v <= 41, isTrue);
  });

  testWidgets('odak kaybında alt sınıra çekilir', (tester) async {
    final c = TextEditingController(text: '30');
    await tester.pumpWidget(wrap(c, min: 22, max: 41));
    await tester.tap(find.byType(TextField)); // odaklan
    await tester.pump();
    await tester.enterText(find.byType(TextField), '5'); // min altı
    await tester.pump();
    // başka yere dokun → odak kaybı → 22'ye çekilmeli
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(c.text, '22');
  });
}
