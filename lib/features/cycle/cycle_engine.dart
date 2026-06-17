import '../../models/cycle.dart';

/// Ana ekran modu — doğum sonrası bağlamına göre pano içeriği değişir.
enum CycleMode {
  lochia, // ilk ~6 hafta lohusalık kanaması — tahmin YOK
  waiting, // adet henüz dönmedi — tahmin YOK, bilgilendirme
  active, // ilk adet kaydedildi — döngü takibi + tahmin
}

/// Döngü fazı (yalnız active modda anlamlı).
enum CyclePhase { menstrual, follicular, ovulation, luteal }

/// Doğum sonrası kırmızı bayrak belirti anahtarları (entry.symptoms içinde).
/// Bunlardan biri girilince M1 uyarı modali tetiklenir (tanı değil, yönlendirme).
const redFlagSymptoms = {'rf_flood', 'rf_clot', 'rf_odor_fever', 'rf_pain'};

/// Geçmiş bir döngü (istatistik/geçmiş listesi).
class CycleSpan {
  final DateTime start;
  final DateTime? end; // sonraki döngü başlangıcının bir öncesi; son döngüde null
  final int? length; // gün (sonraki başlangıca kadar); son döngüde null
  final int periodDays; // bu döngüdeki adet günü sayısı
  final FlowLevel? dominantFlow;
  const CycleSpan({
    required this.start,
    this.end,
    this.length,
    required this.periodDays,
    this.dominantFlow,
  });
}

/// Türetilmiş döngü durumu — pano/takvim/istatistik tek kaynaktan beslenir.
class CycleStatus {
  final CycleMode mode;

  // Lohusalık (lochia modu)
  final int lochiaDay; // doğumdan bu yana gün
  final DateTime? lochiaStart;

  // Aktif döngü
  final int cycleNumber; // kaçıncı döngü (1-based)
  final int dayInCycle; // döngünün kaçıncı günü (1-based)
  final CyclePhase phase;
  final int avgCycleLength;
  final int avgPeriodDays;
  final DateTime? nextPeriod;
  final int? daysToNextPeriod;
  final DateTime? ovulationDay;
  final DateTime? fertileStart;
  final DateTime? fertileEnd;
  final bool lowConfidence; // <3 döngü → "tahmini/değişebilir"
  final List<CycleSpan> spans; // yeni→eski değil; eski→yeni

  const CycleStatus({
    required this.mode,
    this.lochiaDay = 0,
    this.lochiaStart,
    this.cycleNumber = 0,
    this.dayInCycle = 0,
    this.phase = CyclePhase.follicular,
    this.avgCycleLength = 28,
    this.avgPeriodDays = 5,
    this.nextPeriod,
    this.daysToNextPeriod,
    this.ovulationDay,
    this.fertileStart,
    this.fertileEnd,
    this.lowConfidence = true,
    this.spans = const [],
  });
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
int _diffDays(DateTime a, DateTime b) => _d(a).difference(_d(b)).inDays;

/// Adet kayıtlarından döngü başlangıçlarını çıkarır: bir gün, adet günüyse ve
/// bir önceki gün adet değilse "başlangıç"tır.
List<DateTime> periodStarts(List<CycleEntry> entries) {
  final periodDays = entries.where((e) => e.isPeriod).map((e) => _d(e.date)).toSet();
  final starts = <DateTime>[];
  for (final day in periodDays) {
    if (!periodDays.contains(day.subtract(const Duration(days: 1)))) {
      starts.add(day);
    }
  }
  starts.sort();
  return starts;
}

/// Türetme motoru — ayarlar + kayıtlar → durum. Saf fonksiyon (test edilebilir).
CycleStatus computeStatus(
  CycleSettings settings,
  List<CycleEntry> entries, {
  DateTime? today,
}) {
  final now = _d(today ?? DateTime.now());

  // 1) Mod tayini.
  if (!settings.periodReturned) {
    final birth = settings.birthDate;
    final sinceBirth = birth == null ? null : _diffDays(now, birth);
    final hasLochia = entries.any((e) => e.lochiaColor != null);
    final inLochiaWindow = sinceBirth != null && sinceBirth >= 0 && sinceBirth <= 42;
    if (inLochiaWindow || (hasLochia && (sinceBirth == null || sinceBirth <= 60))) {
      return CycleStatus(
        mode: CycleMode.lochia,
        lochiaDay: sinceBirth ?? 0,
        lochiaStart: birth,
      );
    }
    return const CycleStatus(mode: CycleMode.waiting);
  }

  // 2) Aktif döngü — başlangıçları topla (ilk adet tarihi dahil).
  final starts = <DateTime>{
    _d(settings.firstPeriodDate!),
    ...periodStarts(entries),
  }.toList()
    ..sort();

  // Geçmiş döngü span'leri.
  final spans = <CycleSpan>[];
  for (var i = 0; i < starts.length; i++) {
    final start = starts[i];
    final next = i + 1 < starts.length ? starts[i + 1] : null;
    final end = next?.subtract(const Duration(days: 1));
    final pDays = entries.where((e) {
      final d = _d(e.date);
      return e.isPeriod &&
          !d.isBefore(start) &&
          (next == null || d.isBefore(next));
    }).toList();
    FlowLevel? dom;
    if (pDays.isNotEmpty) {
      dom = pDays
          .map((e) => e.flow!)
          .reduce((a, b) => a.index >= b.index ? a : b);
    }
    spans.add(CycleSpan(
      start: start,
      end: end,
      length: next == null ? null : _diffDays(next, start),
      periodDays: pDays.length,
      dominantFlow: dom,
    ));
  }

  // Ortalamalar.
  final lengths = spans.where((s) => s.length != null).map((s) => s.length!).toList();
  final avgLen = lengths.isEmpty
      ? 28
      : (lengths.reduce((a, b) => a + b) / lengths.length).round();
  final pdays = spans.where((s) => s.periodDays > 0).map((s) => s.periodDays).toList();
  final avgPeriod =
      pdays.isEmpty ? 5 : (pdays.reduce((a, b) => a + b) / pdays.length).round();

  final lastStart = starts.last;
  final dayInCycle = _diffDays(now, lastStart) + 1;
  final nextPeriod = lastStart.add(Duration(days: avgLen));
  final daysToNext = _diffDays(nextPeriod, now);
  // Ovülasyon ≈ sonraki adetten ~14 gün önce; doğurganlık penceresi -5 gün.
  final ovulation = nextPeriod.subtract(const Duration(days: 14));
  final fertileStart = ovulation.subtract(const Duration(days: 5));

  // Faz.
  CyclePhase phase;
  if (dayInCycle <= avgPeriod) {
    phase = CyclePhase.menstrual;
  } else if (now.isAtSameMomentAs(ovulation)) {
    phase = CyclePhase.ovulation;
  } else if (now.isBefore(ovulation)) {
    phase = CyclePhase.follicular;
  } else {
    phase = CyclePhase.luteal;
  }

  return CycleStatus(
    mode: CycleMode.active,
    cycleNumber: starts.length,
    dayInCycle: dayInCycle < 1 ? 1 : dayInCycle,
    phase: phase,
    avgCycleLength: avgLen,
    avgPeriodDays: avgPeriod,
    nextPeriod: nextPeriod,
    daysToNextPeriod: daysToNext,
    ovulationDay: ovulation,
    fertileStart: fertileStart,
    fertileEnd: ovulation,
    lowConfidence: lengths.length < 3,
    spans: spans,
  );
}
