import '../models/medication_plan.dart';
import '../models/record.dart';
import 'medication.dart';

/// "Dün nasıl geçti?" sabah özeti — SAF hesap (design/AdenaBaby Mobile/Dün
/// Nasıl Geçti.html karar notları). Sayıları değil dünün ŞEKLİNİ çıkarır: tek
/// cümlelik başlık türü, 24 saatlik şerit verisi ve en fazla 3 öne çıkan an.
/// Metin üretmez (çeviri UI'da) — yalnız tür + ham değer döner; test edilebilir.
///
/// İlkeler: kaydı olmayan kategori hiç görünmez (hiçbir yerde "0" yok — kayıt
/// girilmemesi o şeyin yapılmadığı anlamına gelmez); karşılaştırma için en az
/// 3 günlük geçmiş gerekir; eksik ilaç dozu "verilmedi" değil "kayıtlı değil".

/// Gece penceresi (ayar yok → sabit kural): 19:00–07:00.
const recapNightStartMin = 19 * 60;
const recapNightEndMin = 7 * 60;

/// Karşılaştırma eşiği: son 7 gün ortalamasından en az %15 sapma.
const _diffThreshold = 0.15;

/// Karşılaştırma için gereken en az veri-günü.
const _minHistoryDays = 3;

enum RecapHeadlineKind {
  firstFood, // bir ilk: daha önce kaydı olmayan ek gıda
  longestSleep, // en uzun uyku ortalamanın belirgin üstünde
  daySleepLonger, // gündüz uykusu ortalamanın belirgin üstünde
  closeWatch, // ateş/belirti kaydı var — ebeveynin emeği
  family, // ≥2 kişi kayıt ekledi
  sleepTotal, // varsayılanlar: en çok kaydı olan kategori
  feedCount,
  diaperCount,
  generic,
}

class RecapHeadline {
  final RecapHeadlineKind kind;
  final String? text; // firstFood → yiyecek adı
  final int? minutes; // uyku süreleri
  final int? count; // beslenme/bez adedi
  const RecapHeadline(this.kind, {this.text, this.minutes, this.count});
}

/// Şeritteki uyku bloğu — dünün 00:00'ından dakika, güne kırpılmış.
class RecapSleepBlock {
  final int start;
  final int end;
  final bool night;
  const RecapSleepBlock(this.start, this.end, {required this.night});
}

enum RecapDiaperKind { pee, poo, both }

class RecapRibbon {
  final List<int> feeds;
  final List<RecapSleepBlock> sleeps;
  final List<({int min, RecapDiaperKind kind})> diapers;

  /// En uzun uykunun [sleeps] içindeki sırası (yoksa null) + TAM süresi
  /// (gece yarısını aşan uyku şeritte kırpılır, süre kaydın tamamıdır).
  final int? longest;
  final int longestMin;

  /// Dün BAŞLAYAN uykuların toplam süresi (lejant).
  final int sleepTotalMin;
  const RecapRibbon({
    required this.feeds,
    required this.sleeps,
    required this.diapers,
    required this.longest,
    required this.longestMin,
    required this.sleepTotalMin,
  });

  bool get isEmpty => feeds.isEmpty && sleeps.isEmpty && diapers.isEmpty;
}

enum RecapHighlightKind {
  firstFood,
  medication,
  longestSleep,
  daySleep,
  bedtime,
  fever,
  growth,
  bath,
  breast,
  bottle,
  feedMixed,
  diaper,
}

/// Öne çıkan an. Alanlar türe göre dolar (bkz. [buildYesterdayRecap]).
class RecapHighlight {
  final RecapHighlightKind kind;
  final int score;

  /// "İlk" rozeti + vurgulu zemin.
  final bool first;

  /// Yeşil ✓ (ilaç: bütün dozlar kayıtlı).
  final bool ok;

  /// Son 7 gün ortalamasına göre fark (dk, işaretli) — nötr rozet. Yoksa null.
  final int? deltaMin;

