import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:purchases_flutter/purchases_flutter.dart';

import 'config.dart';

/// RevenueCat sarmalayıcısı — premium satın alma + entitlement okuma.
///
/// Anahtar boşsa veya platform (desktop) desteklemiyorsa sessizce devre dışı
/// kalır (`isConfigured == false`): premium durumu yalnız backend'den okunur,
/// satın alma butonları kapanır. Tüm çağrılar yapılandırılmamışken güvenli no-op.
///
/// Mimari: satın alma RC SDK ile yapılır; entitlement'ın **kaynak gerçeği**
/// backend'tir (RC webhook + /me/subscription/refresh). UI'da gating için
/// `subscriptionProvider.is_premium` kullanılır; RC dinleyicisi değişimde
/// backend'i tazeler (bkz. premiumSyncProvider).
class RevenueCatService {
  RevenueCatService._();
  static final RevenueCatService instance = RevenueCatService._();

  /// RC dashboard'daki entitlement tanımlayıcısı (Offerings ile aynı olmalı).
  static const String entitlementId = 'Adena Baby Pro';

  bool _configured = false;
  bool get isConfigured => _configured;

  String get _key {
    if (Platform.isAndroid) return AppConfig.revenueCatAndroidKey;
    if (Platform.isIOS) return AppConfig.revenueCatIosKey;
    return '';
  }

  /// Açılışta bir kez çağrılır. Eksik anahtar/hata uygulamayı ENGELLEMEZ.
  Future<void> configure() async {
    if (_configured) return;
    final key = _key;
    if (key.isEmpty) return;
    try {
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
    } catch (_) {
      _configured = false;
    }
  }

  /// Giriş sonrası: RC kullanıcı kimliğini bizim `user.id`'ye sabitle (webhook
  /// app_user_id eşleşmesi için). Henüz configure olmadıysa önce dener.
  /// Yalnız test: identify çağrılarını gözlemlemek için kanca.
  @visibleForTesting
  void Function(String userId)? identifyHook;

  Future<void> identify(String userId) async {
    identifyHook?.call(userId);
    if (!_configured) await configure();
    if (!_configured) return;
    try {
      await Purchases.logIn(userId);
    } catch (_) {}
  }

  /// Çıkışta anonim kimliğe dön.
  Future<void> logoutUser() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
    } catch (_) {}
  }

  /// D6: `configure()` main'de unawaited → ilk build'de henüz hazır olmayabilir;
  /// dinleyici düşmesin diye kuyruğa alınır, configure bitince takılır.
  final List<void Function(CustomerInfo)> _pendingListeners = [];

  void addUpdateListener(void Function(CustomerInfo) cb) {
    if (_configured) {
      Purchases.addCustomerInfoUpdateListener(cb);
      return;
    }
    _pendingListeners.add(cb);
    configure().then((_) {
      if (!_configured) return;
      for (final l in List.of(_pendingListeners)) {
        _pendingListeners.remove(l);
        Purchases.addCustomerInfoUpdateListener(l);
      }
    });
  }

  void removeUpdateListener(void Function(CustomerInfo) cb) {
    _pendingListeners.remove(cb);
    if (!_configured) return;
    Purchases.removeCustomerInfoUpdateListener(cb);
  }

  bool isEntitled(CustomerInfo info) =>
      info.entitlements.active.containsKey(entitlementId);

  /// Anlık entitlement (offline cache'ten de okunabilir).
  Future<bool> currentlyEntitled() async {
    if (!_configured) return false;
    try {
      return isEntitled(await Purchases.getCustomerInfo());
    } catch (_) {
      return false;
    }
  }

  /// Aktif teklif (paketler: aylık/yıllık/lifetime). Yoksa null.
  Future<Offering?> currentOffering() async {
    if (!_configured) return null;
    try {
      return (await Purchases.getOfferings()).current;
    } catch (_) {
      return null;
    }
  }

  /// Paketi satın al. Döner: işlem sonrası entitlement aktif mi.
  /// Kullanıcı iptal ederse `PurchasesErrorCode.purchaseCancelledError` fırlatır.
  Future<bool> purchase(Package package) async {
    if (!_configured) return false;
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return isEntitled(result.customerInfo);
  }

  /// Önceki satın almaları geri yükle (cihaz değişimi / yeniden kurulum).
  Future<bool> restore() async {
    if (!_configured) return false;
    return isEntitled(await Purchases.restorePurchases());
  }
}
