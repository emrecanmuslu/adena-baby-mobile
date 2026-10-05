import '../models/medication_plan.dart';
import '../models/record.dart';

/// Bugünkü tek bir ilaç dozunun durumu — ana sayfa doz kartı için.
/// [skipped] = bilinçli olarak verilmedi ("atlandı"); verilmiş sayılmaz ama
/// "saati geçti" uyarısından çıkar. Kayıt olarak `data.skipped == true` taşıyan
/// bir `RecordType.medication` satırıdır (aile paylaşımlı, yeni tablo/alan yok).
enum MedicationDoseStatus { given, skipped, overdue, upcoming }

/// Dozun dokunma rolü. Kayıtlar plan saatleriyle SIRAYLA eşlendiği için yalnız
/// iki doz DEĞİŞTİRİLEBİLİR: [next] (sıradaki — "verildi"/"atlandı" kaydı
/// yazılır) ve [undo] (son işaretlenen — geri alınabilir). Geri kalan her doz
/// [lock]: daha erken işaretlenenler (yalnız saati düzeltilebilir) ve sırası
/// gelmemiş ileri saatler. Böylece kayıt yanlış saate düşemez.
enum MedicationDoseRole { next, undo, lock }

/// Bir planın bugün için TEK zamanlanmış dozu (kart satırındaki bir düğme).
/// [record] — verildiyse eşleşen `Record` (id'si "geri al" silmesi, `ts`'i saat,
/// `createdBy` "kim verdi" göstermesi için taşınır).
class MedicationDose {
  final MedicationPlan plan;
  final String time; // "HH:MM"
  final MedicationDoseStatus status;
  final MedicationDoseRole role;
  final Record? record;
  const MedicationDose(
      {required this.plan,
      required this.time,
      required this.status,
      this.role = MedicationDoseRole.lock,
      this.record});

  bool get isGiven => status == MedicationDoseStatus.given;
  bool get isSkipped => status == MedicationDoseStatus.skipped;
  bool get isOverdue => status == MedicationDoseStatus.overdue;

  /// Verildi ya da atlandı — bir kaydı var, artık beklemiyor.
  bool get isResolved => isGiven || isSkipped;
  DateTime? get givenAt => record?.ts;
}

/// "HH:MM" → gün içi dakika (bozuk girdide 09:00 varsayılır).
int medicationMinutes(String t) {
  final parts = t.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 9;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return h * 60 + m;
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
    // Plan saatinden fazla kayıt olabilir (plan dışı ek doz) → fazlası sayılmaz.
    final k = given.length < times.length ? given.length : times.length;
    for (var i = 0; i < times.length; i++) {
      final t = times[i];
      final mins = medicationMinutes(t);
      final due = DateTime(ref.year, ref.month, ref.day, mins ~/ 60, mins % 60);
      final role = i == k
          ? MedicationDoseRole.next
          : (i == k - 1 ? MedicationDoseRole.undo : MedicationDoseRole.lock);
      if (i < k) {
        out.add(MedicationDose(
            plan: plan,
            time: t,
            status: given[i].data['skipped'] == true
                ? MedicationDoseStatus.skipped
                : MedicationDoseStatus.given,
            role: role,
            record: given[i]));
      } else {
        out.add(MedicationDose(
          plan: plan,
          time: t,
          role: role,
          status:
              due.isBefore(ref) ? MedicationDoseStatus.overdue : MedicationDoseStatus.upcoming,
        ));
      }
    }
  }
  return out;
}

/// Bir planın bugünkü satırı (kartta tek satır): dozları + özet durumu.
class MedicationPlanDay {
  final MedicationPlan plan;
  final List<MedicationDose> doses; // saat sırasıyla
  const MedicationPlanDay({required this.plan, required this.doses});

  int get givenCount => doses.where((d) => d.isGiven).length;
  int get resolvedCount => doses.where((d) => d.isResolved).length;

