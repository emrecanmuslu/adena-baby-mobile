import 'package:flutter/foundation.dart';

import 'user.dart';

/// Aktivite akışı olayı (API §sharing): "{actor} {action}". Actor SET_NULL → nullable.
/// action ör: "created_feed", "created_diaper", "started_sleep".
@immutable
class ActivityEvent {
  final String id;
  final User? actor;
  final String action;
  final String? recordRef;
  final DateTime ts;

  const ActivityEvent({
    required this.id,
    required this.actor,
    required this.action,
    this.recordRef,
    required this.ts,
  });

  factory ActivityEvent.fromJson(Map<String, dynamic> json) => ActivityEvent(
        id: json['id'] as String,
        actor: json['actor'] is Map
            ? User.fromJson((json['actor'] as Map).cast<String, dynamic>())
            : null,
        action: json['action'] as String? ?? '',
        recordRef: json['record_ref'] as String?,
        ts: DateTime.tryParse(json['ts'] as String? ?? '')?.toLocal() ??
            DateTime.now(),
      );
}
