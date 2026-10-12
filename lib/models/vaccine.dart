import 'package:flutter/foundation.dart';

/// Aşı takvimi kaydı — local-first. Katalog (ad + doğumdan ay) içerikten gelir,
/// `dueDate` doğum tarihinden yerelde hesaplanır, durum (done) yerelde tutulur.
/// `key` = durum eşleştirme anahtarı (= aşı adı). API §content/health-catalog.
@immutable
class Vaccine {
  final String key;
  final String name;
  final DateTime dueDate;
  final bool done;
  final DateTime? doneDate;

  /// Takvimdeki ay (doğumdan itibaren) — ekranda yaş gruplaması için.
  final int months;

  /// İsteğe bağlı / ücretli aşı (ulusal takvimde yok). True ise "Gecikti"/"Yaklaşan"
  /// gösterilmez; nötr "İsteğe bağlı" olarak sunulur (gereksiz endişe yaratmaz).
  final bool optional;

  const Vaccine({
    required this.key,
    required this.name,
    required this.dueDate,
    required this.done,
    this.doneDate,
    this.months = 0,
    this.optional = false,
  });

  /// Yapılmadı ve tarihi geçmiş mi? İsteğe bağlı aşılar asla "gecikmiş" sayılmaz.
  bool get isOverdue {
    if (done || optional) return false;
    final now = DateTime.now();
    return dueDate.isBefore(DateTime(now.year, now.month, now.day));
  }
}

/// Aşı adının okunur parçaları: [primary] büyük yazılan ad, [secondary] küçük
/// alt satır (kısaltma ya da açıklama), [dose] ayrı rozet ("2. doz", "Rapel").
@immutable
class VaccineNameParts {
  final String primary;
  final String secondary;
  final String dose;
  const VaccineNameParts(this.primary, this.secondary, this.dose);
}

// Doz parçası — katalogdaki 7 dilin doz/rapel kelimeleri.
final _doseRe = RegExp(
    r'doz|rapel|dose|dosis|rappel|refuerzo|booster|剂|加强|खुराक|बूस्टर|جرعة|معزز',
    caseSensitive: false);
final _paidRe = RegExp(r'\s*\(ücretli\)\s*$');
final _parenRe = RegExp(r'^(.*?)\s*[(（](.*)[)）]$');
final _splitRe = RegExp(r'\s*[,，、،]\s*');

/// Katalog adını ayrıştırır: "KPA (Pnömokok, 1. doz)" → Pnömokok · KPA · 1. doz.
/// Baştaki kelime kısaltmaysa (Latin, boşluksuz, ≥2 büyük harf ya da ≤4 harf)
/// açıklama büyük ad olur, kısaltma alt satıra iner; değilse baştaki ad büyük
/// kalır, açıklama alt satıra iner. Ayrıştırılamayan ad olduğu gibi döner.
VaccineNameParts parseVaccineName(String name) {
  final s = name.replaceFirst(_paidRe, '').trim();
  final m = _parenRe.firstMatch(s);
  if (m == null) return VaccineNameParts(s, '', '');
  final head = m.group(1)!.trim();
  if (head.isEmpty) return VaccineNameParts(s, '', '');
  final dose = <String>[];
  final rest = <String>[];
  for (final p in m.group(2)!.split(_splitRe)) {
    if (p.isEmpty) continue;
    (_doseRe.hasMatch(p) ? dose : rest).add(p);
  }
  final restText = rest.join(', ');
  final doseText = dose.join(', ');
  final isAbbr = RegExp(r'^[A-Za-zÇĞİÖŞÜçğıöşü\-]+$').hasMatch(head) &&
      (RegExp(r'[A-ZÇĞİÖŞÜ]').allMatches(head).length >= 2 || head.length <= 4);
  if (isAbbr && restText.isNotEmpty) {
    return VaccineNameParts(restText, head, doseText);
  }
  return VaccineNameParts(head, restText, doseText);
}

