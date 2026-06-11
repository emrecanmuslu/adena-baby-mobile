import 'package:flutter/foundation.dart';

import 'user.dart';

/// Bir bebeğe üyelik (rol-bazlı paylaşım). API_SOZLESME §3.
@immutable
class Membership {
  final User user;
  final String role; // owner|parent|caregiver
  final DateTime? joinedAt;

  const Membership({required this.user, required this.role, this.joinedAt});

  bool get isOwner => role == 'owner';

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        role: json['role'] as String? ?? 'parent',
        joinedAt: json['joined_at'] != null
            ? DateTime.tryParse(json['joined_at'] as String)
            : null,
      );

  static String roleLabel(String role) => switch (role) {
        'owner' => 'Sahip',
        'parent' => 'Ebeveyn',
        'caregiver' => 'Bakıcı',
        _ => role,
      };
}
