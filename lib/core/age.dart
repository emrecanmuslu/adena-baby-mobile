import '../models/baby.dart';
import 'i18n.dart';

/// Bebeğin ay cinsinden yaşı (bekleme/born değil/doğum yok → null).
///
/// Saf (test edilebilir): referans an [now] verilebilir; verilmezse
/// `DateTime.now()`. Takvim bazlı: gün, doğum gününden küçükse ay 1 azalır.
int? ageInMonths(Baby? b, {DateTime? now}) {
  if (b == null || b.isExpecting) return null;
  final bd = b.birthDate;
  if (bd == null) return null;
  final ref = now ?? DateTime.now();
  var m = (ref.year - bd.year) * 12 + (ref.month - bd.month);
  if (ref.day < bd.day) m -= 1;
  return m < 0 ? 0 : m;
}

/// Kısa yaş etiketi ("5 gün", "2 ay 5 gün", "3 yaş 4 ay"; bekleme: hafta /
/// "Bekliyor"; doğum yok: "Takip"). Ay/gün takvim-doğru (30.44 yaklaşımı değil).
///
/// Saf (test edilebilir): referans an [now] verilebilir; verilmezse
/// `DateTime.now()`.
String babyAgeShort(Baby b, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  if (b.isExpecting) {
    final due = b.dueDate;
    if (due == null) return tr('Bekliyor');
    // Bekleme ekranıyla BİREBİR aynı hesap: gün farkı gece yarısı bazlı olmalı
    // (DateTime.now() saat dahil olduğundan kalan günü 1 eksik sayıp haftayı
    // sınırda kaydırabilir). daysPregnant = 280 - kalan, hafta = tam bölüm.
    final today = DateTime(ref.year, ref.month, ref.day);
    final daysLeft = due.difference(today).inDays;
    final daysPregnant = (280 - daysLeft).clamp(0, 280);
    final weeks = daysPregnant ~/ 7;
    return trp('{w}. hf', {'w': weeks});
  }
  final birth = b.birthDate;
  if (birth == null) return tr('Takip');
  return _calendarAgeLabel(birth, ref);
}

