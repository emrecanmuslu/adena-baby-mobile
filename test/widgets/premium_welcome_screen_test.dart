import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/features/onboarding/premium_welcome_screen.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/pricing.dart';

/// Premium Karşılama Ekranı — YERLEŞİM testi.
///
/// Bu ekranın tek riski taşma (overflow): tasarım 390×844'e göre ölçülendi ve
/// tek ekrana sığması gerekiyor; küçük cihazlarda (360×640) gövde kaymalı ama
/// CTA hep görünür kalmalı. Flutter'da taşma testte hata olarak yüzeye çıkar,
/// bu yüzden farklı ekran boyutlarında pump etmek gerçek bir regresyon ağıdır.
///
/// RevenueCat testte yapılandırılmamış (`isConfigured == false`) → currentOffering
/// null döner; fiyat provider'ı da ağa çıkamaz → kartlar "yükleniyor" (iskelet)
/// durumunda çizilir. Yani bu test aynı zamanda fiyat-yükleniyor durumunu kapsar.
void main() {
  setUp(() => I18n.instance.apply('tr', const {}));

  Baby baby({String name = 'Defne', BabyStatus status = BabyStatus.born}) => Baby(
        id: '11111111-1111-1111-1111-111111111111',
        name: name,
        status: status,
        birthDate: status == BabyStatus.born ? DateTime(2026, 4, 2) : null,
        dueDate: status == BabyStatus.expecting ? DateTime(2026, 12, 1) : null,
      );

  Future<void> pumpScreen(
    WidgetTester tester, {
    Baby? active,
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    AppColors.brightness = brightness;
    addTearDown(() => AppColors.brightness = Brightness.light);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBabyProvider.overrideWithValue(active),
          // Fiyat çağrısı ağa çıkmasın: dio'nun timeout zamanlayıcıları test
          // bitiminde "pending timer" hatası verir. Boş harita = mağaza ve DB
          // fiyatı yok → kartlar iskelet gösterir (yükleniyor durumu).
          pricingProvider.overrideWith((ref) async => const <String, PlanPricing>{}),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: const PremiumWelcomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('390×844 açık temada taşmadan çizilir, tüm bölümler görünür',
      (tester) async {
    await pumpScreen(tester, active: baby());

    // Kişiselleştirilmiş başlık (bebeğin adı) + karşılaştırma + planlar + CTA.
    expect(find.textContaining('Defne'), findsOneWidget);
    expect(find.text('ÜCRETSİZ'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Reklamsız kullanım'), findsOneWidget);
    expect(find.text('Bulut yedekleme'), findsOneWidget);
    expect(find.text('Hatırlatıcılar'), findsOneWidget);
    expect(find.text('En popüler'), findsOneWidget);
    expect(find.text("Premium'a Geç"), findsOneWidget);
    expect(find.text('Şimdi değil'), findsOneWidget);
    // Mağaza zorunluları alt satırda. ("Satın alımları geri yükle" yalnız RC
    // yapılandırılmışsa veya iOS'ta çıkar — testte RC kapalı, bu yüzden burada
    // beklenmiyor; iOS zorunluluğu koddaki `_rc || Platform.isIOS` koşulunda.)
    expect(find.text('Kullanım Koşulları'), findsOneWidget);
    expect(find.text('Gizlilik'), findsOneWidget);
    // Çekirdek özelliklerin ücretsiz kaldığını söyleyen güvence şeridi.
    expect(find.textContaining('ücretsizde de'), findsOneWidget);
  });

  testWidgets('koyu temada da taşmadan çizilir', (tester) async {
    await pumpScreen(tester, active: baby(), brightness: Brightness.dark);
    expect(find.text("Premium'a Geç"), findsOneWidget);
  });

  testWidgets('küçük ekranda (360×640) CTA ve çıkışlar hâlâ görünür',
      (tester) async {
    // Gövde kayar ama alt blok (CTA + "Şimdi değil" + yasal) sabit kalmalı —
    // aksi halde kullanıcı ne satın alabilir ne de kapatabilirdi.
    await pumpScreen(tester, active: baby(), size: const Size(360, 640));
    expect(find.text("Premium'a Geç"), findsOneWidget);
    expect(find.text('Şimdi değil'), findsOneWidget);
  });

  testWidgets('bekleme (gebelik) modunda başlık varyantı gösterilir',
      (tester) async {
    await pumpScreen(tester, active: baby(status: BabyStatus.expecting));
    expect(find.text('Bebeğin gelmeden hazır ol'), findsOneWidget);
    expect(find.textContaining('Defne'), findsNothing);
  });

  testWidgets('bebek yoksa isimsiz fallback başlık kullanılır', (tester) async {
    await pumpScreen(tester, active: null);
    expect(find.text('Bebeğin için en iyisi'), findsOneWidget);
  });

  testWidgets('uzun bebek adı başlığı taşırmaz', (tester) async {
    await pumpScreen(tester, active: baby(name: 'Ayşe Zeynep Nur'));
    expect(find.textContaining('Ayşe Zeynep Nur'), findsOneWidget);
  });

  testWidgets('mağaza fiyatı yokken plan kartları iskelet gösterir (uydurma '
      'fiyat yok)', (tester) async {
    await pumpScreen(tester, active: baby());
    // Plan adları var ama tutar yok.
    expect(find.text('AYLIK'), findsOneWidget);
    expect(find.text('YILLIK'), findsOneWidget);
    expect(find.text('ÖMÜRLÜK'), findsOneWidget);
    expect(find.textContaining('₺'), findsNothing);
  });
}
