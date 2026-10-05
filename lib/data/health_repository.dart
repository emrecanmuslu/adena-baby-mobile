import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../features/records/record_controller.dart';
import '../models/medication_plan.dart';
import '../models/milestone.dart';
import '../models/reminder.dart';
import '../models/tooth.dart';
import '../models/vaccine.dart';
import 'health_catalog.dart';
import 'local/app_database.dart';
import 'sync_gate.dart';

/// Sağlık (aşı/gelişim/diş/hatırlatıcı) — **local-first**. Liste = içerik
/// kataloğu (cache'li/asset) + bebeğe özel durum (Drift). Cloud yalnız premium'da
/// (`_cloudEnabled`): değişiklikte tüm durum `/babies/{id}/health/sync` ile
/// itilir, premium giriş/göçte `importFromCloud` ile mevcut GET uçlarından çekilir.
/// Free kullanıcı tamamen yerelde çalışır → 403 olmaz (eski bebeğe-bağlı GET
/// çağrıları kaldırıldı).
class HealthRepository {
  final AppDatabase _db;
  final ApiClient _api;
  final Future<HealthCatalog> Function() _catalog;
  /// Bu BEBEK bulut senkronuna tabi mi? Per-baby (Seçenek 2): paylaşılan bebek
  /// sahibin premium'uyla senkronlanır, kendi bebeğim kendi premium'umla.
  final bool Function(String babyId) _cloudEnabled;
  /// İlaç planı yerelde değişince çağrılır (senkron tetiklemek için; bkz. provider).
  final void Function(String babyId)? onPlansChanged;
  HealthRepository(this._db, this._api, this._catalog, this._cloudEnabled,
      {this.onPlansChanged});

  static const _uuid = Uuid();

  // ── Yardımcılar ──

  Future<DateTime?> _birthDate(String babyId) async {
    final row = await (_db.select(_db.babies)..where((b) => b.id.equals(babyId)))
        .getSingleOrNull();
    return row?.birthDate;
  }

  Future<Map<String, ({bool done, DateTime? date})>> _statusMap(
      String babyId, String kind) async {
    final rows = await (_db.select(_db.healthStatuses)
          ..where((s) => s.baby.equals(babyId) & s.kind.equals(kind)))
        .get();
    return {for (final r in rows) r.itemKey: (done: r.done, date: r.statusDate)};
  }

  Future<void> _writeStatus(
      String babyId, String kind, String key, bool done, DateTime? date) async {
    await _db.into(_db.healthStatuses).insertOnConflictUpdate(
          HealthStatusesCompanion.insert(
            baby: babyId,
            kind: kind,
            itemKey: key,
            done: Value(done),
            statusDate: Value(done ? date : null),
          ),
        );
  }

  Future<void> _setStatus(
      String babyId, String kind, String key, bool done, DateTime? date) async {
    await _writeStatus(babyId, kind, key, done, date);
    if (_cloudEnabled(babyId)) {
      try {
        await pushAll(babyId);
      } catch (_) {/* çevrimdışı — yerel korunur */}
    }
  }

