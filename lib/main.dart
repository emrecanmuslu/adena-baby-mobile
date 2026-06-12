import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/ad_service.dart';
import 'core/i18n.dart';
import 'core/notification_service.dart';
import 'core/revenuecat_service.dart';
import 'core/theme.dart';
import 'data/subscription_cache.dart';
import 'data/subscription_repository.dart';
import 'features/records/record_controller.dart';
import 'features/settings/locale_controller.dart';
import 'features/settings/theme_controller.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('tr_TR'); // tarih biçimleri (DateFormat tr_TR)
  } catch (_) {}
  // Bildirim/timezone init'i açılışı ENGELLEMESİN — iOS'ta hata/izin sorunu
  // tüm uygulamayı beyaz ekranda bırakmasın. Arka planda kurulur; planlama
  // çağrıları zaten gerekirse init()'i bekler.
  unawaited(NotificationService.instance.init());
  // RevenueCat'i arka planda yapılandır (anahtar yoksa sessiz no-op).
  unawaited(RevenueCatService.instance.configure());
  // Reklam ilk-gün penceresi için kurulum zamanını sakla.
  unawaited(AdService.instance.init());
  // Son bilinen premium durumunu cache'ten oku → açılıştan itibaren flaş'sız.
  final cachedPremium = await SubscriptionCache().read();
  runApp(ProviderScope(
    overrides: [cachedPremiumProvider.overrideWithValue(cachedPremium)],
    child: const AdenaApp(),
  ));
}

class AdenaApp extends ConsumerWidget {
  const AdenaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    ref.watch(syncServiceProvider); // connectivity dinleyicisini canlı tut
    ref.watch(premiumSyncProvider); // RC entitlement → backend senkron dinleyicisi
    final themeMode = ref.watch(themeControllerProvider).asData?.value ?? ThemeMode.system;
    // Sabit AppColors semantik nötrleri etkin temaya göre çözülsün (Gece Modu).
    final platformDark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    AppColors.brightness = (themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system && platformDark))
        ? Brightness.dark
        : Brightness.light;
    final localeStr = ref.watch(localeControllerProvider).asData?.value ?? 'tr';
    // I18n bundle/dil değişince tüm ağaç yenilensin (tr() yeniden değerlensin).
    return AnimatedBuilder(
      animation: I18n.instance,
      builder: (context, _) => MaterialApp.router(
        title: 'Adena Baby',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: router,
        locale: Locale(localeStr),
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
  }
}
