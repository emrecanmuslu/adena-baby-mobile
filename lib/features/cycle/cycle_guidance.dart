import '../../models/cycle.dart';

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
