import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/ad_service.dart';
import 'core/i18n.dart';
import 'core/notification_service.dart';
import 'core/providers.dart';
import 'core/push_service.dart';
import 'core/revenuecat_service.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'data/feed_input_cache.dart';
import 'data/subscription_cache.dart';
import 'data/subscription_repository.dart';
import 'data/theme_cache.dart';
import 'features/babies/activity_watcher.dart';
import 'features/babies/baby_controller.dart';
import 'features/babies/notification_sync.dart';
import 'features/records/record_controller.dart';
import 'features/settings/locale_controller.dart';
import 'features/settings/theme_controller.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('tr_TR'); // tarih biçimleri (DateFormat tr_TR)
  } catch (_) {}
  // Firebase + push arka plan işleyicisi (config yoksa sessizce atlanır).
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {}
  // Bildirim/timezone init'i açılışı ENGELLEMESİN — iOS'ta hata/izin sorunu
  // tüm uygulamayı beyaz ekranda bırakmasın. Arka planda kurulur; planlama
  // çağrıları zaten gerekirse init()'i bekler.
  unawaited(NotificationService.instance.init());
  // RevenueCat'i arka planda yapılandır (anahtar yoksa sessiz no-op).
  unawaited(RevenueCatService.instance.configure());
  // Reklam ilk-gün penceresi için kurulum zamanını sakla.
  unawaited(AdService.instance.init());
  // Beslenme formu son-değer cache'ini belleğe al (form senkron okusun).
  unawaited(FeedInputCache.ensureLoaded());
  // Son bilinen premium durumunu cache'ten oku → açılıştan itibaren flaş'sız.
  final cachedPremium = await SubscriptionCache().read();
  // Son seçilen temayı cache'ten oku → splash/ilk frame doğru temada açılsın.
  final cachedTheme = await ThemeCache().read();
  runApp(ProviderScope(
    overrides: [
      cachedPremiumProvider.overrideWithValue(cachedPremium),
      cachedThemeProvider.overrideWithValue(cachedTheme),
    ],
    child: const AdenaApp(),
  ));
}

class AdenaApp extends ConsumerStatefulWidget {
  const AdenaApp({super.key});

  @override
  ConsumerState<AdenaApp> createState() => _AdenaAppState();
}

class _AdenaAppState extends ConsumerState<AdenaApp> with WidgetsBindingObserver {
  Timer? _activityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Push: ön plan mesaj dinleyicisi (oturum gerektirmez).
    PushService.instance.startForeground();
    // Yol A: öne gelince + periyodik yoklama. İlk tetik ilk frame'den sonra
    // (oturum/bebekler yüklensin diye gecikmeli).
    WidgetsBinding.instance.addPostFrameCallback((_) => _onForeground());
    _activityTimer = Timer.periodic(
        const Duration(seconds: 90), (_) => _pollActivity());
  }

  @override
  void dispose() {
    _activityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onForeground();
  }

  /// Öne gelince: aile etkinliğini yokla + bebek listesini tazele (çıkarılan
  /// üyenin erişimi düşsün, yerel verisi temizlensin).
  void _onForeground() {
    _pollActivity();
    ref.read(babyControllerProvider.notifier).refresh();
  }

  void _pollActivity() {
    // Sessiz; tercih kapalıysa/oturum yoksa watcher kendi içinde no-op döner.
    ref.read(familyActivityWatcherProvider).poll();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Oturum açıkken FCM token'ını sunucuya kaydet (giriş sonrası da tetiklenir).
    ref.listen(authControllerProvider, (prev, next) {
      if (next.asData?.value != null) {
        PushService.instance.registerToken(ref.read(apiClientProvider));
      }
    });
    ref.watch(syncServiceProvider); // connectivity dinleyicisini canlı tut
    ref.watch(premiumSyncProvider); // RC entitlement → backend senkron dinleyicisi
    // Henüz yüklenmediyse cache'lenen temaya düş (sistem koyu olsa bile flaş yok).
    final themeMode =
        ref.watch(themeControllerProvider).asData?.value ?? ref.watch(cachedThemeProvider);
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
        // Tüm bebekler için sayaç/beslenme bildirimi eşitleyici — görünmez, her
        // zaman ağaçta (yalnız aktif ekrana bağlı değil).
        builder: (context, child) => Stack(
          children: [
            ?child,
            const Offstage(child: FamilyNotificationSync()),
          ],
        ),
      ),
    );
  }
}
