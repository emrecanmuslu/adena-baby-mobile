import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../data/subscription_repository.dart';
import 'config.dart';

/// İçerik/liste ekranlarının altına konan AdMob banner'ı.
///
/// - **Premium kullanıcıda hiç yüklenmez/görünmez** (reklamsız).
/// - Birim id yoksa veya reklam yüklenemezse **sıfır yükseklik** döner
///   (`bottomNavigationBar` olarak verilince düzeni bozmaz).
/// - Debug'da Google resmî **test** banner'ı, release'de `dart_defines.json`
///   banner birim id'si kullanılır.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({super.key});

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  static String get _unitId {
    if (kDebugMode) {
      if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/6300978111';
      if (Platform.isIOS) return 'ca-app-pub-3940256099942544/2934735716';
      return '';
    }
    if (Platform.isAndroid) return AppConfig.admobAndroidBannerId;
    if (Platform.isIOS) return AppConfig.admobIosBannerId;
    return '';
  }

  @override
  void initState() {
    super.initState();
    // Premium → banner hiç yüklenmez.
    if (ref.read(isPremiumProvider)) return;
    final id = _unitId;
    if (id.isEmpty) return;
    final ad = BannerAd(
      adUnitId: id,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isPremiumProvider)) return const SizedBox.shrink();
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: double.infinity,
        height: ad.size.height.toDouble(),
        child: Center(
          child: SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
        ),
      ),
    );
  }
}
