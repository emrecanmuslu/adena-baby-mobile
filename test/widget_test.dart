import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:adena_baby/core/ad_widgets.dart';
import 'package:adena_baby/core/brand.dart';
import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/features/splash/splash_screen.dart';

/// Açılış ekranı smoke testi. Tüm uygulamayı (Firebase/RevenueCat/router/ağ)
/// ayağa kaldırmak yerine gerçek SplashScreen'i izole pump eder; premium bayrağı
/// override ile sabitlenir (ağ/cache yok). Gerçek üretim UI'ını doğrular.
void main() {
  Widget harness({required bool premium}) => ProviderScope(
        overrides: [
          isPremiumProvider.overrideWithValue(premium),
        ],
        child: const MaterialApp(home: SplashScreen()),
      );

  testWidgets('Açılış ekranı logo + tagline gösterir', (tester) async {
    await tester.pumpWidget(harness(premium: false));
    await tester.pump(); // bir frame (sonsuz nokta animasyonunu beklemeden)

    // Amblem + kelime-logo (RichText) görünür.
    expect(find.byType(BrandEmblem), findsOneWidget);
    expect(find.byType(BrandWordmark), findsOneWidget);
    expect(find.byType(RichText), findsWidgets);

    // Tagline düz bir Text (varsayılan tr locale → kaynak metnin kendisi).
    expect(find.textContaining('Bir bebekle başladı'), findsOneWidget);
  });

  testWidgets('Premium değilken pro rozeti gösterilmez', (tester) async {
    await tester.pumpWidget(harness(premium: false));
    await tester.pump();
    expect(find.byType(AdProBadge), findsNothing);
  });

  testWidgets('Premium iken pro rozeti gösterilir', (tester) async {
    await tester.pumpWidget(harness(premium: true));
    await tester.pump();
    expect(find.byType(AdProBadge), findsOneWidget);
  });
}
