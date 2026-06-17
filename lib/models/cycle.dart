import 'package:flutter/foundation.dart';

/// Emzirme durumu — ilk adetin ne zaman döneceğini ve doğurganlık uyarılarını etkiler.
enum Breastfeeding {
  exclusive, // sadece anne sütü → LAM geçerli olabilir
  mixed, // karışık
  none; // emzirmiyorum → adet daha erken dönebilir

  static Breastfeeding? fromString(String? s) => s == null || s.isEmpty
      ? null
      : Breastfeeding.values.firstWhere((e) => e.name == s,
          orElse: () => Breastfeeding.exclusive);
}

/// Adet akış miktarı (design ScrCycleEntry).
enum FlowLevel {
  none,
  spotting,
  light,
  medium,
  heavy;

  static FlowLevel? fromString(String? s) => s == null || s.isEmpty
      ? null
      : FlowLevel.values.firstWhere((e) => e.name == s, orElse: () => FlowLevel.light);
}

/// Loşia (lohusalık kanaması) rengi — adet akışından AYRI, doğum sonrası iyileşme izi.
/// Zamanla kırmızı→pembe→kahve→sarı/beyaz seyreder.
enum LochiaColor {
  red,
  pink,
  brown,
  yellowWhite;

  String get apiValue => this == LochiaColor.yellowWhite ? 'yellow_white' : name;

  static LochiaColor? fromString(String? s) {
    if (s == null || s.isEmpty) return null;
    if (s == 'yellow_white') return LochiaColor.yellowWhite;
    return LochiaColor.values
        .firstWhere((e) => e.name == s, orElse: () => LochiaColor.red);
  }
}

/// Adet modülü kullanıcı ayarı (API §13 /cycle/settings). Kullanıcıya özel.
@immutable
class CycleSettings {
  final String? babyId;
  final DateTime? birthDate; // doğum sonrası referans
  final Breastfeeding? breastfeeding;
  final DateTime? firstPeriodDate; // null → ilk adet henüz dönmedi (tahmin yok)
  final Map<String, dynamic> reminders; // period/fertile/pms/log → {on, time}
  final bool showFertilityWarning;
  final bool enabled;

  const CycleSettings({
    this.babyId,
    this.birthDate,
    this.breastfeeding,
    this.firstPeriodDate,
    this.reminders = const {},
    this.showFertilityWarning = true,
    this.enabled = true,
  });

  /// İlk gerçek adet kaydedilmiş mi → döngü tahmini yapılabilir mi?
  bool get periodReturned => firstPeriodDate != null;

  factory CycleSettings.fromJson(Map<String, dynamic> j) => CycleSettings(
        babyId: j['baby'] as String?,
        birthDate: _date(j['birth_date']),
        breastfeeding: Breastfeeding.fromString(j['breastfeeding'] as String?),
        firstPeriodDate: _date(j['first_period_date']),
        reminders: (j['reminders'] as Map?)?.cast<String, dynamic>() ?? const {},
        showFertilityWarning: j['show_fertility_warning'] as bool? ?? true,
        enabled: j['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toPatchJson() => {
        if (babyId != null) 'baby': babyId,
        'birth_date': _iso(birthDate),
        'breastfeeding': breastfeeding?.name ?? '',
        'first_period_date': _iso(firstPeriodDate),
        'reminders': reminders,
        'show_fertility_warning': showFertilityWarning,
        'enabled': enabled,
      };

  CycleSettings copyWith({
    String? babyId,
    DateTime? birthDate,
    Breastfeeding? breastfeeding,
    Object? firstPeriodDate = _sentinel,
    Map<String, dynamic>? reminders,
    bool? showFertilityWarning,
    bool? enabled,
  }) =>
      CycleSettings(
        babyId: babyId ?? this.babyId,
        birthDate: birthDate ?? this.birthDate,
        breastfeeding: breastfeeding ?? this.breastfeeding,
        firstPeriodDate: firstPeriodDate == _sentinel
            ? this.firstPeriodDate
            : firstPeriodDate as DateTime?,
        reminders: reminders ?? this.reminders,
        showFertilityWarning: showFertilityWarning ?? this.showFertilityWarning,
        enabled: enabled ?? this.enabled,
      );

  static const _sentinel = Object();
  static DateTime? _date(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;
  static String? _iso(DateTime? d) =>
      d == null ? null : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Bir güne ait adet/loşia kaydı (API §13 /cycle/entries). Gün başına tek kayıt.
@immutable
class CycleEntry {
  final String id;
  final DateTime date; // yalnız gün (saat anlamsız)
  final FlowLevel? flow;
  final LochiaColor? lochiaColor;
  final List<String> symptoms;
  final int? mood; // 1-5
  final String? note;

  const CycleEntry({
    required this.id,
    required this.date,
    this.flow,
    this.lochiaColor,
    this.symptoms = const [],
    this.mood,
    this.note,
  });

  bool get isPeriod =>
      flow != null && flow != FlowLevel.none && flow != FlowLevel.spotting;

  factory CycleEntry.fromJson(Map<String, dynamic> j) => CycleEntry(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        flow: FlowLevel.fromString(j['flow'] as String?),
        lochiaColor: LochiaColor.fromString(j['lochia_color'] as String?),
        symptoms:
            (j['symptoms'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        mood: j['mood'] as int?,
        note: (j['note'] as String?)?.isEmpty ?? true ? null : j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        'flow': flow?.name ?? '',
        'lochia_color': lochiaColor?.apiValue ?? '',
        'symptoms': symptoms,
        if (mood != null) 'mood': mood,
        'note': note ?? '',
      };
}
