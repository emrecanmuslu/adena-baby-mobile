import '../models/baby.dart';
import 'age.dart';

/// Bebeğin (düzeltilmiş) doğumdan itibaren hafta cinsinden yaşı. Bekleme
/// modunda / doğum tarihi yoksa null. Prematüre bebekte "corrected" doğum
/// anına göre hesaplanır — atak haftaları da bu ankora göre tanımlıdır.
///
/// Saf (test edilebilir): referans an [now] verilebilir.
int? correctedAgeWeeks(Baby? b, {DateTime? now}) {
  if (b == null || b.isExpecting) return null;
  final bd = b.birthDate;
  if (bd == null) return null;
  final ref = now ?? DateTime.now();
  final adj = bd.add(Duration(days: prematureEarlyDays(b)));
  final a = DateTime(adj.year, adj.month, adj.day);
  final t = DateTime(ref.year, ref.month, ref.day);
  final days = t.difference(a).inDays;
  if (days < 0) return null; // TDT'ye henüz gelmedi (çok erken doğum)
  return days ~/ 7;
}

/// Bir atağın şu anki fazı.
enum LeapPhase {
  past, // atak geride kaldı
  fussy, // huzursuz öncesi dönemde
  peak, // atak haftasında/hemen sonrasında
  upcoming, // yakında (fussy penceresinden önce ama makul yakınlıkta) — banner'da gösterilmez, listede "yakında" rozeti için
  future, // çok ileride
}

/// Verilen atak için [weeks] yaşındaki bebeğe göre faz. [fussyWeeksBefore]
/// ataktan önceki yaklaşık huzursuz pencere uzunluğu; atak zirvesi başlangıç
/// haftasından ~1 hafta sonrasına kadar sürdüğü varsayılır (kabaca/genel).
LeapPhase leapPhase(int weeks, int weekStart, double fussyWeeksBefore) {
  final fussyStart = weekStart - fussyWeeksBefore;
  final peakEnd = weekStart + 1;
  if (weeks < fussyStart) return LeapPhase.future;
  if (weeks < weekStart) return LeapPhase.fussy;
  if (weeks <= peakEnd) return LeapPhase.peak;
  return LeapPhase.past;
}

/// Ana sayfa banner'ı için "şu an alakalı" atak var mı? fussy/peak fazındaki
/// EN YAKIN atağı döner (yoksa null — banner gizlenir). Birden fazla aday
/// varsa (nadiren üst üste binebilir) haftası daha yakın olan önceliklidir.
T? relevantLeap<T>(
  List<T> leaps, {
  required int Function(T) index,
  required int Function(T) weekStart,
  required double Function(T) fussyWeeksBefore,
  required int weeks,
}) {
  T? best;
  int? bestDist;
  for (final l in leaps) {
    final phase = leapPhase(weeks, weekStart(l), fussyWeeksBefore(l));
    if (phase != LeapPhase.fussy && phase != LeapPhase.peak) continue;
    final dist = (weekStart(l) - weeks).abs();
    if (bestDist == null || dist < bestDist) {
      best = l;
      bestDist = dist;
    }
  }
  return best;
}
