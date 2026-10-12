import '../models/medication_plan.dart';
import '../models/record.dart';
import 'medication/med_names.dart';

/// İlaç v2 doz motoru (ILAC-TASARIM §2) — SAF, test edilebilir.
///
/// 1. [generateDoses]: plan + tarih aralığı → planlanan dozlar (sıklık türü,
///    başlangıç/bitiş, duraklatma, oluşturma anı, zamanlama çapası).
/// 2. [resolveDoses]: dozlar + `RecordType.medication` kayıtları → her dozun
///    durumu. Eşleme önce KİMLİKLE (`plan_uuid + dose_date + dose_time`);
///    kimliksiz eski kayıtlar ve planda artık olmayan saatteki kimlikli kayıtlar
///    ("yetim") ad + saat YAKINLIĞIYLA bağlanır (yarım boşluk, ≤12 sa).
/// 3. Aynı doza birden çok "verildi" → [MedicationDose.multiple] (çift doz
///    bilgisi KAYBOLMAZ); verildi + atlandı → verildi kazanır + [conflict].

/// Doz durumu. [overdue] = saati geçti, 12 saatten az (kartta "açık");
/// [missed] = 12 saati geçti, işaretlenmedi (geçmiş ekranı).
enum MedicationDoseStatus { given, skipped, overdue, upcoming, missed }

/// Dozun dokunma rolü (S9): [undo] işaretlenmiş (doz sayfası: saat düzelt /
/// geri al); [next] işaretlenebilir (saati geldi ya da en çok 2 saat kaldı);
/// [early] daha ileri — işaretlemek onay ister. [lock] artık üretilmez (eski
/// sıralı kilit kaldırıldı); geriye dönük uyumluluk için duruyor.
enum MedicationDoseRole { next, undo, early, lock }

/// "Açık" penceresi (S5/S6): bu süreden eski çözülmemiş doz "kaçırıldı".
const kMedOpenWindow = Duration(hours: 12);

/// Erken işaretleme penceresi (S9).
const kMedEarlyWindow = Duration(hours: 2);

/// Planlanan TEK doz (kimliği: plan uuid + yerel gün + yerel saat).
class PlannedDose {
  final MedicationPlan plan;
  final DateTime doseDate; // yerel gün 00:00
  final String doseTime; // "HH:MM" (yerel duvar saati etiketi)
  final DateTime dueAt; // yerel an
  const PlannedDose(this.plan, this.doseDate, this.doseTime, this.dueAt);

  String get key => medDoseKey(plan, doseDate, doseTime);
}

String medPlanKey(MedicationPlan p) => p.uuid ?? 'local-${p.id}';

