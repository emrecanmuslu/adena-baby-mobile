import '../../models/medication_plan.dart';
import '../../models/record.dart';
import '../medication.dart';
import 'med_names.dart';

/// İlaç v2 (A3) — doz kaydı yazımının SAF parçaları: kimlikli kayıt kurucusu,
/// atlama nedenleri (K10) ve çift doz denetimi (K3).

/// Atlama nedenleri (K10) — backend `med_push._REASONS` ile aynı kodlar.
enum MedSkipReason {
  vomited('vomited'),
  asleep('asleep'),
  outOfStock('out_of_stock'),
  doctor('doctor'),
  other('other');

  final String wire;
  const MedSkipReason(this.wire);
  static MedSkipReason? fromWire(String? s) {
    for (final r in values) {
      if (r.wire == s) return r;
    }
    return null;
  }
}

/// "Diğer" notunun üst sınırı.
const kMedSkipNoteMax = 80;

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Doz kaydı (`RecordType.medication`, ILAC-TASARIM §1b). [at] = gerçek
/// veriliş/işaret anı (`ts`); kimlik ([doseDate] + [doseTime]) `ts`'den
/// bağımsızdır. PRN'de [doseTime] verilmez. [timeAssumed] = gerçek saat
/// bilinmiyor, plan saatine yazıldı (M20).
Record medDoseRecord({
  required String id,
  required String babyId,
  required MedicationPlan plan,
  required DateTime doseDate,
  String? doseTime,
  required DateTime at,
  required bool skipped,
  MedSkipReason? reason,
  String? note,
  bool timeAssumed = false,
}) {
  final trimmed = note?.trim();
  return Record(
    id: id,
    baby: babyId,
    type: RecordType.medication,
    ts: at,
    data: {
      'v': 2,
      'name': plan.name,
      'dose': plan.dose,
      'plan_uuid': ?plan.uuid,
      'kind': plan.kind.wire,
      'dose_date': medDateToWire(doseDate),
      if (!plan.isPrn && doseTime != null) 'dose_time': doseTime,
      'given': !skipped,
      if (skipped) 'skipped': true,
      if (skipped && reason != null) 'skip_reason': reason.wire,
      if (skipped && reason == MedSkipReason.other && trimmed != null && trimmed.isNotEmpty)
        'skip_note': trimmed.length > kMedSkipNoteMax
            ? trimmed.substring(0, kMedSkipNoteMax)
            : trimmed,
      'at_hm': _hm(at),
      if (timeAssumed) 'time_assumed': true,
    },
  );
}

/// Planın iki doz arasındaki en kısa süre (K3 "gizli çift" eşiği yarısı).
Duration medMinGap(MedicationPlan p) {
  if (p.freq == MedFreq.interval && p.intervalHours != null) {
    return Duration(hours: p.intervalHours!);
  }
  final ms = [for (final t in p.times) medicationMinutes(t)]..sort();
  if (ms.length < 2) return const Duration(hours: 24);
  var best = 24 * 60 - ms.last + ms.first; // gece sarması
  for (var i = 1; i < ms.length; i++) {
    final d = ms[i] - ms[i - 1];
    if (d < best) best = d;
  }
  return Duration(minutes: best);
}

/// K3 isabeti: [record] = önceki "verildi" kaydı; [sameDose] = aynı doz.
class MedDupHit {
  final Record record;
  final bool sameDose;
  const MedDupHit(this.record, this.sameDose);
}

/// Bu planın "verildi" kaydı mı? Kimlikli kayıt plan uuid'siyle; W6
/// (ILAC-INCELEME-3): kimliksiz (eski istemci / v15) kayıt ad anahtarıyla —
/// hiçbir doza bağlanmasa da (ör. gece yarısından önce erken verildi) çift doz
/// uyarısına girer.
bool _mine(MedicationPlan p, Record r) {
  if (r.type != RecordType.medication || r.isDeleted || r.data['skipped'] == true) return false;
  final uuid = r.data['plan_uuid'];
  if (uuid == null) {
    final name = r.data['name'];
    return name is String && medNameKey(name) == medNameKey(p.name);
  }
  return p.uuid != null && uuid == p.uuid;
}

/// "Verildi" yazmadan önce çift doz denetimi (K3):
/// 1. [dose] zaten verilmişse → ilk veren ([sameDose] true);
/// 2. aynı planda, şu andan planın en kısa doz aralığının YARISINDAN az önce
///    verilmiş bir kayıt varsa (saat değişikliği / eski kayıt kaynaklı gizli
///    çift) → o kayıt;
/// 3. PRN: kullanıcının girdiği en kısa aralık dolmadıysa → son veriliş.
/// Kayıt yoksa null. [records] silinmiş/atlanmış içerebilir (yok sayılır).
MedDupHit? medDuplicateCheck(
  MedicationPlan plan,
  MedicationDose? dose,
  Iterable<Record> records, {
  required DateTime now,
}) {
  if (dose != null && dose.givenRecords.isNotEmpty) {
    return MedDupHit(dose.givenRecords.first, true);
  }
  final Duration window;
  if (plan.isPrn) {
    if (plan.prnMinIntervalMin == null) return null;
    window = Duration(minutes: plan.prnMinIntervalMin!);
  } else {
    window = medMinGap(plan) ~/ 2;
  }
  Record? last;
  for (final r in records) {
    if (!_mine(plan, r) || r.ts.isAfter(now)) continue;
    if (now.difference(r.ts) >= window) continue;
    if (last == null || r.ts.isAfter(last.ts)) last = r;
  }
  return last == null ? null : MedDupHit(last, false);
}
