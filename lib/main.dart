import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/ad_service.dart';
import 'core/analytics_service.dart';
import 'core/api_client.dart';
import 'core/background_sync.dart';
import 'core/i18n.dart';
import 'core/locale_util.dart';
import 'core/token_storage.dart';
import 'data/locale_cache.dart';
import 'core/notification_service.dart';
import 'core/providers.dart';
import 'core/push_service.dart';
import 'core/restart_widget.dart';
import 'core/config.dart';
import 'core/revenuecat_service.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'data/env_cache.dart';
import 'data/feed_input_cache.dart';
import 'data/i18n_repository.dart';
import 'data/local_session.dart';
import 'data/migration_service.dart';
import 'data/slot_registry.dart';
import 'data/subscription_cache.dart';
import 'data/subscription_repository.dart';
import 'data/theme_cache.dart';
import 'features/babies/activity_watcher.dart';
import 'features/babies/baby_controller.dart';
import 'features/babies/notification_sync.dart';
import 'features/records/record_controller.dart';
import 'features/settings/locale_controller.dart';
import 'features/settings/migration_overlay.dart';
import 'features/settings/theme_controller.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting(); // tüm locale tarih biçimleri (tr + en)
  } catch (_) {}
  // Firebase + push arka plan işleyicisi (config yoksa sessizce atlanır).
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Crashlytics: debug'da topla(ma) — yalnız release'te çökme/raporları yolla.
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    // Flutter framework hataları → Crashlytics (önce konsola da bas).
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Framework dışı (async/platform) yakalanmamış hatalar → Crashlytics.
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {}
  // Bildirim/timezone init'i açılışı ENGELLEMESİN — iOS'ta hata/izin sorunu
  // tüm uygulamayı beyaz ekranda bırakmasın. Arka planda kurulur; planlama
  // çağrıları zaten gerekirse init()'i bekler.
  unawaited(NotificationService.instance.init());
  // RevenueCat'i arka planda yapılandır (anahtar yoksa sessiz no-op).
  unawaited(RevenueCatService.instance.configure());
  // Reklam ilk-gün penceresi için kurulum zamanını sakla.
  unawaited(AdService.instance.init());
  // Arka plan sync (uygulama kapalıyken paylaşımlı bebek fallback'i): push düşmese
  // de ~30 dk'da bir paylaşımlı bebekleri çek. Android=WorkManager, iOS=BGTaskScheduler
  // (fırsatçı). Kayıt idempotent. OEM (Xiaomi) pil kısıtı throttle edebilir.
  unawaited(registerBackgroundSync());
  // Analytics: consent-gated; rıza yoksa/ debug'da sessiz no-op (varsayılan kapalı).
  unawaited(AnalyticsService.instance.init());
  // Beslenme formu son-değer cache'ini belleğe al (form senkron okusun).
  unawaited(FeedInputCache.ensureLoaded());
  // Local-first kimlik & rıza: localUserId + yerel rıza durumunu belleğe yükle
  // (hesapsız çalışma; router/repository senkron okur). Açılışı bloklamamalı ama
  // router rızayı ilk frame'de doğru görsün diye await edilir (çok hızlı).
  // Local-first kimlik/rıza + bildirim slot haritası — bağımsız, PARALEL yükle
  // (açılış bloke süresini kısalt). Router rızayı; Baby.notifSlot (sync) benzersiz
  // slotu ilk frame'de okuyabilsin diye ikisi de runApp öncesi tamamlanır.
  await Future.wait([
    LocalSession.ensureLoaded(),
    SlotRegistry.instance.load(),
  ]);
  // İlk açılışta (dil cache yokken) cihaz dili TR değilse çeviri bundle'ını
  // splash öncesi getir → İLK ekran (rıza/welcome) doğru dilde açılsın, TR flaş'ı
  // olmasın. Cache varsa anında uygulanır (ağ beklenmez). En fazla 2 sn bekler;
  // ağ yok/timeout → router'ın I18n dinleyicisi bundle gelince yakalar.
  await _preloadLocaleBundle();
  // Debug "Geliştirici → Ortam" seçimini uygula (ApiClient kurulmadan ÖNCE).
  // Release'te EnvCache hep boş kalır (UI gösterilmez) → derleme varsayılanı.
  AppConfig.setRuntimeApiBaseUrl(await EnvCache().read());
  // Son bilinen premium durumunu cache'ten oku → açılıştan itibaren flaş'sız.
  final cachedPremium = await SubscriptionCache().read();
  // Son seçilen temayı cache'ten oku → splash/ilk frame doğru temada açılsın.
  final cachedTheme = await ThemeCache().read();
  runApp(RestartWidget(
    child: ProviderScope(
      overrides: [
        cachedPremiumProvider.overrideWithValue(cachedPremium),
        cachedThemeProvider.overrideWithValue(cachedTheme),
      ],
      child: const AdenaApp(),
    ),
  ));
}

