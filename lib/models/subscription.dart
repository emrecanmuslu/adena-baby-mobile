import 'package:flutter/foundation.dart';

/// Abonelik durumu (API §9). Kaynak gerçek = RevenueCat → backend yansıması.
/// `isPremium` sunucu-doğrulamalı (`is_premium`): tier premium + süre dolmamış.
@immutable
class Subscription {
  final String tier;
  final String? platform;
  final String? store;
  final String? productId;
  final DateTime? expiresAt;
  final bool willRenew;

  /// Sunucu-doğrulamalı premium (`is_premium`): tier premium + süre dolmamış.
  final bool isPremium;

  const Subscription({
    required this.tier,
    this.platform,
    this.store,
    this.productId,
    this.expiresAt,
    this.willRenew = false,
    this.isPremium = false,
  });

  /// Lifetime (tek-seferlik) premium: aktif ama yenileme/bitiş yok.
  bool get isLifetime => isPremium && expiresAt == null;

  /// Premium süresi dolmuş (yenilenmedi/iptal): tier premium ama artık aktif
  /// değil + bitiş tarihi var. Free'ye düştü ama veri yerelde duruyor (ayna).
  bool get isLapsed => tier == 'premium' && !isPremium && expiresAt != null;

  /// Bitişten bu yana geçen güne göre 60 günlük bulut grace'inden kalan gün.
  /// Süre sonunda backend cloud kopyayı siler; yerel veri her hâlükârda kalır.
  int graceDaysLeft({int graceDays = 60}) {
    final exp = expiresAt;
    if (exp == null) return 0;
    final left = graceDays - DateTime.now().difference(exp).inDays;
    return left < 0 ? 0 : left;
  }

  factory Subscription.fromJson(Map<String, dynamic> json) {
    final tier = json['tier'] as String? ?? 'free';
    return Subscription(
      tier: tier,
      platform: json['platform'] as String?,
      store: json['store'] as String?,
      productId: json['product_id'] as String?,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      willRenew: json['will_renew'] as bool? ?? false,
      // Eski sunucu yanıtında is_premium yoksa tier'a düş.
      isPremium: json['is_premium'] as bool? ?? (tier == 'premium'),
    );
  }
}