String medDoseKey(MedicationPlan p, DateTime date, String time) =>
    '${medPlanKey(p)}|${medDateToWire(date)}|$time';

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Takvim günleri arası fark (DST'den bağımsız).
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

/// "HH:MM" → gün içi dakika (bozuk girdide 09:00 varsayılır).
int medicationMinutes(String t) {
  final parts = t.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return h * 60 + m;
}

/// Duraklatma anı [t]'yi kapsıyor mu? Süren duraklatma geçmişi olmayan
/// (v16 öncesi duraklatılmış) plan her anı kapsar.
/// V3: plan AKTİFSE kapanmamış (`to == null`) aralık kapanmış sayılır (bitişi
/// bilinmediği için yok sayılır) — aksi hâlde aktif görünen plan sessizce hiç
/// doz üretmezdi (ör. eski sürümdeki üye `pauses` göndermeden devam ettirdi).
bool _pausedAt(MedicationPlan p, DateTime t) {
  for (final x in p.pauses) {
    if (x.to == null && p.active) continue;
    if (x.covers(t.toUtc())) return true;
  }
  if (!p.active && !p.pauses.any((x) => x.to == null)) return true;
  return false;
}

/// Duraklatmayı yok sayarak (ama diğer kurallarla) planlanan dozlar.
/// [unfiltered] → başlangıç/bitiş/oluşturma/zamanlama çapası filtreleri de
/// uygulanmaz (yalnız aralık): kimliksiz kaydın yakınlık komşuları için HAM
/// takvim (V1 — üretilmeyen doz da kaydı "emer").
List<PlannedDose> _rawDoses(MedicationPlan p, DateTime from, DateTime to,
    {bool unfiltered = false}) {
  if (p.isPrn || p.times.isEmpty) return const [];
  final start = _day(p.startDate ?? p.createdAt);
  final end = p.endDate == null ? null : _day(p.endDate!);
  final sf = p.scheduleFrom;
  final firstDay = sf == null ? null : _day(sf.toLocal());
  final out = <PlannedDose>[];

  bool keep(DateTime due, DateTime date) {
    if (due.isBefore(from) || !due.isBefore(to)) return false;
    if (unfiltered) return true;
    if (date.isBefore(start)) return false;
    if (end != null && date.isAfter(end)) return false;
    if (due.isBefore(p.createdAt)) return false;
    if (firstDay != null && date.isBefore(firstDay)) return false;
    return true;
  }

  if (p.freq == MedFreq.interval) {
    final step = Duration(hours: (p.intervalHours ?? 0).clamp(1, 48));
    final m0 = medicationMinutes(p.times.first);
    final anchor = DateTime(start.year, start.month, start.day, m0 ~/ 60, m0 % 60);
    var k = from.isAfter(anchor) ? from.difference(anchor).inMinutes ~/ step.inMinutes : 0;
    if (k > 0) k--;
    for (var due = anchor.add(step * k); due.isBefore(to); due = due.add(step)) {
      final date = _day(due);
      if (keep(due, date)) out.add(PlannedDose(p, date, _hm(due), due));
    }
    return out;
  }

  final times = [...p.times]..sort((a, b) => medicationMinutes(a).compareTo(medicationMinutes(b)));
  for (var d = _day(from); d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
    final on = switch (p.freq) {
      MedFreq.everyNDays => (unfiltered || _daysBetween(start, d) >= 0) &&
          _daysBetween(start, d) % (p.everyNDays ?? 1).clamp(1, 365) == 0,
      MedFreq.weekly => p.weekdays.contains(d.weekday),
      _ => true,
    };
    if (!on) continue;
    for (final t in times) {
      final mins = medicationMinutes(t);
      final due = DateTime(d.year, d.month, d.day, mins ~/ 60, mins % 60);
      if (keep(due, d)) out.add(PlannedDose(p, d, t, due));
    }
  }
  return out;
}

/// [from, to) aralığında planlanan dozlar (saat sırasıyla). Duraklatılan
/// anlar üretilmez.
List<PlannedDose> generateDoses(MedicationPlan p,
        {required DateTime from, required DateTime to}) =>
    [for (final d in _rawDoses(p, from, to)) if (!_pausedAt(p, d.dueAt)) d];

/// Tek dozun çözülmüş durumu (kart/geçmiş/özet ortak modeli).
class MedicationDose {
  final MedicationPlan plan;
  final String time; // "HH:MM"
  final MedicationDoseStatus status;
  final MedicationDoseRole role;
  /// Birincil kayıt: ilk "verildi" (yoksa ilk "atlandı").
  final Record? record;
  final DateTime doseDate;
  final DateTime dueAt;
  final List<Record> givenRecords;
  final List<Record> skippedRecords;
  /// En az bir bağlı kayıt kimliksiz (eski) ve yakınlıkla eşlendi.
  final bool legacy;
  /// Kart: dünün hâlâ açık dozu (S6).
  final bool fromYesterday;

  MedicationDose({
    required this.plan,
    required this.time,
    required this.status,
    this.role = MedicationDoseRole.next,
    this.record,
    DateTime? doseDate,
    DateTime? dueAt,
    this.givenRecords = const [],
    this.skippedRecords = const [],
    this.legacy = false,
    this.fromYesterday = false,
  })  : doseDate = doseDate ?? _day(DateTime.now()),
        dueAt = dueAt ??
            (() {
              final m = medicationMinutes(time);
              final d = doseDate ?? _day(DateTime.now());
              return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
            })();

  bool get isGiven => status == MedicationDoseStatus.given;
  bool get isSkipped => status == MedicationDoseStatus.skipped;
  bool get isOverdue => status == MedicationDoseStatus.overdue;
  bool get isMissed => status == MedicationDoseStatus.missed;

  /// Verildi ya da atlandı — bir kaydı var, artık beklemiyor.
  bool get isResolved => isGiven || isSkipped;
  DateTime? get givenAt => record?.ts;

  /// Aynı doza birden çok "verildi" (çift doz — her zaman görünür).
  bool get multiple => givenRecords.length > 1;

  /// Verildi + atlandı aynı doz (verildi kazanır, not gösterilir).
  bool get conflict => givenRecords.isNotEmpty && skippedRecords.isNotEmpty;

  List<Record> get records => [...givenRecords, ...skippedRecords];
  String get key => medDoseKey(plan, doseDate, time);
}

bool _isSkipped(Record r) => r.data['skipped'] == true;

/// Kaydın kimliği (plan uuid, gün, saat); kimliksizse null.
({String plan, String date, String? time})? _identity(Record r) {
  final p = r.data['plan_uuid'];
  final d = r.data['dose_date'];
  if (p is! String || p.isEmpty || d is! String) return null;
  final t = r.data['dose_time'];
  // V16: kanonik (küçük harf) — sunucu da kanonik saklar.
  return (plan: p.toLowerCase(), date: d, time: t is String ? t : null);
}

/// [plans]'ın [from, to) dozlarını [records] ile çözümler. [records] her türü
/// içerebilir (yalnız silinmemiş ilaç kayıtları kullanılır).
List<MedicationDose> resolveDoses(
  List<MedicationPlan> plans,
  List<Record> records, {
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  // Yakınlık komşuları için aralık iki yana bir gün genişletilir.
  final pFrom = DateTime(from.year, from.month, from.day - 1);
  final pTo = DateTime(to.year, to.month, to.day + 1);
  final scheduled = [for (final p in plans) if (!p.isPrn) p];
  final doses = <PlannedDose>[for (final p in scheduled) ...generateDoses(p, from: pFrom, to: pTo)];
  final byKey = {for (final d in doses) d.key: d};
  final attached = <String, List<({Record r, bool legacy})>>{};
  final byUuid = {for (final p in scheduled) if (p.uuid != null) p.uuid!.toLowerCase(): p};
  final byName = <String, MedicationPlan>{};
  for (final p in scheduled) {
    byName.putIfAbsent(medNameKey(p.name), () => p);
  }

  final orphans =
      <({Record r, MedicationPlan p, DateTime at, DateTime? date, bool legacy})>[];
  for (final r in records) {
    if (r.type != RecordType.medication || r.isDeleted) continue;
    final id = _identity(r);
    if (id != null) {
      final p = byUuid[id.plan];
      if (p == null || id.time == null) continue; // başka plan / PRN
      final date = medDateFromWire(id.date);
      if (date == null) continue;
      final k = medDoseKey(p, date, id.time!);
      if (byKey.containsKey(k)) {
        attached.putIfAbsent(k, () => []).add((r: r, legacy: false));
      } else {
        final m = medicationMinutes(id.time!);
        orphans.add((
          r: r,
          p: p,
          at: DateTime(date.year, date.month, date.day, m ~/ 60, m % 60),
          date: date,
          legacy: false
        ));
      }
    } else if (r.data['plan_uuid'] == null) {
      final p = byName[medNameKey((r.data['name'] as String?) ?? '')];
      if (p != null) orphans.add((r: r, p: p, at: r.ts.toLocal(), date: null, legacy: true));
    }
  }

  // Yetim/eski kayıtlar: aynı plandaki en yakın doza, yarım boşluk içindeyse.
  // V1 (ILAC-INCELEME-2) — gün sınırı:
  // - kimlikli yetim (saati planda artık yok) YALNIZ kendi dose_date'inin
  //   dozlarına bağlanır;
  // - kimliksiz kayıtta komşular HAM takvimden (başlangıç/oluşturma/çapa/
  //   duraklatma filtresiz) hesaplanır: en yakın ham doz üretilmemişse kayıt
  //   "emilir" (hiçbir doza bağlanmaz). Sonraki günün dozuna İLERİ bağlanmaz;
  //   gece yarısı sonrası dünün dozuna GERİ bağlanabilir (M4).
  final perPlan = <String, List<PlannedDose>>{};
  for (final d in doses) {
    perPlan.putIfAbsent(medPlanKey(d.plan), () => []).add(d);
  }
  for (final list in perPlan.values) {
    list.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }
  final rawPerPlan = <String, List<PlannedDose>>{};
  List<PlannedDose> rawFor(MedicationPlan p) => rawPerPlan.putIfAbsent(medPlanKey(p),
      () => _rawDoses(p, pFrom, pTo, unfiltered: true)..sort((a, b) => a.dueAt.compareTo(b.dueAt)));
  for (final o in orphans) {
    final list = o.legacy ? rawFor(o.p) : (perPlan[medPlanKey(o.p)] ?? const <PlannedDose>[]);
    final atDay = _day(o.at);
    PlannedDose? best;
    Duration? bestGap;
    for (var i = 0; i < list.length; i++) {
      final d = list[i];
      if (o.legacy ? d.doseDate.isAfter(atDay) : d.doseDate != o.date) continue;
      var half = kMedOpenWindow;
      if (i > 0) {
        final g = d.dueAt.difference(list[i - 1].dueAt) ~/ 2;
        if (g < half) half = g;
      }
      if (i < list.length - 1) {
        final g = list[i + 1].dueAt.difference(d.dueAt) ~/ 2;
        if (g < half) half = g;
      }
      final gap = o.at.difference(d.dueAt).abs();
      if (gap > half) continue;
      if (bestGap == null || gap < bestGap) {
        best = d;
        bestGap = gap;
      }
    }
    // Ham takvimdeki en yakın doz üretilmemişse (çapa/oluşturma öncesi,
    // duraklatma, kür dışı) kayıt emilir.
    if (best != null && byKey.containsKey(best.key)) {
      attached.putIfAbsent(best.key, () => []).add((r: o.r, legacy: o.legacy));
    }
  }

  final out = <MedicationDose>[];
  for (final d in doses) {
    if (d.dueAt.isBefore(from) || !d.dueAt.isBefore(to)) continue;
    final recs = [...?attached[d.key]]..sort((a, b) => a.r.ts.compareTo(b.r.ts));
    final given = [for (final x in recs) if (!_isSkipped(x.r)) x.r];
    final skipped = [for (final x in recs) if (_isSkipped(x.r)) x.r];
    final MedicationDoseStatus status;
    if (given.isNotEmpty) {
      status = MedicationDoseStatus.given;
    } else if (skipped.isNotEmpty) {
      status = MedicationDoseStatus.skipped;
    } else if (d.dueAt.isAfter(now)) {
      status = MedicationDoseStatus.upcoming;
    } else if (now.difference(d.dueAt) < kMedOpenWindow) {
      status = MedicationDoseStatus.overdue;
    } else {
      status = MedicationDoseStatus.missed;
    }
    final resolved = given.isNotEmpty || skipped.isNotEmpty;
    final role = resolved
        ? MedicationDoseRole.undo
        : (d.dueAt.isAfter(now.add(kMedEarlyWindow))
            ? MedicationDoseRole.early
            : MedicationDoseRole.next);
    out.add(MedicationDose(
      plan: d.plan,
      time: d.doseTime,
      status: status,
      role: role,
      record: given.isNotEmpty ? given.first : (skipped.isNotEmpty ? skipped.first : null),
      doseDate: d.doseDate,
      dueAt: d.dueAt,
      givenRecords: given,
      skippedRecords: skipped,
      legacy: recs.any((x) => x.legacy),
    ));
  }
  out.sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return out;
}

/// PRN ("ihtiyaç halinde") planının anlık durumu (K7). Uygulama doz ya da
/// aralık ÖNERMEZ; uyarılar yalnız kullanıcının girdiği değerlerden.
class PrnStatus {
  final MedicationPlan plan;
  final Record? last; // son "verildi"
  final int countToday; // bugünkü "verildi" sayısı
  final DateTime now;
  const PrnStatus(this.plan, this.last, this.countToday, this.now);

  Duration? get sinceLast => last == null ? null : now.difference(last!.ts);
  Duration? get minInterval => plan.prnMinIntervalMin == null
      ? null
      : Duration(minutes: plan.prnMinIntervalMin!);

  /// Kullanıcının girdiği en kısa aralık dolmadı.
  bool get tooSoon =>
      minInterval != null && sinceLast != null && sinceLast! < minInterval!;
  Duration? get remaining => tooSoon ? minInterval! - sinceLast! : null;

  /// Kullanıcının girdiği günlük üst sınıra ulaşıldı (S8).
  bool get atDailyMax => plan.prnMaxPerDay != null && countToday >= plan.prnMaxPerDay!;
}

PrnStatus prnStatus(MedicationPlan p, List<Record> records, {required DateTime now}) {
  final today = _day(now);
  Record? last;
  var count = 0;
  for (final r in records) {
    if (r.type != RecordType.medication || r.isDeleted || _isSkipped(r)) continue;
    final id = r.data['plan_uuid'];
    final mine = id is String
        ? id == p.uuid
        : medNameKey((r.data['name'] as String?) ?? '') == medNameKey(p.name);
    if (!mine || r.ts.isAfter(now)) continue;
    if (last == null || r.ts.isAfter(last.ts)) last = r;
    if (_day(r.ts) == today) count++;
  }
  return PrnStatus(p, last, count, now);
}

/// Bir planın bugünkü satırı (kartta tek satır): dozları + özet durumu.
class MedicationPlanDay {
  final MedicationPlan plan;
  final List<MedicationDose> doses; // saat sırasıyla (dünün açık dozu önce)
  const MedicationPlanDay({required this.plan, required this.doses});

  int get givenCount => doses.where((d) => d.isGiven).length;
  int get resolvedCount => doses.where((d) => d.isResolved).length;

  /// Bekleyen doz kalmadı (hepsi verildi ya da atlandı).
  bool get complete => resolvedCount == doses.length;

  /// Saati geçmiş, verilmemiş ilk doz (yoksa null).
  MedicationDose? get firstOverdue {
    for (final d in doses) {
      if (d.isOverdue) return d;
    }
    return null;
  }

  /// Sıradaki (dokunulabilir) ilk çözülmemiş doz; yoksa null.
  MedicationDose? get next {
    for (final d in doses) {
      if (!d.isResolved) return d;
    }
    return null;
  }

  /// Son işaretlenen doz (tamamlanmış satırın "Verildi/Atlandı · saat" metni).
  MedicationDose? get lastResolved {
    MedicationDose? out;
    for (final d in doses) {
      if (d.isResolved) out = d;
    }
    return out;
  }

  /// Çift işaretlenmiş doz var mı (kart uyarısı).
  bool get hasMultiple => doses.any((d) => d.multiple);

  // Sıralama: önce saati geçenler, sonra bekleyenler, en sonda tamamlananlar.
  int get _rank => firstOverdue != null ? 0 : (complete ? 2 : 1);
  int get _sortMinutes => complete ? 1 << 30 : next!.dueAt.millisecondsSinceEpoch ~/ 60000;
}

/// Bugünün ilaç/vitamin özeti — ana sayfa bölümü, + menüsü rozeti, yönetim
/// ekranı ve Hatırlatıcılar satırı aynı hesaptan beslenir.
class MedicationDay {
  final List<MedicationPlanDay> rows; // sıralı (bkz. [MedicationPlanDay._rank])
  final List<PrnStatus> prn; // ihtiyaç halinde planlar (saatsiz)
  final int planCount; // pasif/biten dahil tüm planlar (keşif kartı kararı için)
  final DateTime now;
  const MedicationDay(
      {required this.rows, this.prn = const [], required this.planCount, required this.now});

  Iterable<MedicationDose> get _all => rows.expand((r) => r.doses);

  int get total => _all.length;
  int get done => _all.where((d) => d.isGiven).length; // yalnız VERİLENLER
  int get overdue => _all.where((d) => d.isOverdue).length;
  bool get hasActive => rows.isNotEmpty || prn.isNotEmpty;

  /// Bekleyen doz kalmadı — atlananlar da "tamam" sayılır (ama [done]'a girmez).
  bool get allDone => total > 0 && _all.every((d) => d.isResolved);

  /// Bütün dozlar zaman sırasıyla — karttaki "gün çubuğu" segmentleri.
  List<MedicationDose> get timeline => _all.toList()..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  /// Bugünün ilk doz saati ("yarın ilk doz 08:00" metni için).
  String? get firstTime {
    for (final d in timeline) {
      if (!d.fromYesterday) return d.time;
    }
    return null;
  }

  /// Henüz zamanı gelmemiş en yakın doz saati.
  String? get nextUpcoming {
    for (final d in timeline) {
      if (d.status == MedicationDoseStatus.upcoming) return d.time;
    }
    return null;
  }

  /// Bölüm ana sayfada yukarı (Hızlı Giriş'in altına) çıksın mı: saati geçmiş
  /// doz varsa ya da sıradaki doza 60 dk'dan az kaldıysa.
  bool get promote {
    if (overdue > 0) return true;
    for (final d in timeline) {
      if (d.status == MedicationDoseStatus.upcoming) {
        return d.dueAt.difference(now) <= const Duration(minutes: 60);
      }
    }
    return false;
  }
}

/// [plans] (pasifler dahil) + kayıtlardan bugünün özetini üretir. Saf.
/// Kart = bugünün dozları ∪ dünün hâlâ AÇIK (12 sa içinde, çözülmemiş) dozları.
/// [allRecords] en az dünü ve bugünü kapsamalı.
MedicationDay medicationDay(
  List<MedicationPlan> plans,
  List<Record> allRecords, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final today = _day(ref);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final resolved = resolveDoses(plans, allRecords, from: yesterday, to: tomorrow, now: ref);
  final card = <MedicationDose>[];
  for (final d in resolved) {
    if (!d.doseDate.isBefore(today)) {
      card.add(d);
    } else if (d.isOverdue) {
      card.add(MedicationDose(
        plan: d.plan,
        time: d.time,
        status: d.status,
        role: d.role,
        record: d.record,
        doseDate: d.doseDate,
        dueAt: d.dueAt,
        givenRecords: d.givenRecords,
        skippedRecords: d.skippedRecords,
        legacy: d.legacy,
        fromYesterday: true,
      ));
    }
  }
  final rows = <MedicationPlanDay>[
    for (final p in plans.where((p) => !p.isPrn))
      MedicationPlanDay(plan: p, doses: [for (final d in card) if (d.plan.id == p.id) d]),
  ]
    ..removeWhere((r) => r.doses.isEmpty)
    ..sort((a, b) {
      final r = a._rank.compareTo(b._rank);
      return r != 0 ? r : a._sortMinutes.compareTo(b._sortMinutes);
    });
  final prn = [
    for (final p in plans)
      if (p.isPrn && p.active && !p.isCompletedAt(ref)) prnStatus(p, allRecords, now: ref),
  ];
  return MedicationDay(rows: rows, prn: prn, planCount: plans.length, now: ref);
}

/// Geçmiş ekranının (K11) bir günü.
class MedHistoryDay {
  final DateTime day;
  final List<MedicationDose> doses; // beklenen dozlar (çözülmüş)
  /// Beklenen doza bağlanamayan kayıtlar (zamanlama çapası öncesi, plan dışı) ve
  /// PRN verilişleri.
  final List<Record> extra;
  /// Gün duraklatma kapsamında (en az bir doz duraklatma yüzünden üretilmedi).
  final bool paused;
  const MedHistoryDay(this.day, this.doses, this.extra, this.paused);
}

class MedHistory {
  final List<MedHistoryDay> days; // en yeni gün önce
  const MedHistory(this.days);
  Iterable<MedicationDose> get _all => days.expand((d) => d.doses);
  int get given => _all.where((d) => d.isGiven).length;
  int get skipped => _all.where((d) => d.isSkipped).length;
  int get missed => _all.where((d) => d.isMissed).length;
  int get multiple => _all.where((d) => d.multiple).length;
  int get prnGiven =>
      days.expand((d) => d.extra).where((r) => !_isSkipped(r)).length;
}

/// [plan]'ın [from]..[to] (iki uç DAHİL, yerel gün) geçmişi (K11).
MedHistory medicationHistory(
  MedicationPlan plan,
  List<Record> records, {
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  final start = _day(from);
  final end = DateTime(to.year, to.month, to.day + 1);
  final resolved = resolveDoses([plan], records, from: start, to: end, now: now);
  final claimed = {for (final d in resolved) ...d.records.map((r) => r.id)};
  final raw = _rawDoses(plan, start, end);
  final days = <MedHistoryDay>[];
  for (var d = DateTime(to.year, to.month, to.day); !d.isBefore(start);
      d = DateTime(d.year, d.month, d.day - 1)) {
    final next = DateTime(d.year, d.month, d.day + 1);
    final ds = [for (final x in resolved) if (x.doseDate == d) x];
    final paused = raw.any((x) => x.doseDate == d && _pausedAt(plan, x.dueAt));
    final extra = [
      for (final r in records)
        if (r.type == RecordType.medication &&
            !r.isDeleted &&
            !claimed.contains(r.id) &&
            _belongs(plan, r) &&
            _recordDay(r) == d)
          r
    ]..sort((a, b) => a.ts.compareTo(b.ts));
    days.add(MedHistoryDay(d, ds, extra, paused));
    if (next.isBefore(start)) break;
  }
  return MedHistory(days);
}

bool _belongs(MedicationPlan p, Record r) {
  final id = r.data['plan_uuid'];
  if (id is String) return id == p.uuid;
  return medNameKey((r.data['name'] as String?) ?? '') == medNameKey(p.name);
}

DateTime _recordDay(Record r) =>
    medDateFromWire(r.data['dose_date'] as String?) ?? _day(r.ts);

/// Bugünün (yerel gün) planlı dozları, plan sırasıyla — [resolveDoses] üzerine
/// ince sarmalayıcı (dünün açık dozları DAHİL DEĞİL; kart için [medicationDay]).
List<MedicationDose> todaysMedicationDoses(
  List<MedicationPlan> plans,
  List<Record> allRecords, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final today = _day(ref);
  final all = resolveDoses(plans, allRecords,
      from: today, to: DateTime(today.year, today.month, today.day + 1), now: ref);
  return [
    for (final p in plans)
      if (!p.isPrn) ...all.where((d) => d.plan.id == p.id)
  ];
}
