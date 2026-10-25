import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/onboarding/baby_setup_screen.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/user.dart';

class _SignedOut extends AuthController {
  @override
  Future<User?> build() async => null;
}

/// Bebek kurulum formu — onboarding'de hedef (doğdu/bekliyoruz) ara ekranda
/// seçilir, form içindeki "Bebek doğdu mu?" anahtarı gizli kalmalı.
void main() {
  setUp(() => I18n.instance.apply('tr', const {}));

  Future<void> pump(WidgetTester tester, BabyStatus? status) =>
      tester.pumpWidget(ProviderScope(
        overrides: [authControllerProvider.overrideWith(_SignedOut.new)],
        child: MaterialApp(
          home: BabySetupScreen(
              key: const ValueKey('setup'), initialStatus: status),
        ),
      ));

  testWidgets(
      'router yenilenip extra (initialStatus) kaybolsa da durum anahtarı belirmez',
      (tester) async {
    await pump(tester, BabyStatus.expecting);
    await tester.pump();
    expect(find.text('Bekleme odası 🤰'), findsOneWidget);
    expect(find.text('🎉 Doğdu'), findsNothing);

    // go_router refreshListenable sonrası aynı sayfa extra'sız yeniden kurulur.
    await pump(tester, null);
    await tester.pump();
    expect(find.text('🎉 Doğdu'), findsNothing,
        reason: 'form ortasında anahtar belirip düzeni kaydırmamalı');
    expect(find.text('Bekleme odası 🤰'), findsOneWidget,
        reason: 'seçilen hedef korunur');
  });

  testWidgets('hedef seçilmeden açılırsa (initialStatus yok) anahtar görünür',
      (tester) async {
    await pump(tester, null);
    await tester.pump();
    expect(find.text('🎉 Doğdu'), findsOneWidget);
  });
}