/// Satır durumu (ekran): yapıldı · tarihi geçti · sıradaki · gelecek · isteğe bağlı.
enum VaccineStatus { done, late, next, future, optional }

/// Grup (yaş) durumu: tamamlandı · bekleyen var · sıradaki · gelecek.
enum VaccineGroupStatus { done, late, next, future }

/// Aynı aya düşen aşılar — zorunlular ve isteğe bağlılar ayrı.
@immutable
class VaccineGroup {
  final int months;
  final DateTime dueDate;
  final List<Vaccine> mandatory;
  final List<Vaccine> optional;
  final VaccineGroupStatus status;
  final int lateCount;
  const VaccineGroup({
    required this.months,
    required this.dueDate,
    required this.mandatory,
    required this.optional,
    required this.status,
    required this.lateCount,
  });
}

/// Takvimin ekran görünümü — saf hesap (test edilebilir, [today] verilir).
@immutable
class VaccineSchedule {
  final List<VaccineGroup> groups;
  final Map<String, VaccineStatus> statusByKey;

  /// Sıradaki zorunlu aşının grubu (tarihi bugün/ileride, yapılmamış). Yoksa null.
  final VaccineGroup? nextGroup;
  final List<Vaccine> late;
  final int total;
  final int done;
  final int mandatoryTotal;
  final int mandatoryDone;

  const VaccineSchedule({
    required this.groups,
    required this.statusByKey,
    required this.nextGroup,
    required this.late,
    required this.total,
    required this.done,
    required this.mandatoryTotal,
    required this.mandatoryDone,
  });

  VaccineStatus statusOf(Vaccine v) => statusByKey[v.key] ?? VaccineStatus.future;

  factory VaccineSchedule.build(List<Vaccine> vaccines, DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    bool past(Vaccine v) =>
        DateTime(v.dueDate.year, v.dueDate.month, v.dueDate.day).isBefore(t);
    final sorted = [...vaccines]
      ..sort((a, b) {
        final c = a.months.compareTo(b.months);
        return c != 0 ? c : a.dueDate.compareTo(b.dueDate);
      });
    final next = sorted.where((v) => !v.optional && !v.done && !past(v)).firstOrNull;
    final nextMonths = next?.months;
    final status = <String, VaccineStatus>{};
    for (final v in sorted) {
      status[v.key] = v.done
          ? VaccineStatus.done
          : v.optional
              ? VaccineStatus.optional
              : past(v)
                  ? VaccineStatus.late
                  : v.months == nextMonths
                      ? VaccineStatus.next
                      : VaccineStatus.future;
    }
    final byMonth = <int, List<Vaccine>>{};
    for (final v in sorted) {
      (byMonth[v.months] ??= []).add(v);
    }
    final groups = <VaccineGroup>[];
    for (final e in byMonth.entries) {
      final mand = e.value.where((v) => !v.optional).toList();
      final opt = e.value.where((v) => v.optional).toList();
      final late = mand.where((v) => status[v.key] == VaccineStatus.late).length;
      final allMandDone = mand.every((v) => v.done) &&
          (mand.isNotEmpty || opt.every((v) => v.done));
      final st = late > 0
          ? VaccineGroupStatus.late
          : allMandDone
              ? VaccineGroupStatus.done
              : e.key == nextMonths
                  ? VaccineGroupStatus.next
                  : VaccineGroupStatus.future;
      groups.add(VaccineGroup(
        months: e.key,
        dueDate: e.value.first.dueDate,
        mandatory: mand,
        optional: opt,
        status: st,
        lateCount: late,
      ));
    }
    return VaccineSchedule(
      groups: groups,
      statusByKey: status,
      nextGroup:
          nextMonths == null ? null : groups.firstWhere((g) => g.months == nextMonths),
      late: sorted.where((v) => status[v.key] == VaccineStatus.late).toList(),
      total: sorted.length,
      done: sorted.where((v) => v.done).length,
      mandatoryTotal: sorted.where((v) => !v.optional).length,
      mandatoryDone: sorted.where((v) => !v.optional && v.done).length,
    );
  }
}
