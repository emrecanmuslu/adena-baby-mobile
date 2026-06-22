import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'config.dart';

/// Reklam overlay'ini herhangi bir ekranın üstünden göstermek için kök
/// navigator. MaterialApp.router'a verilir (router.dart). Gerçek interstitial
/// kendi tam-ekranını açar; bu key go_router'ın kök navigatörü içindir.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Frekans-limitli geçiş (interstitial) reklam yöneticisi — AdMob.
///
/// Optimizasyon ([[para-kazanma-modeli]] yumuşak doz): kaydı BLOKLAMAZ — kayıt
/// tamamlandıktan sonra çağrılır; premium muaftır; en az [_minRecords] kayıt VE
/// son reklamdan [_minGap] geçmeden gösterilmez (peş peşe girişte çıkmaz); ilk
/// [_graceWindow] kadar reklamsızdır (onboarding).
///
/// Reklam birimi: **debug** build'de Google'ın resmî **test** id'leri kullanılır
/// (kendi reklamına tıklama → hesap kapanması riski yok); **release**'de
/// `dart_defines.json`'daki gerçek AdMob birim id'leri (boşsa reklam çıkmaz).
/// Reklam o an yüklü değilse gösterim **sessizce atlanır** ve bir sonraki için
/// ön-yükleme yapılır — kullanıcıya hiçbir zaman boş/sahte kutu gösterilmez.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const int _minRecords = 3;
  static const Duration _minGap = Duration(minutes: 3);
  static const Duration _graceWindow = Duration(hours: 24); // ilk gün reklamsız
  // Günlük interstitial üst sınırı — eşikler (3 kayıt/3 dk) aşılsa bile bir günde
  // bundan fazla geçiş reklamı gösterilmez (gün boyu kayıt → tavan korur).
  static const int _maxInterstitialPerDay = 4;
  // App-Open: uygulama öne gelince en fazla bu sıklıkta + reklam 4 saat geçerli.
  static const Duration _appOpenMinGap = Duration(hours: 4);
  static const Duration _appOpenTtl = Duration(hours: 4);
  static const _storage = FlutterSecureStorage();
  static const _kFirstLaunch = 'ad_first_launch';
  // Kalıcı durum (restart by-pass'ı kapatır): son gösterim + günlük sayaç.
  static const _kLastShown = 'ad_last_shown';
  static const _kDayKey = 'ad_day_key';
  static const _kDayCount = 'ad_day_count';
  static const _kAppOpenLast = 'ad_appopen_last';

  // Google resmî test birim id'leri (debug'da kullanılır).
  static const _testAndroidUnit = 'ca-app-pub-3940256099942544/1033173712';
  static const _testIosUnit = 'ca-app-pub-3940256099942544/4411468910';
  static const _testAndroidAppOpen = 'ca-app-pub-3940256099942544/9257395921';
  static const _testIosAppOpen = 'ca-app-pub-3940256099942544/5575463023';

  int _recordsSinceAd = 0;
  DateTime? _lastShown;
  DateTime? _firstLaunch;
  String? _dayKey; // bugünün anahtarı (yyyy-mm-dd) — sayaç bu güne ait
  int _todayCount = 0; // bugün gösterilen interstitial sayısı

  InterstitialAd? _ad;
  bool _loading = false;

  /// Bir tam-ekran reklam (interstitial veya app-open) o an ekrandayken true —
  /// ikisinin üst üste binmesini ve reklam dönüşünde app-open tetiklenmesini önler.
  bool _showingAd = false;

  AppOpenAd? _appOpenAd;
  DateTime? _appOpenLoadedAt;
  DateTime? _lastAppOpenShown;
  bool _firstForegroundSeen = false; // ilk açılış (cold start) = gösterme, ön-yükle

  /// Açılışta bir kez. SDK'yı başlatır, ilk reklamı ön-yükler ve ilk kurulum
  /// zamanını kalıcı saklar (ilk 24 saat reklamsız). Hata uygulamayı engellemez.
  Future<void> init() async {
    try {
      final stored = await _storage.read(key: _kFirstLaunch);
      if (stored != null) {
        _firstLaunch = DateTime.tryParse(stored);
      } else {
        _firstLaunch = DateTime.now();
        await _storage.write(
            key: _kFirstLaunch, value: _firstLaunch!.toIso8601String());
      }
      // Kalıcı reklam durumunu geri yükle (restart sonrası limitler korunsun).
      _lastShown = DateTime.tryParse(await _storage.read(key: _kLastShown) ?? '');
      _lastAppOpenShown =
          DateTime.tryParse(await _storage.read(key: _kAppOpenLast) ?? '');
      _dayKey = await _storage.read(key: _kDayKey);
      _todayCount = int.tryParse(await _storage.read(key: _kDayCount) ?? '') ?? 0;
    } catch (_) {}
    try {
      await MobileAds.instance.initialize();
      _preload();
    } catch (_) {}
  }

  /// Gün anahtarı (yerel yyyy-mm-dd) — günlük sayaç bu güne aittir.
  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Gün değiştiyse günlük interstitial sayacını sıfırla (bellekte).
  void _rolloverIfNeeded(DateTime now) {
    final key = _dateKey(now);
    if (_dayKey != key) {
      _dayKey = key;
      _todayCount = 0;
    }
  }

  Future<void> _persistInterstitialState() async {
    try {
      await _storage.write(key: _kLastShown, value: _lastShown!.toIso8601String());
      await _storage.write(key: _kDayKey, value: _dayKey ?? '');
      await _storage.write(key: _kDayCount, value: _todayCount.toString());
    } catch (_) {}
  }

  Future<void> _persistAppOpenState() async {
    try {
      await _storage.write(
          key: _kAppOpenLast, value: _lastAppOpenShown!.toIso8601String());
    } catch (_) {}
  }

  String get _unitId {
    if (kDebugMode) {
      if (Platform.isAndroid) return _testAndroidUnit;
      if (Platform.isIOS) return _testIosUnit;
      return '';
    }
    if (Platform.isAndroid) return AppConfig.admobAndroidInterstitialId;
    if (Platform.isIOS) return AppConfig.admobIosInterstitialId;
    return '';
  }

  bool get _adsAvailable => _unitId.isNotEmpty;

  /// Bir sonraki gösterim için interstitial'ı ön-yükle (idempotent).
  void _preload() {
    if (!_adsAvailable || _loading || _ad != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: _unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (_) {
          _ad = null;
          _loading = false;
        },
      ),
    );
  }

  /// Tamamlanmış bir kullanıcı kaydından sonra çağrılır (form kaydet, hızlı bez/
  /// beslenme, uyku/emzirme durdur). Süren-sayaç mutasyonlarından (başlat/duraklat/
  /// meme değiştir) çağrılMAZ.
  ///
  /// [suppress] = sessiz saat penceresinde ya da süren bir uyku/emzirme sayacı
  /// varken true; reklam gösterilmez (kayıt yine sayılmaz ki sonra patlamasın).
  Future<void> onRecordSaved({required bool isPremium, bool suppress = false}) async {
    if (isPremium) return; // premium → reklamsız
    if (suppress) return; // sessiz saat / süren sayaç — uygunsuz an
    _recordsSinceAd++;
    if (!_shouldShow()) return;
    await _present();
  }

  bool _shouldShow() {
    if (!_adsAvailable) return false;
    // İlk 24 saat reklamsız (onboarding). Debug'da test edebilmek için atlanır
    // (release'de gerçek grace aynen işler).
    final first = _firstLaunch;
    if (!kDebugMode &&
        first != null &&
        DateTime.now().difference(first) < _graceWindow) {
      return false;
    }
    if (_recordsSinceAd < _minRecords) return false;
    final last = _lastShown;
    if (last != null && DateTime.now().difference(last) < _minGap) return false;
    // Günlük tavan: gün değiştiyse sayaç sıfırlanır, tavana ulaşıldıysa gösterme.
    _rolloverIfNeeded(DateTime.now());
    if (_todayCount >= _maxInterstitialPerDay) return false;
    return true;
  }

  Future<void> _present() async {
    final ad = _ad;
    if (ad == null) {
      // Reklam henüz hazır değil → bu fırsatı tüketme, sayaçları sıfırlama;
      // sıradaki için yükle, bir sonraki uygun kayıtta gösterilir.
      _preload();
      return;
    }
    _ad = null;
    _recordsSinceAd = 0;
    final now = DateTime.now();
    _lastShown = now;
    _rolloverIfNeeded(now);
    _todayCount++;
    unawaited(_persistInterstitialState());
    _showingAd = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _showingAd = false;
        ad.dispose();
        _preload(); // sonraki gösterim için hazırla
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showingAd = false;
        ad.dispose();
        _preload();
      },
    );
    try {
      await ad.show();
    } catch (_) {
      _showingAd = false;
      ad.dispose();
      _preload();
    }
  }

  // ── App-Open reklamı (uygulama öne gelince) ─────────────────────────────────

  String get _appOpenUnitId {
    if (kDebugMode) {
      if (Platform.isAndroid) return _testAndroidAppOpen;
      if (Platform.isIOS) return _testIosAppOpen;
      return '';
    }
    if (Platform.isAndroid) return AppConfig.admobAndroidAppOpenId;
    if (Platform.isIOS) return AppConfig.admobIosAppOpenId;
    return '';
  }

  void _loadAppOpen() {
    if (_appOpenUnitId.isEmpty || _appOpenAd != null) return;
    AppOpenAd.load(
      adUnitId: _appOpenUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _appOpenLoadedAt = DateTime.now();
        },
        onAdFailedToLoad: (_) {
          _appOpenAd = null;
          _appOpenLoadedAt = null;
        },
      ),
    );
  }

  bool get _appOpenValid {
    final at = _appOpenLoadedAt;
    return _appOpenAd != null &&
        at != null &&
        DateTime.now().difference(at) < _appOpenTtl;
  }

  /// Uygulama öne geldiğinde (lifecycle resume) çağrılır. İlk çağrı = soğuk
  /// başlangıç/onboarding → gösterilmez, yalnız ön-yüklenir. Sonraki resume'larda
  /// limitler uygunsa app-open gösterilir. [isPremium] → premium reklamsız.
  ///
  /// [hasBaby] = kullanıcının en az bir bebeği var. Hiç bebek yokken (giriş/
  /// onboarding, bebek ekleme öncesi) app-open gösterilMEZ — interstitial'lar
  /// zaten kayıt kaydından geçtiği için doğal olarak bebek gerektirir.
  Future<void> onAppForeground({
    required bool isPremium,
    required bool hasBaby,
  }) async {
    // İlk foreground (cold start) → gösterme, sadece ön-yükle.
    if (!_firstForegroundSeen) {
      _firstForegroundSeen = true;
      if (hasBaby) _loadAppOpen();
      return;
    }
    if (isPremium) return;
    if (!hasBaby) return; // bebek yok → app-open yok
    if (_showingAd) return; // bir reklam zaten ekranda / reklam dönüşü
    // İlk 24 saat reklamsız (debug atlar).
    final first = _firstLaunch;
    if (!kDebugMode &&
        first != null &&
        DateTime.now().difference(first) < _graceWindow) {
      _loadAppOpen();
      return;
    }
    // App-open kendi min aralığı.
    final lastAo = _lastAppOpenShown;
    if (lastAo != null && DateTime.now().difference(lastAo) < _appOpenMinGap) {
      return;
    }
    // Yakında interstitial çıktıysa üst üste bindirme.
    final lastInt = _lastShown;
    if (lastInt != null && DateTime.now().difference(lastInt) < _minGap) return;
    if (!_appOpenValid) {
      _loadAppOpen();
      return;
    }
    _showAppOpen();
  }

  void _showAppOpen() {
    final ad = _appOpenAd;
    if (ad == null) return;
    _appOpenAd = null;
    _appOpenLoadedAt = null;
    _showingAd = true;
    _lastAppOpenShown = DateTime.now();
    unawaited(_persistAppOpenState());
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _showingAd = false;
        ad.dispose();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        _showingAd = false;
        ad.dispose();
        _loadAppOpen();
      },
    );
    ad.show();
  }
}