/// İlk açılışta çeviri bundle'ını splash öncesi getirir (cache yoksa ve cihaz
/// dili TR değilse). Cache varsa anında uygular, ağ beklemez. En fazla 2 sn.
Future<void> _preloadLocaleBundle() async {
  try {
    final cached = await LocaleCache().read();
    final locale = cached ?? deviceDefaultLanguage();
    if (locale == 'tr') return; // TR = kaynak dil, bundle gerekmez
    final repo = I18nRepository(ApiClient(TokenStorage()));
    final (_, existing) = await repo.readCache(locale);
    if (existing.isNotEmpty) {
      I18n.instance.apply(locale, existing); // cache var → anında
      return;
    }
    // İlk açılış: bundle'ı getirip uygula (kısa timeout; takılırsa router yakalar).
    // 2 sn: zayıf ağda koyu-splash'te uzun donmayı önler; bundle gelince I18n
    // dinleyicisi mevcut ekranı yine de tazeler.
    final fresh = await repo.sync(locale).timeout(const Duration(seconds: 2));
    I18n.instance.apply(locale, fresh);
  } catch (_) {
    // ağ yok/timeout → ilk ekran TR fallback; bundle gelince router I18n
    // dinleyicisi mevcut sayfayı tazeler.
  }
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
    // Ön planda aile-etkinlik push'u gelince yerel kayıtları HEMEN çek → ana
    // ekrandaki "sonraki beslenme"/akış 1 dk'lık polling'i beklemeden yenilensin
    // (handlePushMessage drift'e dokunmaz; sync'i buradan, ref'le tetikliyoruz).
    try {
      // Ortak sevk: hem FlutterFire onMessage hem iOS native köprü buraya düşer.
      void dispatch(String? t) {
        // family_activity = başka üye kayıt ekledi; sync_nudge = güncelleme/silme
        // (uyku/emzirme bitirme dahil). İkisi de yerel kayıtları hemen çeksin.
        if (t == 'family_activity' || t == 'sync_nudge') {
          ref.read(syncServiceProvider).requestSyncSoon();
        }
        // baby_update = sahip bebek profilini değiştirdi (ör. gebelik→doğdu);
        // access_removed = paylaşımdan çıkarıldım / sahibin cloud'u silindi → ikisi de
        // bebek listesini hemen tazelesin (status güncellensin / erişimi kalkan bebek
        // düşürülüp yerel verisi temizlensin), 90 sn polling beklenmesin.
        if (t == 'baby_update' || t == 'access_removed') {
          ref.read(babyControllerProvider.notifier).refresh();
        }
      }

      FirebaseMessaging.onMessage.listen((m) => dispatch(m.data['type'] as String?));
      // iOS native köprü: AppDelegate her gelen push'ta 'adena/push' kanalını
      // çağırır → FlutterFire onMessage yeni UIScene yaşam döngüsünde güvenilir
      // ateşlenmese bile ön planda sync/refresh DETERMİNİSTİK tetiklenir. (Android'de
      // kanal hiç çağrılmaz; orada onMessage yeterli.) requestSyncSoon debounce'lu →
      // onMessage ile çift tetiklense bile tek sync olur.
      const MethodChannel('adena/push').setMethodCallHandler((call) async {
        if (call.method == 'onPush') {
          final raw = (call.arguments as Map?) ?? const {};
          dispatch(raw['type']?.toString());
        }
      });
    } catch (_) {}
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
    // Bildirim izni sistem ayarlarından sonradan açıldıysa, devam eden uyku/
    // emzirme sayacının bildirimini yeniden post et (reaktif sync tetiklenmez).
    repostActiveTimers(ref);
    // FCM token iOS'ta ilk açılışta geç gelmiş olabilir → oturum varsa cihaz
    // kaydını yeniden dene (token artık hazırsa /me/devices'a düşer). Güvence.
    if (ref.read(authControllerProvider).asData?.value != null) {
      PushService.instance.registerToken(ref.read(apiClientProvider));
    }
    // App-Open reklamı: ilk çağrı (cold start) yalnız ön-yükler; sonraki
    // resume'larda limitler uygunsa gösterir (premium muaf). Hiç bebek yokken
    // (giriş/onboarding) gösterilmez — reklam ancak bebek eklendikten sonra.
    final babies = ref.read(babyControllerProvider).asData?.value ?? const [];
    AdService.instance.onAppForeground(
      isPremium: ref.read(isPremiumProvider),
      hasBaby: babies.isNotEmpty,
    );
    // İçeriksiz segment özellikleri (rıza yoksa/debug'da no-op): premium + dil.
    unawaited(AnalyticsService.instance.setUserProperty(
        'is_premium', ref.read(isPremiumProvider) ? 'yes' : 'no'));
    unawaited(
        AnalyticsService.instance.setUserProperty('app_locale', I18n.instance.locale));
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
    ref.watch(localToCloudMigrationProvider); // free→premium: yerel veriyi yükle
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
    final localeStr =
        ref.watch(localeControllerProvider).asData?.value ?? deviceDefaultLanguage();
    // Desteklenen diller sunucudan (yeni dil eklenince otomatik); yüklenene
    // kadar tr+en. Aktif dil listede yoksa eklenir (Localizations çözümü için).
    final fetched = ref.watch(supportedLocalesProvider).asData?.value;
    final codes = <String>{
      ...(fetched != null && fetched.isNotEmpty)
          ? fetched.map((e) => e.code)
          : const ['tr', 'en'],
      localeStr,
    };
    final supported = [for (final c in codes) Locale(c)];
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
        supportedLocales: supported,
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
            // free→premium yükleme sürecini gösteren tam-ekran overlay
            // (yalnız migrasyon çalışırken/biterken görünür).
            const MigrationOverlay(),
          ],
        ),
      ),
    );
  }
}
