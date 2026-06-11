import 'package:flutter/foundation.dart';

/// Kullanıcı modeli — API sözleşmesi: {id, email, name, avatar_color, created_at}.
@immutable
class User {
  final String id;
  final String email;
  final String name;
  final String? avatarColor;
  final DateTime? createdAt;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.avatarColor,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        avatarColor: json['avatar_color'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'avatar_color': avatarColor,
        'created_at': createdAt?.toIso8601String(),
      };

  /// Görünen ad boşsa e-postanın yerel kısmını kullan.
  String get displayName => name.trim().isNotEmpty ? name : email.split('@').first;
}
