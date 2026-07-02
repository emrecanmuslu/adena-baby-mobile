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
import 'core/in_app_notification.dart';
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
import 'data/activity_notif_cache.dart';
import 'data/env_cache.dart';
import 'data/feed_input_cache.dart';
import 'data/guest_migration.dart';
import 'data/i18n_repository.dart';
import 'data/local_session.dart';
import 'data/migration_service.dart';
import 'data/slot_registry.dart';
import 'data/subscription_cache.dart';
import 'data/subscription_repository.dart';
import 'data/theme_cache.dart';
import 'features/babies/baby_controller.dart';
import 'features/babies/notification_sync.dart';
import 'features/records/record_controller.dart';
import 'features/settings/locale_controller.dart';
import 'features/settings/migration_overlay.dart';
import 'features/settings/theme_controller.dart';
import 'router.dart';

// Açılış izleme durumu — watchdog + telemetri için. UI ilk frame'e ulaşınca
// _uiStarted=true; _startupStep o an çalışan adımı tutar (donmada hangi adımda
// kalındığı). Uzun-uyku sonrası soğuk başlatma donmasının teşhisi + kanıtı.
String _startupStep = 'start';
bool _uiStarted = false;

/// Açılış adımını timeout'la sarar: süre aşılır/patlarsa fallback döner ve
/// Crashlytics'e non-fatal olarak düşer. runApp öncesi TÜM bekleyişler bundan
/// geçer — Firebase init ve Keychain (flutter_secure_storage) okumaları uzun-uyku
/// sonrası soğuk başlatmada süresiz takılıp UI'ı koyu splash'te donduruyordu;
/// timeout bunu mekanik olarak imkânsız kılar, telemetri de nedenini söyler.
Future<T> _step<T>(
  String name,
  Future<T> Function() body,
  T fallback, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  _startupStep = name;
  final sw = Stopwatch()..start();
  try {
    final r = await body().timeout(timeout);
    if (sw.elapsedMilliseconds > 1500) {
      _reportStartup('startup_slow', name, sw.elapsedMilliseconds);
    }
    return r;
  } catch (e) {
    _reportStartup('startup_timeout', '$name: $e', sw.elapsedMilliseconds);
    return fallback;
  }
}

/// Açılış telemetrisi → Crashlytics non-fatal (Firebase hazır değilse sessizce
/// yutulur; konsola her durumda basılır).
void _reportStartup(String kind, String detail, int ms) {
  debugPrint('[startup] $kind — $detail (${ms}ms)');
  try {
    FirebaseCrashlytics.instance.recordError('$kind: $detail (${ms}ms)', null,
        reason: 'cold-start', fatal: false);
  } catch (_) {}
}

/// Firebase başarılı init sonrası: push arka plan işleyicisi + Crashlytics kancaları.
void _setupFirebaseSideEffects() {
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Crashlytics: debug'da topla(ma) — yalnız release'te çökme/raporları yolla.
    FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    // Flutter framework hataları → Crashlytics (önce konsola da bas).
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Framework dışı (async/platform) yakalanmamış hatalar → Crashlytics.
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {}
}