  /// Bekleyen doz kalmadı (hepsi verildi ya da atlandı).
  bool get complete => resolvedCount == doses.length;

  /// Saati geçmiş, verilmemiş ilk doz (yoksa null).
  MedicationDose? get firstOverdue {
    for (final d in doses) {
      if (d.isOverdue) return d;
    }
    return null;
  }

  /// Sıradaki (dokunulabilir) doz; hepsi verildiyse null.
  MedicationDose? get next {
    for (final d in doses) {
      if (d.role == MedicationDoseRole.next) return d;
    }
    return null;
  }

  /// Son işaretlenen doz (tamamlanmış satırın "Verildi/Atlandı · saat" metni).
  MedicationDose? get lastResolved {
    MedicationDose? out;
    for (final d in doses) {
      if (d.isResolved) out = d;
    }
    return out;
  }

  // Sıralama: önce saati geçenler, sonra bekleyenler, en sonda tamamlananlar.
  int get _rank => firstOverdue != null ? 0 : (complete ? 2 : 1);
  int get _sortMinutes => complete ? 9999 : medicationMinutes(next!.time);
}

/// Bugünün ilaç/vitamin özeti — ana sayfa bölümü, + menüsü rozeti, yönetim
/// ekranı ve Hatırlatıcılar satırı aynı hesaptan beslenir.
class MedicationDay {
  final List<MedicationPlanDay> rows; // sıralı (bkz. [MedicationPlanDay._rank])
  final int planCount; // pasifler dahil tüm planlar (keşif kartı kararı için)
  final DateTime now;
  const MedicationDay({required this.rows, required this.planCount, required this.now});

  Iterable<MedicationDose> get _all => rows.expand((r) => r.doses);

  int get total => _all.length;
  int get done => _all.where((d) => d.isGiven).length; // yalnız VERİLENLER
  int get overdue => _all.where((d) => d.isOverdue).length;
  bool get hasActive => rows.isNotEmpty;

  /// Bekleyen doz kalmadı — atlananlar da "tamam" sayılır (ama [done]'a girmez).
  bool get allDone => total > 0 && _all.every((d) => d.isResolved);

  /// Bütün dozlar saat sırasıyla — karttaki "gün çubuğu" segmentleri.
  List<MedicationDose> get timeline => _all.toList()
    ..sort((a, b) => medicationMinutes(a.time).compareTo(medicationMinutes(b.time)));

  /// Günün ilk doz saati ("yarın ilk doz 08:00" metni için).
  String? get firstTime => total == 0 ? null : timeline.first.time;

  /// Henüz zamanı gelmemiş en yakın doz saati.
  String? get nextUpcoming {
    for (final d in timeline) {
      if (d.status == MedicationDoseStatus.upcoming) return d.time;
    }
    return null;
  }

  /// Bölüm ana sayfada yukarı (Hızlı Giriş'in altına) çıksın mı: saati geçmiş
  /// doz varsa ya da sıradaki doza 60 dk'dan az kaldıysa.
  bool get promote {
    if (overdue > 0) return true;
    final t = nextUpcoming;
    if (t == null) return false;
    return medicationMinutes(t) - (now.hour * 60 + now.minute) <= 60;
  }
}

/// [plans] (pasifler dahil) + kayıtlardan bugünün özetini üretir. Saf.
MedicationDay medicationDay(
  List<MedicationPlan> plans,
  List<Record> allRecords, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final doses = todaysMedicationDoses(plans, allRecords, now: ref);
  final rows = <MedicationPlanDay>[
    for (final p in plans.where((p) => p.active))
      MedicationPlanDay(plan: p, doses: doses.where((d) => d.plan.id == p.id).toList()),
  ]
    ..removeWhere((r) => r.doses.isEmpty)
    ..sort((a, b) {
      final r = a._rank.compareTo(b._rank);
      return r != 0 ? r : a._sortMinutes.compareTo(b._sortMinutes);
    });
  return MedicationDay(rows: rows, planCount: plans.length, now: ref);
}
