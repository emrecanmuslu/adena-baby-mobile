import 'dart:async' show unawaited;

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';

/// Native "uygulamayı puanla" prompt'u — iOS'ta StoreKit ([SKStoreReviewController]),
/// Android'de Google Play In-App Review API. Apple/Google'ın kendi kotası var
/// (iOS: 365 günde en fazla 3 gösterim, karar tamamen sistemde) — biz sadece
/// "uygun an" tespiti yapıp isteği yolluyoruz, gösterilip gösterilmeyeceğini
/// asla bilemeyiz/garanti edemeyiz.
///
/// Tetikleme kuralı (AdService'teki gibi kalıcı, SharedPreferences'ta):
/// en az [_minRecords] anlamlı kayıt VE kurulumdan [_graceWindow] geçmiş VE
/// son istekten [_cooldown] geçmiş VE ömür boyu en fazla [_maxAsks] kez
/// sorulmuş VE o an/az önce bir reklam gösterilmiyor (iki sistem dialogu
/// üst üste binmesin) olmalı.
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  static const int _minRecords = 6;
  static const Duration _graceWindow = Duration(days: 2);
  static const Duration _cooldown = Duration(days: 90);
  static const int _maxAsks = 3;
  // Az önce reklam gösterildiyse (interstitial/app-open) bu kadar süre daha
  // puanlama dialogu istenmez — iki sistem prompt'u art arda gelmesin.
  static const Duration _adQuiet = Duration(minutes: 2);

  static const _kFirstLaunch = 'review_first_launch';
  static const _kTotalRecords = 'review_total_records';
  static const _kLastAsked = 'review_last_asked';
  static const _kAskCount = 'review_ask_count';

  bool _loaded = false;
  int _totalRecords = 0;
  DateTime? _firstLaunch;
  DateTime? _lastAsked;
  int _askCount = 0;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final first = prefs.getString(_kFirstLaunch);
      if (first != null) {
        _firstLaunch = DateTime.tryParse(first);
      } else {
        _firstLaunch = DateTime.now();
        await prefs.setString(_kFirstLaunch, _firstLaunch!.toIso8601String());
      }
      _totalRecords = prefs.getInt(_kTotalRecords) ?? 0;
      _askCount = prefs.getInt(_kAskCount) ?? 0;
      final last = prefs.getString(_kLastAsked);
      _lastAsked = last != null ? DateTime.tryParse(last) : null;
    } catch (_) {}
  }

  /// Anlamlı bir kullanıcı kaydı tamamlandığında çağrılır (form kaydet, hızlı
  /// bez/beslenme, uyku/emzirme durdur — [[AdService.onRecordSaved]] ile aynı
  /// noktalardan). Süren-sayaç mutasyonlarından (başlat/duraklat) çağrılmaz.
  Future<void> onRecordSaved() async {
    await _ensureLoaded();
    _totalRecords++;
    unawaited(_persistCount());
    if (!_shouldAsk()) return;
    await _ask();
  }

  bool _shouldAsk() {
    if (_askCount >= _maxAsks) return false;
    if (_totalRecords < _minRecords) return false;
    final first = _firstLaunch;
    if (first != null && DateTime.now().difference(first) < _graceWindow) {
      return false;
    }
    final last = _lastAsked;
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      return false;
    }
    if (AdService.instance.isShowingAd) return false;
    final lastAd = AdService.instance.lastAdShownAt;
    if (lastAd != null && DateTime.now().difference(lastAd) < _adQuiet) {
      return false;
    }
    return true;
  }

  Future<void> _persistCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTotalRecords, _totalRecords);
    } catch (_) {}
  }

  Future<void> _ask() async {
    // Sayaçları istek ANINDA güncelle (requestReview() gösterilip
    // gösterilmediğini asla bildirmez — "denedik" kalıcı sayılır, aksi halde
    // her kayıtta tekrar tekrar denenip kota anlamsızca tükenir).
    _askCount++;
    _lastAsked = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kAskCount, _askCount);
      await prefs.setString(_kLastAsked, _lastAsked!.toIso8601String());
    } catch (_) {}
    try {
      final inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
      }
    } catch (_) {}
  }
}
