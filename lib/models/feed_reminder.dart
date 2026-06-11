import 'package:flutter/foundation.dart';

import '../core/i18n.dart';

/// Beslenme hatırlatıcı ayarı (family-settings 'feed_reminder' altında saklanır).
/// Son (baz türü) beslenmesi + sabit aralıktan bir sonraki beslenmeyi kestirir;
/// ana uyarı + opsiyonel ön-hatırlatma planlanır. Sesli alarm varsayılan kapalı.
@immutable
class FeedReminderConfig {
  final bool enabled;
  final int intervalMin; // son beslenmeden sonraki süre (varsayılan 2 saat)
  final String baseType; // 'all' | 'breast' | 'formula' — baz alınan beslenme türü
  final int preMin; // ön-hatırlatma dk (0 = kapalı)
  final bool soundEnabled; // sesli/heads-up alarm (varsayılan kapalı = sessiz bildirim)

  const FeedReminderConfig({
    this.enabled = false,
    this.intervalMin = 120,
    this.baseType = 'all',
    this.preMin = 30,
    this.soundEnabled = false,
  });

  factory FeedReminderConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const FeedReminderConfig();
    int asInt(dynamic v, int d) => v is num ? v.toInt() : d;
    return FeedReminderConfig(
      enabled: m['enabled'] as bool? ?? false,
      intervalMin: asInt(m['interval_min'], 120),
      baseType: m['base_type'] as String? ?? 'all',
      preMin: asInt(m['pre_min'], 30),
      soundEnabled: m['sound'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'interval_min': intervalMin,
        'base_type': baseType,
        'pre_min': preMin,
        'sound': soundEnabled,
      };

  FeedReminderConfig copyWith({
    bool? enabled,
    int? intervalMin,
    String? baseType,
    int? preMin,
    bool? soundEnabled,
  }) =>
      FeedReminderConfig(
        enabled: enabled ?? this.enabled,
        intervalMin: intervalMin ?? this.intervalMin,
        baseType: baseType ?? this.baseType,
        preMin: preMin ?? this.preMin,
        soundEnabled: soundEnabled ?? this.soundEnabled,
      );

  /// Kısa Türkçe özet (hatırlatıcı kartı için).
  String get summary {
    if (!enabled) return tr('Kapalı');
    final base = switch (baseType) {
      'breast' => tr('anne sütü'),
      'formula' => tr('mama'),
      _ => tr('beslenme'),
    };
    final pre = preMin > 0 ? trp(' · {n} dk önce uyarı', {'n': preMin}) : '';
    final snd = soundEnabled ? tr(' · sesli') : '';
    return trp('Son {base} sonrası her {iv}{pre}{snd}', {
      'base': base,
      'iv': _hm(intervalMin),
      'pre': pre,
      'snd': snd,
    });
  }

  static String _hm(int min) {
    final h = min ~/ 60, m = min % 60;
    if (h > 0 && m > 0) return trp('{h} sa {m} dk', {'h': h, 'm': m});
    if (h > 0) return trp('{h} saat', {'h': h});
    return trp('{m} dk', {'m': m});
  }
}