  final String? text; // yiyecek adı / plan adı / dışkı notu
  final String? text2; // tepki notu
  final Object? amount; // ek gıda miktarı (num → kaşık, yoksa serbest metin)
  final int? minutes; // süre
  final int? minutes2; // karşılaştırma süresi / ortalama aralık / en uzun ara
  final int? count;
  final int? count2;
  final DateTime? at; // olayın saati (başlangıç)
  final DateTime? at2; // bitiş / son ölçüm saati
  final int? clock; // gün içi dakika (yatış saati)
  final int? clock2; // ortalama yatış saati
  final num? value; // ateş tepe / kilo / toplam ml
  final num? value2; // son ateş / boy
  final String? unit; // ateş birimi
  final bool flag; // longestSleep: son 7 günün en uzunu

  /// İlaç: kaydı olmayan dozlar ("ekle" bağlantısı bunları yazar).
  final List<MedicationDose> missing;

  const RecapHighlight(
    this.kind, {
    required this.score,
    this.first = false,
    this.ok = false,
    this.deltaMin,
    this.text,
    this.text2,
    this.amount,
    this.minutes,
    this.minutes2,
    this.count,
    this.count2,
    this.at,
    this.at2,
    this.clock,
    this.clock2,
    this.value,
    this.value2,
    this.unit,
    this.flag = false,
    this.missing = const [],
  });

  /// Tekrar-önleme kimliği (aynı aday 3 gün üst üste aynı sırada gelmesin).
  String get id => kind.name;
}

class YesterdayRecap {
  final DateTime day; // dünün 00:00'ı
  final RecapHeadline headline;
  final RecapRibbon ribbon;
  final List<RecapHighlight> highlights; // en fazla 3

  /// Kayıt ekleyenler: createdBy (null = bu cihaz/ben) → adet, çoktan aza.
  /// Tek kişiyse boş (aile satırı çıkmaz).
  final List<({String? userId, int count})> contributors;

  /// Bugünkü ilk randevu (varsa).
  final Record? nextAppointment;

  /// Geçmiş 3 günden azsa: "birkaç gün sonra ritmi göstereceğiz" notu.
  final bool littleData;

  const YesterdayRecap({
    required this.day,
    required this.headline,
    required this.ribbon,
    required this.highlights,
    required this.contributors,
    required this.nextAppointment,
    required this.littleData,
  });
}

// ───────── yardımcılar ─────────

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime _sleepStart(Record r) =>
    DateTime.tryParse(r.data['start_ts'] as String? ?? '')?.toLocal() ?? r.ts;

int? _sleepDur(Record r) {
  final d = r.data['duration'];
  return d is num && d > 0 ? d.toInt() : null;
}

bool _isNightMinute(int m) => m >= recapNightStartMin || m < recapNightEndMin;

/// Bir günün (BAŞLANGICINA göre atanan) uyku istatistikleri.
class _SleepDay {
  int total = 0;
  int dayTotal = 0; // gündüz başlayan (şekerlemeler)
  int naps = 0;
  int longest = 0;
  DateTime? longestStart;
  int? bedtime; // akşam (≥19:00) başlayan ilk gece uykusu — gün içi dakika
  bool get hasData => total > 0;
}

_SleepDay _sleepStats(List<Record> all, DateTime day) {
  final s = _SleepDay();
  for (final r in all) {
    if (r.type != RecordType.sleep) continue;
    final dur = _sleepDur(r);
    if (dur == null) continue;
    final st = _sleepStart(r);
    if (_d(st) != day) continue;
    final m = st.hour * 60 + st.minute;
    s.total += dur;
    if (dur > s.longest) {
      s.longest = dur;
      s.longestStart = st;
    }
    if (_isNightMinute(m)) {
      if (m >= recapNightStartMin && (s.bedtime == null || m < s.bedtime!)) s.bedtime = m;
    } else {
      s.dayTotal += dur;
      s.naps++;
    }
  }
  return s;
}

