import 'package:flutter/foundation.dart';

/// Bekleme modu anne takibi türü.
enum MomKind {
  weight,
  appointment,
  note;

  static MomKind fromString(String s) =>
      MomKind.values.firstWhere((e) => e.name == s, orElse: () => MomKind.note);
}

/// Anne hafif takip kaydı (kilo / randevu / not) — API §babies/mom-entries.
@immutable
class MomEntry {
  final String id;
  final MomKind kind;
  final DateTime date;
  final double? weightKg;
  final String? title;
  final String? note;

  const MomEntry({
    required this.id,
    required this.kind,
    required this.date,
    this.weightKg,
    this.title,
    this.note,
  });

  factory MomEntry.fromJson(Map<String, dynamic> json) => MomEntry(
        id: json['id'] as String,
        kind: MomKind.fromString(json['kind'] as String),
        date: DateTime.parse(json['date'] as String).toLocal(),
        weightKg: json['weight_kg'] == null
            ? null
            : double.tryParse(json['weight_kg'].toString()),
        title: (json['title'] as String?)?.isEmpty ?? true
            ? null
            : json['title'] as String?,
        note: (json['note'] as String?)?.isEmpty ?? true
            ? null
            : json['note'] as String?,
      );

  Map<String, dynamic> toCreateJson() => {
        'id': id,
        'kind': kind.name,
        'date': date.toUtc().toIso8601String(),
        if (weightKg != null) 'weight_kg': weightKg,
        if (title != null) 'title': title,
        if (note != null) 'note': note,
      };
}
