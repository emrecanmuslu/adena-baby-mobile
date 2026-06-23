class AppConfig {
  /// API taban adresi.
  /// - Android emülatör → host makineye `10.0.2.2` ile erişir.
  /// - Fiziksel cihaz → PC'nin LAN IP'si (ör. http://192.168.1.X:8000/api/v1).
  /// `--dart-define=API_BASE_URL=...` ile override edilebilir.
  // Derleme-zamanı varsayılanı. Runtime'da (debug ortam değiştirici) override edilebilir.
  static const String _compileApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  /// Debug "Geliştirici → Ortam" override'ı (EnvCache'ten açılışta yüklenir).
  /// Yalnız debug build'lerde değiştirilir; release'te hep _compileApiBaseUrl.
  static String? _runtimeApiBaseUrl;
  static void setRuntimeApiBaseUrl(String? url) =>
      _runtimeApiBaseUrl = (url == null || url.isEmpty) ? null : url;

  static String get apiBaseUrl => _runtimeApiBaseUrl ?? _compileApiBaseUrl;

  /// Bilinen ortam sabitleri (debug ortam değiştirici seçenekleri).
  static const String envLocalUrl = 'http://10.0.2.2:8000/api/v1';
  static const String envProdUrl = 'https://api.adenababy.com/api/v1';

  /// Sunucu kökü (media/static için) — `apiBaseUrl`'den `/api/v1` soneki atılır.
  /// Ör. http://10.0.2.2:8000 → fetus görselleri: `$mediaBaseUrl/media/fetus/12.png`.
  static String get mediaBaseUrl =>
      apiBaseUrl.replaceFirst(RegExp(r'/api/v\d+/?$'), '');

  /// Tanıtım/yasal sitesi kökü (API'den bağımsız, her ortamda canlı domain).
  /// Yasal sayfa linkleri (gizlilik/şartlar/KVKK/çerez) buradan açılır.
  static const String websiteBaseUrl = String.fromEnvironment(
    'WEBSITE_BASE_URL',
    defaultValue: 'https://adenababy.com',
  );

  // ── Sosyal giriş (Google / Apple) ──────────────────────────────────
  // Değerler `--dart-define` ile build'e verilir; gizli değil ama kaynakta
  // tutmuyoruz çünkü ortama göre değişir. Boşsa ilgili sağlayıcı butonu
  // "yapılandırılmamış" hatası verir.

  /// Google **Web** OAuth client ID. id_token'ın `aud`'u bu olur; backend
  /// `GOOGLE_CLIENT_IDS` bu değeri içermeli. Android + iOS ikisinde de gerekir.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Google **iOS** OAuth client ID (iOS'ta native akış için). Android'de boş
  /// bırakılabilir (orada `serverClientId` + google-services yeterli).
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  /// Apple **Services ID** — yalnızca Android/web web-akışı için. iOS/macOS'ta
  /// gerekmez (native Sign in with Apple). Boşsa Apple butonu Android'de gizli.
  static const String appleServiceId = String.fromEnvironment(
    'APPLE_SERVICE_ID',
    defaultValue: '',
  );

  /// Apple web-akışı dönüş adresi (Android için, Services ID ile eşleşir).
  static const String appleRedirectUri = String.fromEnvironment(
    'APPLE_REDIRECT_URI',
    defaultValue: '',
  );

  // ── RevenueCat (premium satın alma / entitlement) ──────────────────
  // Platform-bazlı **public** API anahtarları (gizli değil — istemci anahtarı).
  // Boşsa RevenueCat sessizce devre dışı kalır: premium durumu yalnız backend'den
  // okunur, satın alma akışı kapanır. RC dashboard → Project → API keys.

  /// Android (Google Play) public anahtarı (goog_...).
  static const String revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
    defaultValue: '',
  );

  /// iOS (App Store) public anahtarı (appl_...).
  static const String revenueCatIosKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: '',
  );

  // ── AdMob (reklam) ──────────────────────────────────────────────────
  // Interstitial reklam birim id'leri. Boşsa gerçek reklam yerine geliştirme
  // placeholder'ı gösterilir (frekans limiti yine işler). AdMob app id'si ayrıca
  // AndroidManifest/Info.plist'e eklenmeli (SDK bağlanınca).

  static const String admobAndroidInterstitialId = String.fromEnvironment(
    'ADMOB_ANDROID_INTERSTITIAL_ID',
    defaultValue: '',
  );

  static const String admobIosInterstitialId = String.fromEnvironment(
    'ADMOB_IOS_INTERSTITIAL_ID',
    defaultValue: '',
  );

  // App-Open reklam birim id'leri (uygulama öne gelince). Boşsa app-open
  // gösterilmez. Debug'da Google test id'leri kullanılır (ad_service.dart).
  static const String admobAndroidAppOpenId = String.fromEnvironment(
    'ADMOB_ANDROID_APP_OPEN_ID',
    defaultValue: '',
  );

  static const String admobIosAppOpenId = String.fromEnvironment(
    'ADMOB_IOS_APP_OPEN_ID',
    defaultValue: '',
  );

  // Banner reklam birim id'leri (içerik/liste ekranları). Boşsa banner
  // gösterilmez. Debug'da Google test id'leri kullanılır (banner widget).
  static const String admobAndroidBannerId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_ID',
    defaultValue: '',
  );

  static const String admobIosBannerId = String.fromEnvironment(
    'ADMOB_IOS_BANNER_ID',
    defaultValue: '',
  );
}