double? _avg(Iterable<int> xs) {
  final l = xs.toList();
  if (l.length < _minHistoryDays) return null;
  return l.reduce((a, b) => a + b) / l.length;
}

/// Sapma oranı (y - ort) / ort; ortalama yoksa null.
double? _dev(int y, double? avg) => avg == null || avg <= 0 ? null : (y - avg) / avg;

// ───────── ana hesap ─────────

/// [day] = dünün 00:00'ı. [history] = en az [day]-7 gününden bugüne kadarki
/// kayıtlar (silinmemiş). [knownFoods] = [day]'den ÖNCE kaydı olan ek gıda
/// adları (küçük harf, kırpılmış). [recentIds] = önceki günlerin öne çıkan
/// kimlikleri (en yeni önce) — tekrar önleme. [selfIds] = bu kullanıcının
/// kimlikleri (hesap + yerel); henüz senkronlanmamış kayıtların createdBy'si
/// null olduğundan hepsi tek "ben" sayılır. Dün hiç kayıt yoksa null.
YesterdayRecap? buildYesterdayRecap({
  required DateTime day,
  required List<Record> history,
  Set<String> knownFoods = const {},
  List<MedicationPlan> plans = const [],
  List<List<String>> recentIds = const [],
  Set<String> selfIds = const {},
}) {
  final end = day.add(const Duration(days: 1));
  bool inDay(Record r) => !r.ts.isBefore(day) && r.ts.isBefore(end);
  final yRecs = history.where(inDay).toList()..sort((a, b) => a.ts.compareTo(b.ts));
  if (yRecs.isEmpty) return null;
  int minOf(DateTime t) => t.difference(day).inMinutes;

  // ── uyku ──
  final ys = _sleepStats(history, day);
  final past = [
    for (var i = 1; i <= 7; i++) _sleepStats(history, day.subtract(Duration(days: i))),
  ].where((s) => s.hasData).toList();
  final avgLongest = _avg(past.map((s) => s.longest));
  final avgDay = _avg(past.where((s) => s.naps > 0).map((s) => s.dayTotal));
  final avgBed = _avg(past.where((s) => s.bedtime != null).map((s) => s.bedtime!));
  final devLongest = ys.hasData ? _dev(ys.longest, avgLongest) : null;
  final devDay = ys.naps > 0 ? _dev(ys.dayTotal, avgDay) : null;

  // Şerit: dünle KESİŞEN her uyku (önceki geceden sarkan dahil), güne kırpılır.
  final blocks = <RecapSleepBlock>[];
  int? longestIdx;
  for (final r in history.where((r) => r.type == RecordType.sleep)) {
    final dur = _sleepDur(r);
    if (dur == null) continue;
    final st = _sleepStart(r);
    final a = minOf(st), b = a + dur;
    if (b <= 0 || a >= 1440) continue;
    final sm = st.hour * 60 + st.minute;
    blocks.add(RecapSleepBlock(a.clamp(0, 1440), b.clamp(0, 1440), night: _isNightMinute(sm)));
    if (ys.longestStart != null && st == ys.longestStart && dur == ys.longest) {
      longestIdx = blocks.length - 1;
    }
  }
  // Çizim sırası saat sırası olsun; en uzunun sırasını koru.
  final longestBlock = longestIdx != null ? blocks[longestIdx] : null;
  blocks.sort((a, b) => a.start.compareTo(b.start));
  longestIdx = longestBlock != null ? blocks.indexOf(longestBlock) : null;

  // ── beslenme ──
  final feeds = yRecs
      .where((r) =>
          r.type == RecordType.feed &&
          // süren emzirme sayacı (bitmemiş) özet dışı
          !(r.data['sub'] == 'breast' &&
              r.data.containsKey('start_ts') &&
              r.data['end_ts'] == null))
      .toList();
  final milk = feeds.where((r) => r.data['sub'] != 'solid').toList();
  final solids = feeds.where((r) => r.data['sub'] == 'solid').toList();
  int? avgGap, maxGap;
  if (milk.length >= 2) {
    avgGap = milk.last.ts.difference(milk.first.ts).inMinutes ~/ (milk.length - 1);
    maxGap = 0;
    for (var i = 1; i < milk.length; i++) {
      final g = milk[i].ts.difference(milk[i - 1].ts).inMinutes;
      if (g > maxGap!) maxGap = g;
    }
  }

  // ── bez ──
  final diapers = yRecs.where((r) => r.type == RecordType.diaper).toList();
  RecapDiaperKind dk(Record r) => switch (r.data['sub']) {
        'poo' => RecapDiaperKind.poo,
        'poopee' => RecapDiaperKind.both,
        _ => RecapDiaperKind.pee,
      };

  final ribbon = RecapRibbon(
    feeds: [for (final r in feeds) minOf(r.ts)],
    sleeps: blocks,
    diapers: [for (final r in diapers) (min: minOf(r.ts), kind: dk(r))],
    longest: longestIdx,
    longestMin: ys.longest,
    sleepTotalMin: ys.total,
  );

  // ── adaylar (puan: ilk > plan > 7 güne göre fark > nadir kayıt > ritim) ──
  final cands = <RecapHighlight>[];

  // İlk ek gıda — adı önceki kayıtlarda hiç geçmemişse.
  Record? firstFood;
  for (final r in solids) {
    final name = (r.data['food_name'] as String? ?? '').trim();
    if (name.isEmpty || knownFoods.contains(name.toLowerCase())) continue;
    firstFood = r;
    break;
  }
  if (firstFood != null) {
    cands.add(RecapHighlight(
      RecapHighlightKind.firstFood,
      score: 100,
      first: true,
      text: (firstFood.data['food_name'] as String).trim(),
      text2: (firstFood.data['reaction'] as String?)?.trim(),
      amount: firstFood.data['amount'],
      at: firstFood.ts,
    ));
  }

  // İlaç/vitamin planı — dün var olan planların dozları. Plan dün gün içinde
  // oluşturulduysa, oluşturulmadan önceki saatler "kayıtlı değil" sayılmaz.
  final dayPlans = plans.where((p) => p.active && p.createdAt.isBefore(end)).toList();
  if (dayPlans.isNotEmpty) {
    final md = medicationDay(dayPlans, yRecs, now: end.subtract(const Duration(seconds: 1)));
    final doses = md.timeline.where((d) {
      if (!d.plan.createdAt.isAfter(day)) return true;
      return d.isResolved || medicationMinutes(d.time) >= minOf(d.plan.createdAt);
    }).toList();
    if (doses.isNotEmpty) {
      final given = doses.where((d) => d.isGiven).length;
      final skipped = doses.where((d) => d.isSkipped).length;
      // "Ekle" yalnız sıradaki doza yazabilir (sıralı eşleme) → plan başına ilk eksik.
      final missing = doses.where((d) => d.role == MedicationDoseRole.next).toList();
      final unresolved = doses.where((d) => !d.isResolved).length;
      cands.add(RecapHighlight(
        RecapHighlightKind.medication,
        score: unresolved > 0 ? 85 : 80,
        ok: unresolved == 0 && skipped == 0,
        text: dayPlans.length == 1 ? dayPlans.single.name : null,
        count: given,
        count2: doses.length,
        minutes: skipped, // atlanan doz adedi
        missing: missing,
      ));
    }
  }

  // Uyku: en uzun, gündüz, yatış saati.
  if (ys.hasData) {
    final best = past.isNotEmpty && past.every((s) => ys.longest > s.longest);
    final notable = devLongest != null && devLongest.abs() >= _diffThreshold;
    cands.add(RecapHighlight(
      RecapHighlightKind.longestSleep,
      score: notable ? 60 + (devLongest * 20).round().clamp(0, 15) : 21,
      minutes: ys.longest,
      at: ys.longestStart,
      at2: ys.longestStart!.add(Duration(minutes: ys.longest)),
      deltaMin: notable ? (ys.longest - avgLongest!).round() : null,
      flag: best && past.length >= _minHistoryDays,
    ));
    if (ys.naps > 0) {
      final n = devDay != null && devDay.abs() >= _diffThreshold;
      cands.add(RecapHighlight(
        RecapHighlightKind.daySleep,
        score: n ? 58 : 19,
        minutes: ys.dayTotal,
        minutes2: avgDay?.round(),
        count: ys.naps,
        deltaMin: n ? (ys.dayTotal - avgDay!).round() : null,
      ));
    }
    if (ys.bedtime != null && avgBed != null) {
      final delta = (ys.bedtime! - avgBed).round();
      if (delta.abs() >= 20) {
        cands.add(RecapHighlight(
          RecapHighlightKind.bedtime,
          score: 56,
          clock: ys.bedtime,
          clock2: avgBed.round(),
          deltaMin: delta,
        ));
      }
    }
  }

  // Nadir kayıtlar.
  final temps = yRecs
      .where((r) => r.type == RecordType.temperature && r.data['value'] is num)
      .toList();
  if (temps.isNotEmpty) {
    final peak = temps.reduce(
        (a, b) => (a.data['value'] as num) >= (b.data['value'] as num) ? a : b);
    cands.add(RecapHighlight(
      RecapHighlightKind.fever,
      score: 45,
      value: peak.data['value'] as num,
      value2: temps.last.data['value'] as num,
      unit: peak.data['unit'] as String? ?? 'C',
      count: temps.length,
      at2: temps.last.ts,
    ));
  }
  final growth = yRecs.where((r) => r.type == RecordType.growth).toList();
  if (growth.isNotEmpty) {
    final g = growth.last;
    cands.add(RecapHighlight(
      RecapHighlightKind.growth,
      score: 42,
      value: g.data['weight'] as num?,
      value2: g.data['height'] as num?,
      at: g.ts,
    ));
  }
  final bath = yRecs.where((r) => r.type == RecordType.bath).toList();
  if (bath.isNotEmpty) {
    cands.add(RecapHighlight(RecapHighlightKind.bath, score: 30, at: bath.last.ts));
  }

  // Ritim: beslenme, bez.
  if (milk.isNotEmpty) {
    final allBreast = milk.every((r) => r.data['sub'] == 'breast');
    num sum(String k) =>
        milk.fold<num>(0, (a, r) => a + (r.data[k] is num ? r.data[k] as num : 0));
    final ml = sum('ml');
    if (allBreast) {
      cands.add(RecapHighlight(
        RecapHighlightKind.breast,
        score: 22,
        count: sum('left_min').round(),
        count2: sum('right_min').round(),
        minutes: milk.length,
        minutes2: avgGap,
      ));
    } else if (ml > 0 && milk.every((r) => r.data['sub'] != 'breast')) {
      cands.add(RecapHighlight(
        RecapHighlightKind.bottle,
        score: 22,
        count: milk.length,
        value: ml,
        minutes2: maxGap,
      ));
    } else {
      cands.add(RecapHighlight(
        RecapHighlightKind.feedMixed,
        score: 22,
        count: milk.length,
        minutes2: avgGap,
      ));
    }
  }
  if (diapers.isNotEmpty) {
    final poos = diapers.where((r) => dk(r) != RecapDiaperKind.pee).toList();
    final pees = diapers.where((r) => dk(r) != RecapDiaperKind.poo).length;
    final stool = poos.isEmpty ? null : poos.last.data['stool'];
    cands.add(RecapHighlight(
      RecapHighlightKind.diaper,
      score: 20,
      count: poos.length,
      count2: pees,
      at2: poos.isEmpty ? null : poos.last.ts,
      text: stool is String && stool.isNotEmpty ? stool : null,
    ));
  }

  // En yüksek 3; aynı aday son 2 günde de aynı sıradaysa bir alttakiyle yer
  // değiştirir (diyalog her gün biraz farklı görünsün). "İlk" hiç kaydırılmaz.
  cands.sort((a, b) => b.score.compareTo(a.score));
  if (recentIds.length >= 2) {
    for (var i = 0; i < cands.length - 1 && i < 3; i++) {
      final id = cands[i].id;
      final stale = recentIds.take(2).every((d) => d.length > i && d[i] == id);
      if (stale && !cands[i].first) {
        final t = cands[i];
        cands[i] = cands[i + 1];
        cands[i + 1] = t;
        i++; // yeni yerleşeni tekrar kaydırma
      }
    }
  }
  final highlights = cands.take(3).toList();

  // ── kayıt ekleyenler ──
  final by = <String?, int>{};
  for (final r in yRecs) {
    final who = r.createdBy == null || selfIds.contains(r.createdBy) ? null : r.createdBy;
    by[who] = (by[who] ?? 0) + 1;
  }
  final contributors = by.length < 2
      ? const <({String? userId, int count})>[]
      : ([for (final e in by.entries) (userId: e.key, count: e.value)]
        ..sort((a, b) => b.count.compareTo(a.count)));

  // ── başlık (öncelik sırasıyla) ──
  final closeWatch =
      temps.isNotEmpty || yRecs.any((r) => r.type == RecordType.symptom);
  RecapHeadline headline;
  if (firstFood != null) {
    headline = RecapHeadline(RecapHeadlineKind.firstFood,
        text: (firstFood.data['food_name'] as String).trim());
  } else if (devLongest != null && devLongest >= _diffThreshold) {
    headline = RecapHeadline(RecapHeadlineKind.longestSleep, minutes: ys.longest);
  } else if (devDay != null && devDay >= _diffThreshold) {
    headline = const RecapHeadline(RecapHeadlineKind.daySleepLonger);
  } else if (closeWatch) {
    headline = const RecapHeadline(RecapHeadlineKind.closeWatch);
  } else if (contributors.length >= 2) {
    headline = const RecapHeadline(RecapHeadlineKind.family);
  } else {
    final sleepN = blocks.length, feedN = feeds.length, diaperN = diapers.length;
    if (ys.hasData && sleepN >= feedN && sleepN >= diaperN) {
      headline = RecapHeadline(RecapHeadlineKind.sleepTotal, minutes: ys.total);
    } else if (feedN > 0 && feedN >= diaperN) {
      headline = RecapHeadline(RecapHeadlineKind.feedCount, count: feedN);
    } else if (diaperN > 0) {
      headline = RecapHeadline(RecapHeadlineKind.diaperCount, count: diaperN);
    } else if (ys.hasData) {
      headline = RecapHeadline(RecapHeadlineKind.sleepTotal, minutes: ys.total);
    } else {
      headline = const RecapHeadline(RecapHeadlineKind.generic);
    }
  }

  // Geçmiş: dünden önceki 7 günde kaydı olan gün sayısı.
  final historyDays = history
      .where((r) => r.ts.isBefore(day) && !r.ts.isBefore(day.subtract(const Duration(days: 7))))
      .map((r) => _d(r.ts))
      .toSet()
      .length;

  // Bugünkü ilk randevu.
  final todayEnd = end.add(const Duration(days: 1));
  final appts = history
      .where((r) =>
          r.type == RecordType.appointment && !r.ts.isBefore(end) && r.ts.isBefore(todayEnd))
      .toList()
    ..sort((a, b) => a.ts.compareTo(b.ts));

  return YesterdayRecap(
    day: day,
    headline: headline,
    ribbon: ribbon,
    highlights: highlights,
    contributors: contributors,
    nextAppointment: appts.isEmpty ? null : appts.first,
    littleData: historyDays < _minHistoryDays,
  );
}
