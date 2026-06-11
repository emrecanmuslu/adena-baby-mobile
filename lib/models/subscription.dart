import 'package:flutter/foundation.dart';

/// Abonelik durumu (API §9). tier: free|premium.
@immutable
class Subscription {
  final String tier;
  final String? platform;
  final DateTime? expiresAt;

  const Subscription({required this.tier, this.platform, this.expiresAt});

  bool get isPremium => tier == 'premium';

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        tier: json['tier'] as String? ?? 'free',
        platform: json['platform'] as String?,
        expiresAt: json['expires_at'] != null
            ? DateTime.tryParse(json['expires_at'] as String)
            : null,
      );
}
