import '../models/medication_plan.dart';
import '../models/record.dart';

/// Bugünkü tek bir ilaç dozunun durumu — ana sayfa checklist'i + snackbar için.
enum MedicationDoseStatus { given, overdue, upcoming }

/// Bir planın bugün için TEK zamanlanmış dozu (checklist satırı). [record] —
/// verildiyse eşleşen `Record` (id'si "geri al" silmesi, `ts`'i saat, `createdBy`
/// "kim verdi" göstermesi için taşınır).
class MedicationDose {
  final MedicationPlan plan;
  final String time; // "HH:MM"
  final MedicationDoseStatus status;
  final Record? record;
  const MedicationDose(
      {required this.plan, required this.time, required this.status, this.record});

  bool get isGiven => status == MedicationDoseStatus.given;
  bool get isOverdue => status == MedicationDoseStatus.overdue;
  DateTime? get givenAt => record?.ts;
}

/// Aktif planların bugünkü dozlarının durumunu hesaplar. Eşleme YALIN tutulur:
/// bir planın adına ([plan.name], küçük/büyük harf ve boşluk duyarsız) eşleşen
/// bugünkü `RecordType.medication` kayıtları saat sırasına göre planın
/// saatleriyle SIRAYLA eşlenir (1. kayıt → 1. doz, 2. kayıt → 2. doz…) — kaydın
/// hangi saate ait olduğunu ayrıca sormaz, günde 1-2 doz için yeterince
/// doğrudur ve aile paylaşımlı `Record` sistemini olduğu gibi kullanır (yeni
/// bir "hangi doz" alanı gerekmez). [allRecords] önceden "bugün"e filtrelenmiş
/// OLMAK ZORUNDA DEĞİL — gün filtresi burada uygulanır (çağıran ham/son-N-gün
/// listesi verebilir).
///
/// Saf (test edilebilir): referans an [now] verilebilir.
List<MedicationDose> todaysMedicationDoses(
  List<MedicationPlan> plans,
  List<Record> allRecords, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final todayRecords = allRecords.where((r) {
    final d = DateTime(r.ts.year, r.ts.month, r.ts.day);
    return d == today;
  }).toList();
  final out = <MedicationDose>[];
  for (final plan in plans.where((p) => p.active)) {
    final given = todayRecords
        .where((r) =>
            r.type == RecordType.medication &&
            (r.data['name'] as String? ?? '').trim().toLowerCase() ==
                plan.name.trim().toLowerCase())
        .toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    final times = [...plan.times]..sort();
    for (var i = 0; i < times.length; i++) {
      final t = times[i];
      final parts = t.split(':');
      final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
      final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      final due = DateTime(ref.year, ref.month, ref.day, h, m);
      if (i < given.length) {
        out.add(MedicationDose(
            plan: plan, time: t, status: MedicationDoseStatus.given, record: given[i]));
      } else {
        out.add(MedicationDose(
          plan: plan,
          time: t,
          status:
              due.isBefore(ref) ? MedicationDoseStatus.overdue : MedicationDoseStatus.upcoming,
        ));
      }
    }
  }
  return out;
}