/// Bir doğum anına ([bd0]) göre [ref] tarihindeki takvim yaşı etiketi
/// ("5 gün" / "2 ay 5 gün" / "3 yaş 4 ay"; gelecekteyse "Takip").
/// Düzeltilmiş yaş için de kullanılır (ayarlı doğum anıyla çağrılır).
String _calendarAgeLabel(DateTime bd0, DateTime ref) {
  final bd = DateTime(bd0.year, bd0.month, bd0.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  if (today.isBefore(bd)) return tr('Takip');

  // Takvim bazlı yaş: yıl/ay/gün farkı (ay gün taşımalı).
  var years = today.year - bd.year;
  var months = today.month - bd.month;
  var days = today.day - bd.day;
  if (days < 0) {
    months -= 1;
    days += DateTime(today.year, today.month, 0).day; // önceki ayın gün sayısı
  }
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  final totalMonths = years * 12 + months;

  // 1 aydan küçük → yalnız gün.
  if (totalMonths < 1) return trp('{n} gün', {'n': days});
  // 2 yaşından küçük → ay + gün.
  if (totalMonths < 24) {
    final ay = trp('{n} ay', {'n': totalMonths});
    return days > 0 ? '$ay ${trp('{n} gün', {'n': days})}' : ay;
  }
  // 2 yaş ve üzeri → yaş + ay.
  final yas = trp('{n} yaş', {'n': years});
  return months > 0 ? '$yas ${trp('{n} ay', {'n': months})}' : yas;
}

// ---- Prematüre / düzeltilmiş yaş (corrected age) ----
//
// Prematüre (gebelik < 37 hafta) bebeklerde büyüme/gelişim, doğum tarihine değil
// "olması gereken doğum tarihine" göre kıyaslanır: düzeltilmiş yaş = takvim yaşı −
// erken doğum süresi. ~24. takvim ayından sonra düzeltme bırakılır. AŞILAR takvim
// yaşında kalır (tıbben erkenliğe göre ertelenmez) — orada bu fonksiyonlar KULLANILMAZ.

/// Düzeltmenin uygulandığı üst sınır (takvim ayı). Bunun üstünde takvim = düzeltilmiş.
const int correctedAgeCutoffMonths = 24;

/// Tahmini doğum tarihinden (due) gerçek doğuma göre doğumdaki gebelik yaşını
/// türetir (bekleme→doğum geçişinde otomatik ön-doldurma için). Zamanında/sonra
/// doğmuşsa (≥40 hafta) null döner (prematüre değil). Saf / test edilebilir.
({int weeks, int days})? gestationalAgeFromDue(DateTime birthDate, DateTime dueDate) {
  final bd = DateTime(birthDate.year, birthDate.month, birthDate.day);
  final dd = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final earlyDays = dd.difference(bd).inDays; // doğum due'dan önce → pozitif
  final gestTotalDays = 280 - earlyDays;
  if (gestTotalDays >= 280) return null; // zamanında / geç doğum
  if (gestTotalDays < 0) return (weeks: 0, days: 0);
  return (weeks: gestTotalDays ~/ 7, days: gestTotalDays % 7);
}

/// Erken doğum gün sayısı: (40hf − gebelik) − ek gün. Prematüre değilse 0.
int prematureEarlyDays(Baby? b) {
  if (b == null || !b.isPremature) return 0;
  final days = (40 - b.gestationalWeeks!) * 7 - b.gestationalDays;
  return days < 0 ? 0 : days;
}

/// Düzeltilmiş yaş (ay). Prematüre değil / 24 ay üstü / doğum yok → takvim yaşı
/// (bekleme → null). Saf: [now] enjekte edilebilir.
int? correctedAgeMonths(Baby? b, {DateTime? now}) {
  final chrono = ageInMonths(b, now: now);
  if (chrono == null || b == null) return chrono;
  if (!b.isPremature || chrono >= correctedAgeCutoffMonths) return chrono;
  final ref = now ?? DateTime.now();
  final adj = b.birthDate!.add(Duration(days: prematureEarlyDays(b)));
  var m = (ref.year - adj.year) * 12 + (ref.month - adj.month);
  if (ref.day < adj.day) m -= 1;
  return m < 0 ? 0 : m;
}

/// Düzeltme şu an etkin mi (prematüre + henüz cutoff'a gelmemiş)? UI'da
/// "düzeltilmiş yaş" etiketini/bilgi rozetini göstermek için.
bool usesCorrectedAge(Baby? b, {DateTime? now}) {
  if (b == null || !b.isPremature) return false;
  final chrono = ageInMonths(b, now: now);
  return chrono != null && chrono < correctedAgeCutoffMonths;
}

/// Düzeltilmiş kısa yaş etiketi (örn. "3 ay 4 gün"). Düzeltme etkin değilse
/// normal [babyAgeShort]'a düşer. Saf: [now] enjekte edilebilir.
String correctedAgeShort(Baby b, {DateTime? now}) {
  if (!usesCorrectedAge(b, now: now)) return babyAgeShort(b, now: now);
  final ref = now ?? DateTime.now();
  final adj = b.birthDate!.add(Duration(days: prematureEarlyDays(b)));
  return _calendarAgeLabel(adj, ref);
}

/// İkili yaş etiketi: prematüre + düzeltme etkinse "{takvim} · düzeltilmiş
/// {düzeltilmiş}", aksi halde sade takvim yaşı. UI'da bebeğin yaşını gösteren
/// her yerde kullanılır. Saf: [now] enjekte edilebilir.
String dualAgeLabel(Baby b, {DateTime? now}) {
  final chrono = babyAgeShort(b, now: now);
  if (!usesCorrectedAge(b, now: now)) return chrono;
  return trp('{chrono} · düzeltilmiş {corrected}',
      {'chrono': chrono, 'corrected': correctedAgeShort(b, now: now)});
}

/// "Düzeltilmiş yaş" bilgi rozetinin gövdesi (AdInfoDot/showAdInfo ile
/// gösterilir). Acemi kullanıcıya prematüre düzeltmesini açıklar.
String correctedAgeInfoBody() => tr(
    'Bebeğin erken (prematüre) doğduğu için yaşını düzeltilmiş olarak da '
    'gösteriyoruz: düzeltilmiş yaş, tahmini doğum tarihine göre hesaplanır '
    '(takvim yaşı − erken doğum süresi). Büyüme, gelişim ve diş takibinde '
    'düzeltilmiş yaş kullanılır; ~2 yaşından sonra düzeltme bırakılır. '
    'Aşılar her zaman takvim yaşına göre planlanır.');

/// Gebelik günü: 280 - kalan gün, 0..280 aralığına kırpılır. Gün farkı gece
/// yarısı bazlı (saat dahil [now] kalan günü sınırda kaydırmasın diye).
///
/// Saf (test edilebilir): referans an [now] verilebilir; verilmezse
/// `DateTime.now()`.
int pregnancyDays(DateTime due, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final daysLeft = due.difference(today).inDays;
  return (280 - daysLeft).clamp(0, 280);
}

/// Gebelik haftası: (280 - kalan gün) ~/ 7. Gün 0..280 aralığına kırpılır.
///
/// Saf (test edilebilir): referans an [now] verilebilir; verilmezse
/// `DateTime.now()`.
int pregnancyWeeks(DateTime due, {DateTime? now}) => pregnancyDays(due, now: now) ~/ 7;
