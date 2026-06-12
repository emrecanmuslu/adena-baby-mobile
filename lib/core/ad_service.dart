import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import 'adena_icons.dart';
import 'config.dart';
import 'i18n.dart';
import 'theme.dart';

/// Reklam overlay'ini (placeholder/interstitial) herhangi bir ekranın üstünden
/// göstermek için kök navigator. MaterialApp.router'a verilir (router.dart).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Frekans-limitli geçiş (interstitial) reklam yöneticisi.
///
/// Optimizasyon ([[para-kazanma-modeli]] yumuşak doz): kaydı BLOKLAMAZ — kayıt
/// tamamlandıktan sonra çağrılır; premium muaftır; en az [_minRecords] kayıt VE
/// son reklamdan [_minGap] geçmeden gösterilmez (peş peşe girişte çıkmaz).
///
/// AdMob birim id'si yoksa gerçek reklam yerine geliştirme **placeholder**'ı
/// gösterilir — böylece frekans mantığı token'sız da test edilir.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const int _minRecords = 3;
  static const Duration _minGap = Duration(minutes: 3);
  static const Duration _graceWindow = Duration(hours: 24); // ilk gün reklamsız
  static const _storage = FlutterSecureStorage();
  static const _kFirstLaunch = 'ad_first_launch';

  int _recordsSinceAd = 0;
  DateTime? _lastShown;
  DateTime? _firstLaunch;

  /// Açılışta bir kez. İlk kurulum zamanını kalıcı saklar (ilk 24 saat reklamsız —
  /// onboarding sırasında kullanıcıyı kaçırmamak için). Hata uygulamayı engellemez.
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
    } catch (_) {}
  }

  String get _unitId {
    if (Platform.isAndroid) return AppConfig.admobAndroidInterstitialId;
    if (Platform.isIOS) return AppConfig.admobIosInterstitialId;
    return '';
  }

  bool get _realAdsConfigured => _unitId.isNotEmpty;

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
    _recordsSinceAd = 0;
    _lastShown = DateTime.now();
    await _present();
  }

  bool _shouldShow() {
    // İlk 24 saat reklamsız (onboarding).
    final first = _firstLaunch;
    if (first != null && DateTime.now().difference(first) < _graceWindow) {
      return false;
    }
    if (_recordsSinceAd < _minRecords) return false;
    final last = _lastShown;
    if (last != null && DateTime.now().difference(last) < _minGap) return false;
    return true;
  }

  Future<void> _present() async {
    // Kayıt sheet'i kendi Navigator.pop'unu yapana kadar bekle — yoksa o pop
    // bizim dialog'umuzu kapatır (ikisi de kök navigator'da). Sheet kapanış
    // animasyonu (~250ms) bitsin diye küçük gecikme.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    if (_realAdsConfigured) {
      // TODO(reklam): google_mobile_ads ile InterstitialAd yükle + göster.
      // SDK/anahtar gelene kadar aşağıdaki placeholder gösterilir.
    }
    // ctx await'ten SONRA taze alındı (kök navigator key context'i, State değil).
    // ignore: use_build_context_synchronously
    await _showPlaceholder(ctx);
  }

  Future<void> _showPlaceholder(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reklam alanı placeholder'ı
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.feedBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line, width: 1),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AdenaIcon('star', size: 30, color: AppColors.muted, sw: 2),
                    const SizedBox(height: 8),
                    Text(tr('Reklam alanı'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(tr('Geliştirme placeholder’ı'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        rootNavigatorKey.currentContext?.push('/premium');
                      },
                      child: Text(tr('Reklamsız yap'),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.coral,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(tr('Kapat'),
                          style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
