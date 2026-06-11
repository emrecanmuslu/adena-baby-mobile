import 'package:flutter/foundation.dart';

/// Birim tercihleri (FamilySettings.units). Veri kanonik saklanır
/// (hacim=ml, ağırlık=kg, uzunluk=cm, ateş=°C); gösterim/giriş tercihe göre çevrilir.
@immutable
class Units {
  final String volume; // ml | oz
  final String weight; // kg | lb
  final String length; // cm | in
  final String temp; // C | F

  const Units({
    this.volume = 'ml',
    this.weight = 'kg',
    this.length = 'cm',
    this.temp = 'C',
  });

  factory Units.fromMap(Map<String, dynamic>? m) => Units(
        volume: m?['volume'] as String? ?? 'ml',
        weight: m?['weight'] as String? ?? 'kg',
        length: m?['length'] as String? ?? 'cm',
        temp: m?['temp'] as String? ?? 'C',
      );

  Map<String, dynamic> toMap() =>
      {'volume': volume, 'weight': weight, 'length': length, 'temp': temp};

  Units copyWith({String? volume, String? weight, String? length, String? temp}) =>
      Units(
        volume: volume ?? this.volume,
        weight: weight ?? this.weight,
        length: length ?? this.length,
        temp: temp ?? this.temp,
      );

  // ---- Sabitler ----
  static const _mlPerOz = 29.5735;
  static const _gPerLb = 0.453592; // kg
  static const _cmPerIn = 2.54;

  String get volumeLabel => volume == 'oz' ? 'oz' : 'ml';
  String get weightLabel => weight == 'lb' ? 'lb' : 'kg';
  String get lengthLabel => length == 'in' ? 'in' : 'cm';

  // ---- Giriş (tercih birimi) → kanonik saklama ----
  double volumeToCanonical(double v) => volume == 'oz' ? v * _mlPerOz : v;
  double weightToCanonical(double v) => weight == 'lb' ? v * _gPerLb : v;
  double lengthToCanonical(double v) => length == 'in' ? v * _cmPerIn : v;

  // ---- Kanonik → tercih birimi (gösterim/düzenleme) ----
  double volumeFromCanonical(num ml) => volume == 'oz' ? ml / _mlPerOz : ml.toDouble();
  double weightFromCanonical(num kg) => weight == 'lb' ? kg / _gPerLb : kg.toDouble();
  double lengthFromCanonical(num cm) => length == 'in' ? cm / _cmPerIn : cm.toDouble();

  // ---- Formatlı gösterim (özetler) ----
  String fmtVolume(num ml) {
    final v = volumeFromCanonical(ml);
    final s = volume == 'oz' ? v.toStringAsFixed(1) : v.round().toString();
    return '$s $volumeLabel';
  }

  String fmtWeight(num kg) {
    final v = weightFromCanonical(kg);
    return '${v.toStringAsFixed(weight == 'lb' ? 1 : 2)} $weightLabel';
  }

  String fmtLength(num cm) {
    final v = lengthFromCanonical(cm);
    return '${v.toStringAsFixed(1)} $lengthLabel';
  }

  /// Düzenleme alanı başlangıç değeri (gereksiz ondalık olmadan).
  String editValue(double v, {bool decimal = false}) {
    if (!decimal && v == v.roundToDouble()) return v.round().toString();
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? v.round().toString() : s;
  }
}
