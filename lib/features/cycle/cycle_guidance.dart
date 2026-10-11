import '../../models/cycle.dart';
import 'cycle_engine.dart';

/// Adet modülü sağlık yönlendirmeleri — SAF karar fonksiyonları (ADET-INCELEME
/// düzeltme turu). Ekranlar hangi uyarının görüneceğini buradan sorar; metinler
/// `cycle_widgets.dart` `CycleTexts`'te. Hepsi birim testli.

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// DST-güvenli gün farkı (a − b).
int cycleDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(a.year, a.month, a.day)
        .difference(DateTime.utc(b.year, b.month, b.day))
        .inDays;

/// Doğumdan bu yana gün (doğum yoksa null).
int? daysSinceBirth(CycleSettings s, {DateTime? today}) {
  final b = s.birthDate;
  if (b == null) return null;
  return cycleDaysBetween(today ?? DateTime.now(), b);
}

/// Doğumdan bu yana tamamlanan takvim ayı.
int? monthsSinceBirth(CycleSettings s, {DateTime? today}) {
  final b = s.birthDate;
  if (b == null) return null;
  final t = _d(today ?? DateTime.now());
  var m = (t.year - b.year) * 12 + (t.month - b.month);
  if (t.day < b.day) m -= 1;
  return m < 0 ? 0 : m;
}

/// LAM (emzirme) kartının durumu (A2/A5/C8).
enum LamState {
  /// Gösterilmez: doğum yok, emzirme bilinmiyor (null) ya da emzirmiyor.
  hidden,

  /// Tam emziren, ilk 6 ay, adet dönmemiş → üç koşul listelenir (öneri değil).
  conditions,

  /// Koşullardan biri bozuldu (6 ay geçti / karışık / adet döndü) →
  /// "Emzirme artık tek başına korunma sağlamaz".
  notProtective,
}

/// C1 (karar S8): "Uzun süredir adet görmedin — hekimine danış" kartı.
///  • Aktif takip: son adetten ≥90 gün (düzensiz döngüde ≥180 gün — temkinli
///    ek eşik; düzenli için karar S8).
///  • Kayıp sonrası adet dönmedi: kayıptan ≥8 hafta (56 gün).
///  • Emzirmeyen lohusa, adet dönmedi: doğumdan ≥12 hafta (84 gün).
///  • Emziren lohusada GÖSTERİLMEZ (emzirmede uzun amenore sık); gebelikte yok.
bool longAmenorrheaWarning(CycleSettings s, CycleStatus st, {DateTime? today}) {
  final t = today ?? DateTime.now();
  if (s.lifecycleMode == CycleLifecycleMode.pregnant) return false;
  final bf = s.breastfeeding;
  final birth = s.birthDate;
  final breastfeedingMom = birth != null &&
      (bf == Breastfeeding.exclusive || bf == Breastfeeding.mixed);
  if (st.mode == CycleMode.active) {
    if (breastfeedingMom) return false;
    final since = st.dayInCycle - 1;
    return since >= (st.irregular ? 180 : 90);
  }
  final loss = s.lastLossDate;
  final lossIsLatest = loss != null && (birth == null || !birth.isAfter(loss));
  if (lossIsLatest) return cycleDaysBetween(t, loss) >= 56;
  if (birth != null && bf == Breastfeeding.none) {
    return cycleDaysBetween(t, birth) >= 84;
  }
  return false;
}

/// C2 (karar S10): adet 8 günden uzun → hekim önerisi. Aktif takipte:
///  • ortalama adet süresi > 8 gün, ya da
///  • son döngünün başlangıcından itibaren kesintisiz adet ≥ 9 gün, ya da
///  • son adette ardışık ≥ 7 gün "yoğun" akış.
bool longPeriodWarning(List<CycleEntry> entries, CycleStatus st) {
  if (st.mode != CycleMode.active || st.spans.isEmpty) return false;
  if (st.avgPeriodDays > 8) return true;
  final byDay = <DateTime, CycleEntry>{for (final e in entries) _d(e.date): e};
  var day = _d(st.spans.last.start);
  var run = 0, heavy = 0, maxHeavy = 0;
  while (true) {
    final e = byDay[day];
    if (e == null || !e.isPeriod) break;
    run++;
    heavy = e.flow == FlowLevel.heavy ? heavy + 1 : 0;
    if (heavy > maxHeavy) maxHeavy = heavy;
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return run >= 9 || maxHeavy >= 7;
}

LamState lamState(CycleSettings s, {DateTime? today}) {
  final bf = s.breastfeeding;
  if (s.birthDate == null || bf == null || bf == Breastfeeding.none) {
    return LamState.hidden;
  }
  final months = monthsSinceBirth(s, today: today) ?? 0;
  if (bf == Breastfeeding.mixed || months >= 6 || s.periodReturned) {
    return LamState.notProtective;
  }
  return LamState.conditions;
}
