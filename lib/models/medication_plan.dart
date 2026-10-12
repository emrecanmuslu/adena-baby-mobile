import 'package:flutter/foundation.dart';

/// Plan türü (ILAC-TASARIM §1a): düzenli (saatli) ya da ihtiyaç halinde (PRN).
enum MedKind {
  scheduled('scheduled'),
  prn('prn');

  final String wire;
  const MedKind(this.wire);
  static MedKind fromWire(String? s) =>
      values.firstWhere((k) => k.wire == s, orElse: () => MedKind.scheduled);
}

/// Sıklık türü (K9): her gün · her X saatte · N günde bir · haftalık.
enum MedFreq {
  daily('daily'),
  interval('interval'),
  everyNDays('every_n_days'),
  weekly('weekly');

  final String wire;
  const MedFreq(this.wire);
  static MedFreq fromWire(String? s) =>
      values.firstWhere((f) => f.wire == s, orElse: () => MedFreq.daily);
}

/// Duraklatma aralığı — [to] null = hâlâ duraklatılmış.
@immutable
class MedPause {
  final DateTime from;
  final DateTime? to;
  const MedPause(this.from, [this.to]);

  bool covers(DateTime t) => !t.isBefore(from) && (to == null || t.isBefore(to!));

  @override
  bool operator ==(Object other) =>
      other is MedPause && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

/// İlaç/vitamin planı — aile paylaşımlı (bkz. `MedicationPlans` tablosu). Yalnız
/// ZAMANLAMAYI taşır; "verildi" durumu aile-paylaşımlı `Record`
/// (RecordType.medication) ile takip edilir (bkz. core/medication/).
/// [id] cihaza özel yerel kimliktir; aile içi ortak kimlik [uuid].
@immutable
class MedicationPlan {
  final int id;
  final String name;
  final String dose;
  /// "HH:MM". daily/everyNDays/weekly: gün içi saatler; interval: [0] çapa saati;
  /// prn: boş.
  final List<String> times;
  /// false = duraklatıldı.
  final bool active;
  final DateTime createdAt;
  /// N2/KB-10: bakıcı cihazında KB-8 öncesinden kalmış, sunucuya hiç gitmemiş
  /// (dirty) plan — yalnız bu cihazda; ailenle paylaşılmadı. Hatırlatıcısı
  /// çalışır, bakıcı silebilir, düzenleyemez.
  final bool localOnly;

  // ── İlaç v2 ──
  final String? uuid;
  final MedKind kind;
  final MedFreq freq;
  final int? intervalHours;
  final int? everyNDays;
  final List<int> weekdays; // ISO 1..7
  /// Yerel takvim günleri (saat 00:00). Bitiş DAHİL; null = süresiz.
  final DateTime? startDate;
  final DateTime? endDate;
  final int? prnMinIntervalMin;
  final int? prnMaxPerDay;
  final List<MedPause> pauses;
  /// Zamanlamanın (saatler/sıklık) son değiştiği an — öncesi için beklenen doz
  /// üretilmez.
  final DateTime? scheduleFrom;
  /// Sunucunun reddettiği değişiklik nedeni (ör. 'invalid'); null = sorun yok.
  final String? syncError;

  const MedicationPlan({
    required this.id,
    required this.name,
    required this.dose,
    required this.times,
    required this.active,
    required this.createdAt,
    this.localOnly = false,
    this.uuid,
    this.kind = MedKind.scheduled,
    this.freq = MedFreq.daily,
    this.intervalHours,
    this.everyNDays,
    this.weekdays = const [],
    this.startDate,
    this.endDate,
    this.prnMinIntervalMin,
    this.prnMaxPerDay,
    this.pauses = const [],
    this.scheduleFrom,
    this.syncError,
  });

  bool get isPrn => kind == MedKind.prn;

  /// K8: kür bitti mi (bitiş günü geçti). Saklanmaz, türetilir.
  bool isCompletedAt(DateTime now) {
    final e = endDate;
    if (e == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    return today.isAfter(DateTime(e.year, e.month, e.day));
  }

  /// "N gün" kür süresinden bitiş günü (başlangıç dahil).
  static DateTime endDateForDays(DateTime start, int days) =>
      DateTime(start.year, start.month, start.day + days - 1);

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
        localOnly: localOnly,
        uuid: uuid,
        kind: kind,
        freq: freq,
        intervalHours: intervalHours,
        everyNDays: everyNDays,
        weekdays: weekdays,
        startDate: startDate,
        endDate: endDate,
        prnMinIntervalMin: prnMinIntervalMin,
        prnMaxPerDay: prnMaxPerDay,
        pauses: pauses,
        scheduleFrom: scheduleFrom,
        syncError: syncError,
      );
}

/// 'YYYY-MM-DD' ↔ yerel gün.
String? medDateToWire(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

DateTime? medDateFromWire(String? s) {
  if (s == null || s.length != 10) return null;
  final p = s.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}