/// initializeApp ilk denemede timeout ettiyse (UI zaten açıldı): Firebase'i sessizce
/// yeniden dene ki push/Crashlytics çalışsın + bu gecikme kök-neden kanıtı olarak düşsün.
Future<void> _retryFirebaseInBackground() async {
  for (var i = 0; i < 3; i++) {
    await Future.delayed(const Duration(seconds: 2));
    try {
      await Firebase.initializeApp();
      _setupFirebaseSideEffects();
      _reportStartup(
          'firebase_init_deferred', 'recovered after timeout (try ${i + 1})', 0);
      return;
    } catch (_) {}
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Watchdog: UI 12 sn'de ilk frame'e ulaşmazsa hangi adımda kalındığını Crashlytics'e
  // düşür. Timeout'lu adımlar donmayı zaten ÖNLER; bu çok-adımlı yavaşlığa karşı backstop.
  Timer(const Duration(seconds: 12), () {
    if (_uiStarted) return;
    debugPrint('[startup] WATCHDOG: ilk frame yok, son adım: $_startupStep');
    try {
      FirebaseCrashlytics.instance
          .setCustomKey('startup_last_step', _startupStep);
      FirebaseCrashlytics.instance.recordError(
          'startup_watchdog_stall after "$_startupStep"', null,
          reason: 'cold-start-hang', fatal: false);
    } catch (_) {}
  });

  await _step<Object?>('intl', () async {
    await initializeDateFormatting(); // tüm locale tarih biçimleri (tr + en)
    return null;
  }, null);

  // Firebase init uzun-uyku sonrası soğuk başlatmada süresiz takılabiliyordu
  // (koyu splash donması) → 5 sn timeout; başarısızsa UI'ı bekletme, arka planda yeniden dene.
  final firebaseReady = await _step<bool>('firebase', () async {
    await Firebase.initializeApp();
    return true;
  }, false, timeout: const Duration(seconds: 5));
  if (firebaseReady) {
    _setupFirebaseSideEffects();
  } else {
    unawaited(_retryFirebaseInBackground());
  }

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
  // Local-first kimlik/rıza + bildirim slot haritası — bağımsız, PARALEL yükle.
  // Router rızayı; Baby.notifSlot (sync) benzersiz slotu ilk frame'de okuyabilsin
  // diye ikisi de runApp öncesi tamamlanır (Keychain takılırsa timeout kurtarır).
  await _step<Object?>('session+slots', () async {
    await Future.wait([
      LocalSession.ensureLoaded(),
      SlotRegistry.instance.load(),
    ]);
    return null;
  }, null, timeout: const Duration(seconds: 5));
  // İlk açılışta (dil cache yokken) cihaz dili TR değilse çeviri bundle'ını
  // splash öncesi getir → İLK ekran doğru dilde açılsın. Cache varsa anında.
  await _step<Object?>('locale-bundle', () async {
    await _preloadLocaleBundle();
    return null;
  }, null);
  // Debug "Geliştirici → Ortam" seçimini uygula (ApiClient kurulmadan ÖNCE).
  // Release'te EnvCache hep boş kalır (UI gösterilmez) → derleme varsayılanı.
  AppConfig.setRuntimeApiBaseUrl(
      await _step<String?>('env-cache', () => EnvCache().read(), null));
  // Son bilinen premium durumunu cache'ten oku → açılıştan itibaren flaş'sız.
  final cachedPremium =
      await _step<bool>('premium-cache', () => SubscriptionCache().read(), false);
  // Son seçilen temayı cache'ten oku → splash/ilk frame doğru temada açılsın.
  final cachedTheme = await _step<ThemeMode>(
      'theme-cache', () => ThemeCache().read(), ThemeMode.system);
  _startupStep = 'runApp';
  _uiStarted = true;
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
  // Ön plan in-app banner'ının aynı olayı iki kez göstermesini önleyen basit
  // in-memory dedup (onMessage + iOS native köprü aynı push'u sevk edebilir).
  String? _lastBannerEventId;
  // Misafir→hesap göç teklifini oturum başına bir kez sor.
  bool _guestMigChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Uygulama ön planda başlar → push OS bildirimi yerine in-app banner göstersin.
    appInForeground = true;
    // Push: ön plan mesaj dinleyicisi (oturum gerektirmez).
    PushService.instance.startForeground();
    // Ön planda aile-etkinlik push'u gelince yerel kayıtları HEMEN çek → ana
    // ekrandaki "sonraki beslenme"/akış 1 dk'lık polling'i beklemeden yenilensin
    // (handlePushMessage drift'e dokunmaz; sync'i buradan, ref'le tetikliyoruz).
    try {
      // Ortak sevk: hem FlutterFire onMessage hem iOS native köprü buraya düşer.
      void dispatch(Map<String, dynamic> data) {
        final t = data['type'] as String?;
        // family_activity = başka üye kayıt ekledi; sync_nudge = güncelleme/silme
        // (uyku/emzirme bitirme dahil). İkisi de yerel kayıtları hemen çeksin.
        if (t == 'family_activity' || t == 'sync_nudge') {
          ref.read(syncServiceProvider).requestSyncSoon();
        }
        // baby_update = sahip bebek profilini değiştirdi (ör. gebelik→doğdu);
        // access_removed = paylaşımdan çıkarıldım / sahibin cloud'u silindi → ikisi de
        // bebek listesini hemen tazelesin (status güncellensin / erişimi kalkan bebek
        // düşürülüp yerel verisi temizlensin), 90 sn beklenmesin.
        if (t == 'baby_update' || t == 'access_removed') {
          ref.read(babyControllerProvider.notifier).refresh();
        }
        // Ön plan in-app banner: GÖRÜNÜR body taşıyan her push (OS bildirimi ön
        // planda basılmaz — bkz. appInForeground). Sessiz push'lar (sync_nudge/
        // baby_update/access_removed) body taşımadığından _showActivityBanner
        // içindeki body-boş kontrolüyle elenir. Push tek kaynak → çift bildirim yok.
        _showActivityBanner(t, data);
      }

      FirebaseMessaging.onMessage.listen((m) => dispatch(m.data));
      // iOS native köprü: AppDelegate her gelen push'ta 'adena/push' kanalını
      // çağırır → FlutterFire onMessage yeni UIScene yaşam döngüsünde güvenilir
      // ateşlenmese bile ön planda sync/refresh/banner DETERMİNİSTİK tetiklenir.
      // (Android'de kanal hiç çağrılmaz; orada onMessage yeterli.) requestSyncSoon
      // debounce'lu + banner event_id dedup'lı → çift sevk tek sonuç verir.
      const MethodChannel('adena/push').setMethodCallHandler((call) async {
        if (call.method == 'onPush') {
          final raw = (call.arguments as Map?) ?? const {};
          dispatch(raw.map((k, v) => MapEntry(k.toString(), v)));
        }
      });
    } catch (_) {}
    // Yol A: öne gelince + periyodik yoklama. İlk tetik ilk frame'den sonra
    // (oturum/bebekler yüklensin diye gecikmeli).
    WidgetsBinding.instance.addPostFrameCallback((_) => _onForeground());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ön plan/arka plan bayrağı: ön planda push OS bildirimi yerine in-app banner
    // gösterir (handlePushMessage appInForeground'a bakar).
    appInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) _onForeground();
  }

  /// Ön plan push'u için in-app üst banner göster. Yalnız GÖRÜNÜR body taşıyan
  /// push'lar (family_activity/topluluk/admin test); sessiz push'lar body boş →
  /// gösterilmez. event_id ile in-memory dedup (onMessage + iOS native köprü aynı
  /// olayı sevk edebilir).
  Future<void> _showActivityBanner(String? type, Map<String, dynamic> data) async {
    final body = data['body']?.toString() ?? '';
    if (body.isEmpty) return; // sessiz push (sync_nudge/baby_update/...) → banner yok
    final eventId = data['event_id']?.toString() ?? '';
    if (eventId.isNotEmpty && eventId == _lastBannerEventId) return;
    if (eventId.isNotEmpty) _lastBannerEventId = eventId;
    // Aile etkinliği tercihi kapalıysa gösterme (sunucu push görünürlüğüyle tutarlı).
    if (type == 'family_activity' && !await ActivityNotifCache().enabled()) return;
    final title =
        data['title']?.toString() ?? data['baby_name']?.toString() ?? 'Adena Baby';
    showInAppNotification(title: title, body: body);
  }

  /// Misafirken giriş/kayıt yapan kullanıcıya "yereldeki kayıtlarını hesabına
  /// aktaralım mı?" diye bir kez sorar. Onaylarsa [GuestMigration.migrate] yerel
  /// misafir verisini gerçek hesaba rebind eder (premium'da buluta yükler).
  Future<void> _maybeOfferGuestMigration(String accountId) async {
    if (_guestMigChecked || LocalSession.guestMigrationResolved) return;
    _guestMigChecked = true;
    final db = ref.read(databaseProvider);
    if (!await GuestMigration.hasData(db, accountId)) return;
    // Bu misafir turu için yanıtlandı say (enterGuest'te yeniden sıfırlanır).
    await LocalSession.setGuestMigrationResolved(true);
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final migrate = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(tr('Kayıtlarını hesabına aktaralım mı?')),
        content: Text(tr('Kayıt olmadan eklediğin bebek ve kayıtlar bu cihazda '
            'duruyor. Hesabına aktaralım mı? Aktarmazsan hesabın boş başlar '
            've bu veriler cihazda kalır.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Hayır')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Aktar')),
          ),
        ],
      ),
    );
    if (migrate == true) {
      await GuestMigration.migrate(ref, accountId);
      showInAppNotification(
          title: tr('Aktarıldı'), body: tr('Kayıtların hesabına taşındı.'));
    }
  }

  /// Öne gelince: bebek listesini tazele (çıkarılan üyenin erişimi düşsün, yerel
  /// verisi temizlensin) + drift stream'lerini yeniden okut.
  void _onForeground() {
    // Warm-resume'da ön plan drift stream'lerini ANINDA yeniden okut: uygulama
    // kapalı/arka plandayken arka plan isolate'i (bg sync / push handler) ayrı
    // bağlantıyla yeni kayıtları dosyaya yazmış olabilir — bu bağlantının stream'leri
    // o yazımdan habersizdir, Home bayat görünür (yalnız kapat-aç düzeltiyordu).
    // Ağ sync'ini beklemeden dosyadaki güncel veriyi yansıt. Bkz syncAll() + drift
    // cross-isolate notifyUpdates. [[bug-home-bayat-veri-warm-resume]]
    ref.read(databaseProvider).refreshSyncedStreams();
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

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // Oturum açıkken FCM token'ını sunucuya kaydet (giriş sonrası da tetiklenir).
    ref.listen(authControllerProvider, (prev, next) {
      final user = next.asData?.value;
      if (user != null) {
        PushService.instance.registerToken(ref.read(apiClientProvider));
        // Misafirken (çıkış/oturum-yok) giriş/kayıt yapıldıysa: yereldeki misafir
        // verisini hesaba aktarmayı bir kez teklif et.
        if (prev?.asData?.value == null) {
          unawaited(_maybeOfferGuestMigration(user.id));
        }
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
