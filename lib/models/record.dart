import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Kayıt tipleri (API ile ortak string değerler).
enum RecordType {
  diaper,
  feed,
  pumping,
  sleep,
  growth,
  temperature,
  medication,
  bath,
  appointment;

  static RecordType fromString(String s) =>
      RecordType.values.firstWhere((e) => e.name == s, orElse: () => RecordType.feed);
}

/// Polimorfik kayıt. Tipe özgü alanlar [data] içinde (API_SOZLESME §4).
@immutable
class Record {
  final String id;
  final String baby;
  final RecordType type;
  final DateTime ts;
  final Map<String, dynamic> data;
  final bool isDeleted;
  final String? createdBy; // ekleyen kullanıcı id'si (sunucudan; timeline "kim ekledi")

  const Record({
    required this.id,
    required this.baby,
    required this.type,
    required this.ts,
    this.data = const {},
    this.isDeleted = false,
    this.createdBy,
  });

  /// Aktif (bitmemiş) uyku sayacı mı?
  bool get isOngoingSleep =>
      type == RecordType.sleep && (data['end_ts'] == null);

  /// Aktif (bitmemiş) emzirme sayacı mı? (kronometreyle başlatılmış, henüz
  /// durdurulmamış). Elle girilen emzirme kayıtlarında start_ts olmaz.
  bool get isOngoingBreast =>
      type == RecordType.feed &&
      data['sub'] == 'breast' &&
      data.containsKey('start_ts') &&
      data['end_ts'] == null;

  factory Record.fromJson(Map<String, dynamic> json) => Record(
        id: json['id'] as String,
        baby: (json['baby'] ?? json['baby_id']) as String,
        type: RecordType.fromString(json['type'] as String),
        ts: DateTime.parse(json['ts'] as String).toLocal(),
        data: json['data'] is Map
            ? Map<String, dynamic>.from(json['data'] as Map)
            : (json['data'] is String
                ? Map<String, dynamic>.from(jsonDecode(json['data'] as String) as Map)
                : <String, dynamic>{}),
        isDeleted: json['is_deleted'] as bool? ?? false,
        createdBy: json['created_by'] as String?,
      );

  String get dataJson => jsonEncode(data);

  Record copyWith(
          {Map<String, dynamic>? data,
          DateTime? ts,
          bool? isDeleted,
          String? createdBy}) =>
      Record(
        id: id,
        baby: baby,
        type: type,
        ts: ts ?? this.ts,
        data: data ?? this.data,
        isDeleted: isDeleted ?? this.isDeleted,
        createdBy: createdBy ?? this.createdBy,
      );
}
