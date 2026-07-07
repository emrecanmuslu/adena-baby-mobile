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
  final DateTime? fertileStart; // MEVCUT döngünün penceresi (takvim işaretlemesi)
  final DateTime? fertileEnd;
  // YAKLAŞAN pencere: mevcut döngününki geçmişse sonraki döngününki (pano/hatırlatıcı).
  final DateTime? upcomingFertileStart;
  final DateTime? upcomingFertileEnd;
  final bool fertileWindowIsNextCycle; // yaklaşan pencere sonraki döngüye mi ait
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
    this.upcomingFertileStart,
    this.upcomingFertileEnd,
    this.fertileWindowIsNextCycle = false,
    this.lowConfidence = true,
    this.spans = const [],
  });
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
int _diffDays(DateTime a, DateTime b) => _d(a).difference(_d(b)).inDays;

/// DST-güvenli gün ekleme. `.add(Duration(days: n))` bir DST (yaz saati) geçişini
/// aşarsa yerel gece-yarısı 23:00'e (önceki gün) ya da 01:00'e kayabilir → işaretli
/// tarih 1 gün kayar. DateTime yapıcısı gün taşmasını normalize eder ve her zaman
/// yerel gece-yarısı üretir (Türkiye kalıcı UTC+3 olduğundan etkilenmez, ABD DST'de
/// etkilenirdi). Tüm tahmin tarihleri bununla üretilir; takvim/bugün UI'ları da
/// gün aritmetiğinde bunu kullanmalı (Duration değil).
DateTime cycleAddDays(DateTime x, int days) =>
    DateTime(x.year, x.month, x.day + days);
DateTime _addDays(DateTime x, int days) => cycleAddDays(x, days);

/// Gebe kalma olasılığı seviyesi (Wilcox eğrisi, kademeli).
enum ConceptionChance { low, medium, high, veryHigh }

/// Bir günün gebe-kalma olasılığı — Bugün ve Takvim AYNI fonksiyonu kullanır
/// (kopya mantık çelişki üretmesin). Kademelendirme (My Calendar + Wilcox):
/// yumurtlama=çok yüksek; ov−2/−1=yüksek; pencere kenarları (ov−5..−3) ve
/// ovülasyon SONRASI gün (ov+1, olasılık hızla düşer)=orta; pencere dışı=düşük.
ConceptionChance conceptionChance(DateTime day, CycleStatus status) {
  if (status.mode != CycleMode.active) return ConceptionChance.low;
  final d = _d(day);
  final ovu = status.ovulationDay;
  if (ovu != null && _d(ovu).isAtSameMomentAs(d)) return ConceptionChance.veryHigh;
  if (status.fertileStart != null &&
      status.fertileEnd != null &&
      !d.isBefore(_d(status.fertileStart!)) &&
      !d.isAfter(_d(status.fertileEnd!))) {
    final toOvu = ovu == null ? null : _diffDays(ovu, d);
    return (toOvu != null && toOvu >= 1 && toOvu <= 2)
        ? ConceptionChance.high
        : ConceptionChance.medium;
  }
  return ConceptionChance.low;
}