  /// birth_date + ay → due_date (Python add_months ile birebir).
  DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final y = d.year + (total ~/ 12);
    final mm = (total % 12) + 1;
    final lastDay = DateTime(y, mm + 1, 0).day;
    return DateTime(y, mm, d.day < lastDay ? d.day : lastDay);
  }

  static String? _d(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parse(dynamic s) =>
      s is String && s.isNotEmpty ? DateTime.tryParse(s) : null;

  // ── Aşılar ──

  Future<List<Vaccine>> vaccines(String babyId) async {
    final birth = await _birthDate(babyId);
    if (birth == null) return const []; // doğum tarihi girilince üretilir
    final cat = await _catalog();
    final st = await _statusMap(babyId, 'vaccine');
    return cat.vaccines.map((v) {
      final s = st[v.key];
      return Vaccine(
        key: v.key,
        name: v.name,
        dueDate: _addMonths(birth, v.months),
        done: s?.done ?? false,
        doneDate: s?.date,
        optional: v.optional,
      );
    }).toList();
  }

  Future<void> setVaccineDone(String babyId, String key,
          {required bool done, DateTime? date}) =>
      _setStatus(babyId, 'vaccine', key, done, done ? (date ?? DateTime.now()) : null);

  // ── Gelişim / kilometre taşları ──

  Future<List<Milestone>> milestones(String babyId) async {
    final cat = await _catalog();
    final st = await _statusMap(babyId, 'milestone');
    return cat.milestones.map((m) {
      final s = st[m.key];
      return Milestone(
        key: m.key,
        category: m.category,
        title: m.title,
        description: m.description,
        tip: m.tip,
        expectedMonth: m.month,
        achieved: s?.done ?? false,
        achievedDate: s?.date,
      );
    }).toList();
  }

  Future<void> setMilestoneAchieved(String babyId, String key,
          {required bool achieved, DateTime? date}) =>
      _setStatus(babyId, 'milestone', key, achieved,
          achieved ? (date ?? DateTime.now()) : null);

  // ── Diş çıkarma ──

  Future<List<Tooth>> teeth(String babyId) async {
    final cat = await _catalog();
    final st = await _statusMap(babyId, 'tooth');
    return cat.teeth.map((t) {
      final s = st[t.key];
      return Tooth(
        key: t.key,
        jaw: t.jaw,
        side: t.side,
        position: t.position,
        name: t.name,
        typicalMonth: t.typicalMonth,
        erupted: s?.done ?? false,
        eruptedDate: s?.date,
      );
    }).toList();
  }

  Future<void> setToothErupted(String babyId, String key,
          {required bool erupted, DateTime? date}) =>
      _setStatus(babyId, 'tooth', key, erupted,
          erupted ? (date ?? DateTime.now()) : null);

  // ── Hatırlatıcılar (yerel int id → NotificationService) ──
  // KARAR (2026-07-07): hatırlatıcılar KİŞİSELDİR — aile paylaşımına dahil
  // değildir; buluta itilmez/çekilmez (herkes kendi cihazında kendi düzenini
  // kurar). Bu yüzden push/pull/import yolları kaldırıldı; yalnız Drift.

  Reminder _toReminder(ReminderRow r) => Reminder(
        id: r.localId,
        type: r.type,
        schedule:
            (jsonDecode(r.scheduleJson) as Map?)?.cast<String, dynamic>() ?? const {},
        enabled: r.enabled,
        createdAt: r.createdAt ?? DateTime.now(),
      );

  Future<List<Reminder>> reminders(String babyId) async {
    final rows = await (_db.select(_db.localReminders)
          ..where((r) => r.baby.equals(babyId)))
        .get();
    return rows.map(_toReminder).toList();
  }

  Future<Reminder> createReminder(String babyId,
      {required String type, required Map<String, dynamic> schedule}) async {
    final id = await _db.into(_db.localReminders).insert(
          LocalRemindersCompanion.insert(
            baby: babyId,
            type: Value(type),
            scheduleJson: Value(jsonEncode(schedule)),
            enabled: const Value(true),
            createdAt: Value(DateTime.now()),
          ),
        );
    final row = await (_db.select(_db.localReminders)
          ..where((r) => r.localId.equals(id)))
        .getSingle();
    return _toReminder(row);
  }

  Future<void> setReminderEnabled(int id, bool enabled) async {
    await (_db.update(_db.localReminders)..where((r) => r.localId.equals(id)))
        .write(LocalRemindersCompanion(enabled: Value(enabled)));
  }

  Future<void> deleteReminder(int id) async {
    await (_db.delete(_db.localReminders)..where((r) => r.localId.equals(id))).go();
  }

  // ── İlaç / vitamin planları (yerel int id → NotificationService) ──
  // AİLE PAYLAŞIMLI (2026-10-05): plan (ad/doz/saatler/duraklatma) diğer
  // üyelere aynalanır; "verildi" durumu zaten Record (RecordType.medication)
  // ile paylaşılıyordu. Bildirim cihaz-yerel kalır (herkes kendi telefonunda
  // açıp kapatır). Yerel yazım → dirty; `syncMedicationPlans` gönderir/çeker.

  MedicationPlan _toPlan(MedicationPlanRow r) => MedicationPlan(
        id: r.localId,
        name: r.name,
        dose: r.dose,
        times: (jsonDecode(r.timesJson) as List).cast<String>(),
        active: r.active,
        createdAt: r.createdAt ?? DateTime.now(),
      );

  /// Son-yazan-kazanır damgası. drift DateTime'ı saniyeye yuvarlar → aynı
  /// saniyedeki ardışık düzenleme sunucuda "eski" sayılmasın diye bir öncekinden
  /// kesinlikle ileri tutulur.
  DateTime _planStamp([DateTime? prev]) {
    final now = DateTime.now();
    if (prev != null && !now.isAfter(prev.add(const Duration(seconds: 1)))) {
      return prev.add(const Duration(seconds: 1));
    }
    return now;
  }

  Future<List<MedicationPlan>> medicationPlans(String babyId) async {
    final rows = await (_db.select(_db.medicationPlans)
          ..where((r) => r.baby.equals(babyId) & r.isDeleted.equals(false))
          // Her cihazda aynı sıra (yerel ekleme sırası cihazdan cihaza değişir).
          ..orderBy([
            (r) => OrderingTerm(expression: r.createdAt),
            (r) => OrderingTerm(expression: r.localId),
          ]))
        .get();
    return rows.map(_toPlan).toList();
  }

  Future<MedicationPlan> createMedicationPlan(String babyId,
      {required String name, required String dose, required List<String> times}) async {
    final now = DateTime.now();
    final id = await _db.into(_db.medicationPlans).insert(
          MedicationPlansCompanion.insert(
            baby: babyId,
            name: name,
            dose: Value(dose),
            timesJson: Value(jsonEncode(times)),
            createdAt: Value(now),
            uuid: Value(_uuid.v4()),
            clientUpdatedAt: Value(now),
          ),
        );
    final row = await (_db.select(_db.medicationPlans)
          ..where((r) => r.localId.equals(id)))
        .getSingle();
    onPlansChanged?.call(babyId);
    return _toPlan(row);
  }

  Future<void> updateMedicationPlan(int id,
      {String? name, String? dose, List<String>? times, bool? active}) async {
    final row = await (_db.select(_db.medicationPlans)
          ..where((r) => r.localId.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.medicationPlans)..where((r) => r.localId.equals(id))).write(
      MedicationPlansCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        dose: dose != null ? Value(dose) : const Value.absent(),
        timesJson: times != null ? Value(jsonEncode(times)) : const Value.absent(),
        active: active != null ? Value(active) : const Value.absent(),
        clientUpdatedAt: Value(_planStamp(row.clientUpdatedAt)),
        dirty: const Value(true),
      ),
    );
    onPlansChanged?.call(row.baby);
  }

  /// Bulut-senkronlu bebekte silme TOMBSTONE'dur (diğer üyelere taşınsın diye;
  /// sunucu onaylayınca satır gerçekten silinir). Yerel-only bebekte doğrudan silinir.
  Future<void> deleteMedicationPlan(int id) async {
    final row = await (_db.select(_db.medicationPlans)
          ..where((r) => r.localId.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    if (row.uuid != null && _cloudEnabled(row.baby)) {
      await (_db.update(_db.medicationPlans)..where((r) => r.localId.equals(id)))
          .write(MedicationPlansCompanion(
        isDeleted: const Value(true),
        clientUpdatedAt: Value(_planStamp(row.clientUpdatedAt)),
        dirty: const Value(true),
      ));
      onPlansChanged?.call(row.baby);
    } else {
      await (_db.delete(_db.medicationPlans)..where((r) => r.localId.equals(id))).go();
    }
  }

  /// Bekleyen yerel plan değişikliklerini gönderir ve sunucudaki TÜM planları
  /// (tombstone dahil) çekip yerele uygular — küme küçük olduğundan cursor yok,
  /// yanıt otoriterdir. Hata atarsa (çevrimdışı/403) çağıran yutar; yerel korunur.
  ///
  /// Döner: `changed` → görünen plan listesi değişti (provider tazelenmeli);
  /// `removed` → silinen satırların yerel id'leri (bildirimleri iptal edilmeli).
  ///
  /// Bakıcı sağlık verisinde salt-okunurdur: değişiklik göndermez, sunucudaki
  /// planlar yereldeki düzenlemesini ezer (kendi eklediği yerel plan ise kalır).
  Future<({bool changed, List<int> removed})> syncMedicationPlans(String babyId) async {
    final baby = await (_db.select(_db.babies)..where((b) => b.id.equals(babyId)))
        .getSingleOrNull();
    final readOnly = baby?.myRole == 'caregiver';
    Future<List<MedicationPlanRow>> load() =>
        (_db.select(_db.medicationPlans)..where((r) => r.baby.equals(babyId))).get();

    // v13'ten kalan (uuid'siz) satırlara ortak kimlik ver.
    for (final r in await load()) {
      if (r.uuid != null) continue;
      await (_db.update(_db.medicationPlans)..where((t) => t.localId.equals(r.localId)))
          .write(MedicationPlansCompanion(
        uuid: Value(_uuid.v4()),
        clientUpdatedAt: Value(r.clientUpdatedAt ?? r.createdAt ?? DateTime.now()),
      ));
    }

    final dirty = readOnly
        ? const <MedicationPlanRow>[]
        : (await load()).where((r) => r.dirty).toList();
    // Gönderilen damga → uçuş sırasında yeniden düzenlenen plan ezilmesin.
    final sent = {for (final r in dirty) r.uuid!: r.clientUpdatedAt};
    final resp = await _api.dio.post('/babies/$babyId/medication-plans/sync', data: {
      'changes': [
        for (final r in dirty)
          {
            'id': r.uuid,
            'op': r.isDeleted ? 'delete' : 'upsert',
            'name': r.name,
            'dose': r.dose,
            'times': jsonDecode(r.timesJson),
            'active': r.active,
            'client_updated_at': r.clientUpdatedAt?.toUtc().toIso8601String(),
          }
      ],
    });
    final data = resp.data as Map<String, dynamic>;
    final applied = (data['applied'] as List? ?? const []).cast<String>().toSet();
    final plans = (data['plans'] as List? ?? const []).cast<Map<String, dynamic>>();

    var changed = false;
    final removed = <int>[];
    bool sameStamp(DateTime? a, DateTime? b) =>
        a == null || b == null ? a == b : a.isAtSameMomentAs(b);

    await _db.transaction(() async {
      final local = {
        for (final r in await load())
          if (r.uuid != null) r.uuid!: r
      };
      Future<void> drop(MedicationPlanRow r) async {
        await (_db.delete(_db.medicationPlans)..where((t) => t.localId.equals(r.localId)))
            .go();
        removed.add(r.localId);
        if (!r.isDeleted) changed = true;
      }

      for (final sp in plans) {
        final id = sp['id'] as String;
        final l = local[id];
        // Gönderimden sonra yerelde yeniden düzenlendi → yerel kalsın, sonraki tur gönderir.
        final editedMidFlight = l != null &&
            l.dirty &&
            !readOnly &&
            !(sent.containsKey(id) && sameStamp(sent[id], l.clientUpdatedAt));
        if (editedMidFlight) continue;
        if (sp['is_deleted'] == true) {
          if (l != null) {
            local.remove(id);
            await drop(l);
          }
          continue;
        }
        final name = sp['name'] as String? ?? '';
        final dose = sp['dose'] as String? ?? '';
        final timesJson = jsonEncode((sp['times'] as List? ?? const []).cast<String>());
        final active = sp['active'] != false;
        final stamp = _parse(sp['client_updated_at'])?.toLocal();
        if (l == null) {
          await _db.into(_db.medicationPlans).insert(MedicationPlansCompanion.insert(
                baby: babyId,
                name: name,
                dose: Value(dose),
                timesJson: Value(timesJson),
                active: Value(active),
                createdAt: Value(_parse(sp['created_at'])?.toLocal() ?? DateTime.now()),
                uuid: Value(id),
                clientUpdatedAt: Value(stamp),
                dirty: const Value(false),
              ));
          changed = true;
          continue;
        }
        if (l.isDeleted ||
            l.name != name ||
            l.dose != dose ||
            l.timesJson != timesJson ||
            l.active != active) {
          changed = true;
        }
        await (_db.update(_db.medicationPlans)..where((t) => t.localId.equals(l.localId)))
            .write(MedicationPlansCompanion(
          name: Value(name),
          dose: Value(dose),
          timesJson: Value(timesJson),
          active: Value(active),
          isDeleted: const Value(false),
          clientUpdatedAt: Value(stamp),
          dirty: const Value(false),
        ));
      }
      // Sunucuda hiç olmamış planın silinmesi (applied ama listede yok) → tombstone'u at.
      for (final l in local.values) {
        if (l.isDeleted &&
            applied.contains(l.uuid) &&
            sameStamp(sent[l.uuid], l.clientUpdatedAt) &&
            !plans.any((sp) => sp['id'] == l.uuid)) {
          await drop(l);
        }
      }
    });
    return (changed: changed, removed: removed);
  }

  // ── Cloud (premium) ──

  /// Tüm sağlık DURUMUNU buluta iter (son-yazan-kazanır). Premium push (durum
  /// değişimi / migrasyon). Hatırlatıcılar KİŞİSEL olduğundan gönderilmez —
  /// 'reminders' anahtarı yoksa backend mevcut satırlara dokunmaz.
  Future<void> pushAll(String babyId) async {
    final vac = await vaccines(babyId);
    final mil = await milestones(babyId);
    final tee = await teeth(babyId);
    await _api.dio.post('/babies/$babyId/health/sync', data: {
      'vaccines': [
        for (final v in vac)
          {'name': v.name, 'done': v.done, 'done_date': _d(v.doneDate)}
      ],
      'milestones': [
        for (final m in mil)
          {'key': m.key, 'achieved': m.achieved, 'achieved_date': _d(m.achievedDate)}
      ],
      'teeth': [
        for (final t in tee)
          {'key': t.key, 'erupted': t.erupted, 'erupted_date': _d(t.eruptedDate)}
      ],
    });
  }

  /// Premium giriş/göçte bulutu yerele çeker (mevcut salt-okuma GET uçlarından).
  /// Yereldeki işaretleri korur; yalnız buluttaki "yapıldı"ları ekler.
  Future<void> importFromCloud(String babyId) async {
    try {
      final r = await _api.dio.get('/babies/$babyId/vaccines');
      for (final e in (r.data as List? ?? const [])) {
        final m = e as Map<String, dynamic>;
        if (m['status'] == 'done') {
          await _writeStatus(babyId, 'vaccine',
              m['vaccine_name'] as String? ?? '', true, _parse(m['done_date']));
        }
      }
    } catch (_) {}
    try {
      final r = await _api.dio.get('/babies/$babyId/milestones');
      for (final e in (r.data as List? ?? const [])) {
        final m = e as Map<String, dynamic>;
        if (m['achieved'] == true) {
          await _writeStatus(babyId, 'milestone', m['key'] as String? ?? '', true,
              _parse(m['achieved_date']));
        }
      }
    } catch (_) {}
    try {
      final r = await _api.dio.get('/babies/$babyId/teeth');
      for (final e in (r.data as List? ?? const [])) {
        final m = e as Map<String, dynamic>;
        if (m['erupted'] == true) {
          await _writeStatus(babyId, 'tooth', m['key'] as String? ?? '', true,
              _parse(m['erupted_date']));
        }
      }
    } catch (_) {}
    // Hatırlatıcılar KİŞİSEL (karar 2026-07-07) → buluttan içeri alınmaz.
  }

  Future<void> purgeBaby(String babyId) async {
    await (_db.delete(_db.healthStatuses)..where((s) => s.baby.equals(babyId))).go();
    await (_db.delete(_db.localReminders)..where((r) => r.baby.equals(babyId))).go();
    await (_db.delete(_db.medicationPlans)..where((r) => r.baby.equals(babyId))).go();
  }
}

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    () => ref.read(healthCatalogProvider.future),
    (babyId) => ref.read(babyCloudSyncedProvider(babyId)),
    // Plan değişti → aile senkronunu (debounce'lu) tetikle; planlar syncAll içinde gider.
    onPlansChanged: (_) => ref.read(syncServiceProvider).requestSyncSoon(),
  ),
);

/// Aktif bebeğin aşıları (due_date'e göre). Local-first → her kullanıcıda çalışır.
final vaccinesProvider = FutureProvider.family<List<Vaccine>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).vaccines(babyId),
);

/// Aktif bebeğin hatırlatıcıları (yerel).
final remindersProvider = FutureProvider.family<List<Reminder>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).reminders(babyId),
);

/// Aktif bebeğin gelişim/kilometre taşları (beklenen aya göre).
final milestonesProvider = FutureProvider.family<List<Milestone>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).milestones(babyId),
);

/// Aktif bebeğin süt dişleri.
final teethProvider = FutureProvider.family<List<Tooth>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).teeth(babyId),
);

/// Aktif bebeğin ilaç/vitamin planları (yerel kopya; aile senkronu syncAll'da).
final medicationPlansProvider = FutureProvider.family<List<MedicationPlan>, String>(
  (ref, babyId) => ref.watch(healthRepositoryProvider).medicationPlans(babyId),
);
