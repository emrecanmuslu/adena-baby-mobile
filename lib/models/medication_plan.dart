import 'package:flutter/foundation.dart';

/// İlaç/vitamin planı — aile paylaşımlı (bkz. `MedicationPlans` tablosu). Yalnız
/// ZAMANLAMAYI taşır; "verildi" durumu aile-paylaşımlı `Record`
/// (RecordType.medication) ile takip edilir (bkz. core/medication.dart).
/// [id] cihaza özel yerel kimliktir (bildirim id'leri bundan türer).
@immutable
class MedicationPlan {
  final int id;
  final String name;
  final String dose;
  final List<String> times; // "HH:MM", günde birden çok doz desteklenir
  final bool active;
  final DateTime createdAt;
  /// N2/KB-10: bakıcı cihazında KB-8 öncesinden kalmış, sunucuya hiç gitmemiş
  /// (dirty) plan — yalnız bu cihazda; ailenle paylaşılmadı. Hatırlatıcısı
  /// çalışır, bakıcı silebilir, düzenleyemez.
  final bool localOnly;

  const MedicationPlan({
    required this.id,
    required this.name,
    required this.dose,
    required this.times,
    required this.active,
    required this.createdAt,
    this.localOnly = false,
  });

  MedicationPlan copyWith({
    String? name,
    String? dose,
    List<String>? times,
    bool? active,
  }) =>
      MedicationPlan(
        id: id,
        name: name ?? this.name,
        dose: dose ?? this.dose,
        times: times ?? this.times,
        active: active ?? this.active,
        createdAt: createdAt,
      );
}
