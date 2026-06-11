import 'package:flutter/foundation.dart';

/// Bebek durumu: gebelik (bekleme) / doğmuş (takip).
enum BabyStatus { expecting, born }

enum BabyGender { male, female, unknown }

/// Bebek modeli — API_SOZLESME.md §2.
@immutable
class Baby {
  final String id;
  final String name;
  final BabyGender gender;
  final String? photo;
  final BabyStatus status;
  final DateTime? birthDate;
  final int? gestationalAgeAtBirthWeeks;
  final DateTime? dueDate;
  final DateTime? lastMenstrualDate;
  final String? myRole; // owner|parent|caregiver

  const Baby({
    required this.id,
    required this.name,
    this.gender = BabyGender.unknown,
    this.photo,
    this.status = BabyStatus.born,
    this.birthDate,
    this.gestationalAgeAtBirthWeeks,
    this.dueDate,
    this.lastMenstrualDate,
    this.myRole,
  });

  bool get isExpecting => status == BabyStatus.expecting;

  factory Baby.fromJson(Map<String, dynamic> json) => Baby(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        gender: _genderFrom(json['gender'] as String?),
        photo: json['photo'] as String?,
        status: (json['status'] as String?) == 'expecting'
            ? BabyStatus.expecting
            : BabyStatus.born,
        birthDate: _date(json['birth_date']),
        gestationalAgeAtBirthWeeks: json['gestational_age_at_birth_weeks'] as int?,
        dueDate: _date(json['due_date']),
        lastMenstrualDate: _date(json['last_menstrual_date']),
        myRole: json['my_role'] as String?,
      );

  /// POST /babies için gövde. id istemci-üretimli (offline-first).
  Map<String, dynamic> toCreateJson() => {
        'id': id,
        'name': name,
        if (gender != BabyGender.unknown) 'gender': gender.name,
        'status': status.name,
        if (birthDate != null) 'birth_date': _isoDate(birthDate!),
        if (gestationalAgeAtBirthWeeks != null)
          'gestational_age_at_birth_weeks': gestationalAgeAtBirthWeeks,
        if (dueDate != null) 'due_date': _isoDate(dueDate!),
        if (lastMenstrualDate != null) 'last_menstrual_date': _isoDate(lastMenstrualDate!),
      };

  static BabyGender _genderFrom(String? v) => switch (v) {
        'male' => BabyGender.male,
        'female' => BabyGender.female,
        _ => BabyGender.unknown,
      };

  static DateTime? _date(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

  /// Sadece tarih (YYYY-MM-DD) — API doğum/tahmini tarih alanları gün hassasiyetinde.
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
