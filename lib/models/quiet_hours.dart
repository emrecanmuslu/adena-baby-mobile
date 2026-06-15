import 'package:flutter/foundation.dart';

import '../core/i18n.dart';

/// Sessiz saat penceresi (family-settings 'quiet_hours' altında saklanır).
/// Belirlenen saat aralığında bildirimler sessizce gelir (ses/titreşim yok);
/// "Sesli alarm" açık olsa bile bu pencere her zaman kazanır. Gece yarısını
/// aşan aralıkları (ör. 22:00–07:00) destekler.
@immutable
class QuietHours {
  final bool enabled;
  final int startMin; // gün içi dakika (0–1439), varsayılan 22:00
  final int endMin; // varsayılan 07:00

  const QuietHours({
    this.enabled = false,
    this.startMin = 22 * 60,
    this.endMin = 7 * 60,
  });

  factory QuietHours.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const QuietHours();
    int asInt(dynamic v, int d) => v is num ? v.toInt() : d;
    return QuietHours(
      enabled: m['enabled'] as bool? ?? false,
      startMin: asInt(m['start_min'], 22 * 60),
      endMin: asInt(m['end_min'], 7 * 60),
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'start_min': startMin,
        'end_min': endMin,
      };

  QuietHours copyWith({bool? enabled, int? startMin, int? endMin}) => QuietHours(
        enabled: enabled ?? this.enabled,
        startMin: startMin ?? this.startMin,
        endMin: endMin ?? this.endMin,
      );

  /// [t] anı sessiz saat penceresinde mi? Pencere kapalıysa ya da sıfır
  /// genişlikteyse false. Gece yarısını aşan aralığı (start > end) destekler.
  bool covers(DateTime t) {
    if (!enabled || startMin == endMin) return false;
    final m = t.hour * 60 + t.minute;
    if (startMin < endMin) return m >= startMin && m < endMin; // aynı gün
    return m >= startMin || m < endMin; // gece yarısını aşar
  }

  static String hhmm(int min) {
    final h = (min ~/ 60) % 24, m = min % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String get label => '${hhmm(startMin)} – ${hhmm(endMin)}';
  String get summary => enabled ? trp('{r} arası sessiz', {'r': label}) : tr('Kapalı');
}
