import 'package:flutter/foundation.dart';

/// İlaç/vitamin planı — cihaz-yerel (bkz. `MedicationPlans` tablosu). Yalnız
/// ZAMANLAMAYI taşır; "verildi" durumu aile-paylaşımlı `Record`
/// (RecordType.medication) ile takip edilir (bkz. core/medication.dart).
@immutable
class MedicationPlan {
  final int id;
  final String name;
  final String dose;
  final List<String> times; // "HH:MM", günde birden çok doz desteklenir
  final bool active;
  final DateTime createdAt;

  const MedicationPlan({
    required this.id,
    required this.name,
    required this.dose,
    required this.times,
    required this.active,
    required this.createdAt,
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
