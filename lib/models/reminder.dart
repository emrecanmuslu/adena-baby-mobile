import 'package:flutter/foundation.dart';

/// Hatırlatıcı (API §health). Tür + serbest-biçim schedule JSON + açık/kapalı.
/// Türler: custom (kullanıcı tanımlı), appt (randevu), feed (sonraki beslenme),
/// vitamin (eski). schedule iki şekil: günlük {repeat:'daily', time:'HH:MM',
/// title?} ya da tek-sefer {repeat:'once', at:ISO8601, title?}.
@immutable
class Reminder {
  final int id;
  final String type;
  final Map<String, dynamic> schedule;
  final bool enabled;
  final DateTime createdAt;

  const Reminder({
    required this.id,
    required this.type,
    required this.schedule,
    required this.enabled,
    required this.createdAt,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: json['id'] as int,
        type: json['type'] as String? ?? 'vitamin',
        schedule: (json['schedule'] as Map?)?.cast<String, dynamic>() ?? const {},
        enabled: json['enabled'] as bool? ?? true,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}
