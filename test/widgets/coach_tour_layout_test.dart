import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/coach_tour.dart';
import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/theme.dart';

/// Tanıtım turu balonu — her koşulda ekrana sığmalı: dar ekran, büyük yazı,
/// uzun (çevrilmiş) metin, hedef ekranın altında/üstünde ya da çok büyük.
/// Flutter'da taşma testte hata olarak yüzeye çıkar.
void main() {
  setUp(() => I18n.instance.apply('tr', const {}));

  final long = List.filled(6, 'Réorganisez les cartes avec le crayon ;').join(' ');

  Future<void> run(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    required double targetTop,
    required double targetHeight,
    String finalLabel = 'Ajouter la première entrée',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            top: targetTop,
            left: 20,
            right: 20,
            height: targetHeight,
            child: Container(key: key, color: Colors.white),
          ),
          Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showCoachTour(ctx,
                    steps: [CoachStep('Organisez à votre façon', long, [key])],
                    finalLabel: finalLabel),
                child: const Text('go'),
              ),
            ),
          ),
        ]),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    final screen = Offset.zero & size;
    final bubble = tester.getRect(find.byType(Semantics).hitTestable().first);
    expect(find.text('Organisez à votre façon'), findsOneWidget);
    // Başlık ve ana düğme görünür alanda (kesilmemiş).
    for (final f in [find.text('Organisez à votre façon'), find.text(finalLabel)]) {
      final r = tester.getRect(f);
      expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(1, 1)),
          isTrue, reason: '$f ekran dışında: $r (bubble $bubble)');
    }
  }

  for (final s in const [Size(320, 568), Size(390, 844)]) {
    for (final scale in const [1.0, 1.3, 1.6]) {
      testWidgets('hedef altta · ${s.width.toInt()}w · ×$scale', (t) async {
        await run(t, size: s, textScale: scale, targetTop: s.height - 140, targetHeight: 80);
      });
      testWidgets('hedef üstte · ${s.width.toInt()}w · ×$scale', (t) async {
        await run(t, size: s, textScale: scale, targetTop: 60, targetHeight: 80);
      });
      testWidgets('dev hedef · ${s.width.toInt()}w · ×$scale', (t) async {
        await run(t, size: s, textScale: scale, targetTop: 40, targetHeight: s.height - 120);
      });
    }
  }
}