/// Adet kayıtlarından döngü başlangıçlarını çıkarır: bir gün, adet günüyse ve
/// bir önceki gün adet değilse "başlangıç"tır.
List<DateTime> periodStarts(List<CycleEntry> entries) {
  final periodDays = entries.where((e) => e.isPeriod).map((e) => _d(e.date)).toSet();
  final starts = <DateTime>[];
  for (final day in periodDays) {
    if (!periodDays.contains(_addDays(day, -1))) {
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

  // 1) Mod tayini. `predictionsHidden` (düşük/doğum sonrası şefkatli gizleme)
  // açıkken çapa dolu olsa bile tahmin üretilmez — bayrak yalnız yazılan değil,
  // burada TÜKETİLEN bir koruma katmanı (aksi halde işlevsiz kalırdı).
  if (!settings.periodReturned || settings.predictionsHidden) {
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
  // Çapadan (firstPeriodDate) ÖNCEKİ adet kayıtları yok sayılır: doğum/kayıp
  // sonrası "ilk adet = yeni Gün 1" sıfırlamasında eski dönemin kayıtları
  // ortalama ve döngü numarasını kirletmesin (çapa öncesi dev span oluşurdu).
  final anchor = _d(settings.firstPeriodDate!);
  final starts = <DateTime>{
    anchor,
    ...periodStarts(entries).where((s) => !s.isBefore(anchor)),
  }.toList()
    ..sort();

  // Geçmiş döngü span'leri.
  final spans = <CycleSpan>[];
  for (var i = 0; i < starts.length; i++) {
    final start = starts[i];
    final next = i + 1 < starts.length ? starts[i + 1] : null;
    final end = next == null ? null : _addDays(next, -1);
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

  // Ortalamalar — My Calendar "Smart prediction" pariteli.
  //  • smartPrediction AÇIK → döngü/adet süresi YAKIN loglardan (son [_recentWindow]
  //    döngü) öğrenilir. Eski outlier'lar tahmini bozmasın diye tüm geçmiş değil
  //    yakın pencere ortalaması alınır.
  //  • smartPrediction KAPALI → kullanıcının girdiği sabit expected/period değerleri
  //    kullanılır (ölçüm yok sayılır).
  // Öğrenme penceresi: son kaç döngü ortalanır (kullanıcı ayarı; null → 6).
  // Düzensiz/uzun döngülerde kullanıcı 3'e indirip son eğilimi yakalayabilir.
  final lw = settings.learningWindow;
  final recentWindow = (lw != null && lw >= 2 && lw <= 12) ? lw : 6;
  final smart = settings.smartPrediction;
  List<int> recent(List<int> xs) =>
      xs.length > recentWindow ? xs.sublist(xs.length - recentWindow) : xs;
  int mean(List<int> xs) => (xs.reduce((a, b) => a + b) / xs.length).round();

  final lengths = spans.where((s) => s.length != null).map((s) => s.length!).toList();
  final recentLengths = recent(lengths);
  // Ölçülmüş döngü yoksa (ilk döngü) ya da smart kapalıysa manuel beklenen uzunluk
  // (21–40 dışı → yok say → 28 varsayılan).
  final manualLen = settings.expectedCycleLength;
  final manualValid = manualLen != null && manualLen >= 21 && manualLen <= 40;
  final avgLen = (!smart || recentLengths.isEmpty)
      ? (manualValid ? manualLen : 28)
      : mean(recentLengths);
  // Yalnız TAMAMLANMIŞ döngülerin (length != null) adet günü sayısı. Devam eden son
  // döngü henüz büyüyor (1. günde periodDays=1) → dahil edersek ortalama bozulur ve
  // tahmini adet tek güne düşer. My Calendar de mevcut döngüyü ortalamaya katmaz.
  final pdays = spans
      .where((s) => s.length != null && s.periodDays > 0)
      .map((s) => s.periodDays)
      .toList();
  final recentPdays = recent(pdays);
  // Ölçülmüş adet günü yoksa ya da smart kapalıysa manuel süre (2–10), yoksa 5.
  final manualPeriod = settings.periodLength;
  final manualPeriodValid =
      manualPeriod != null && manualPeriod >= 2 && manualPeriod <= 10;
  final avgPeriod = (!smart || recentPdays.isEmpty)
      ? (manualPeriodValid ? manualPeriod : 5)
      : mean(recentPdays);
  // Luteal faz uzunluğu (gün) — ovülasyon konumunu belirler. Kullanıcı ayarı 10–16
  // arası geçerli, yoksa tıbbi varsayılan 14.
  final lutealRaw = settings.lutealPhaseLength;
  final luteal = (lutealRaw != null && lutealRaw >= 10 && lutealRaw <= 16)
      ? lutealRaw
      : 14;

  final lastStart = starts.last;
  final dayInCycle = _diffDays(now, lastStart) + 1;
  final nextPeriod = _addDays(lastStart, avgLen);
  final daysToNext = _diffDays(nextPeriod, now);
  // Ovülasyon ≈ sonraki adetten luteal faz kadar önce; doğurganlık penceresi
  // ovülasyon −5 … +1 (My Calendar pariteti — pencere ovülasyondan 1 gün sonra biter).
  final ovulation = _addDays(nextPeriod, -luteal);
  final fertileStart = _addDays(ovulation, -5);
  final fertileEnd = _addDays(ovulation, 1);
  // Yaklaşan pencere: mevcut döngününki (fertileStart..ovulation) bugünü geçtiyse
  // sonraki döngünün penceresine kay → pano "geçmiş" pencere göstermez, doğurganlık
  // hatırlatıcısı doğru kurulur. (Mevcut fertileStart/End calendar için korunur.)
  final windowPassed = ovulation.isBefore(now);
  final nextCyclePeriod = _addDays(nextPeriod, avgLen);
  final nextOvulation = _addDays(nextCyclePeriod, -luteal);
  final upcomingOvulation = windowPassed ? nextOvulation : ovulation;
  final upcomingFertileStart = _addDays(upcomingOvulation, -5);

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
    fertileEnd: fertileEnd,
    upcomingFertileStart: upcomingFertileStart,
    upcomingFertileEnd: _addDays(upcomingOvulation, 1),
    fertileWindowIsNextCycle: windowPassed,
    lowConfidence: lengths.length < 3,
    spans: spans,
  );
}
