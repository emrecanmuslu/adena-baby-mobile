import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:adena_baby/main.dart';

void main() {
  testWidgets('Açılış ekranı logo + tagline gösterir', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AdenaApp()));
    // Tagline düz bir Text widget'ı
    expect(find.textContaining('Bir bebekle başladı'), findsOneWidget);
    // Logo bir RichText
    expect(find.byType(RichText), findsWidgets);
  });
}
