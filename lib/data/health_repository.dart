import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../features/records/record_controller.dart';
import '../models/medication_plan.dart';
import '../models/milestone.dart';
import '../models/reminder.dart';
import '../models/tooth.dart';
import '../models/vaccine.dart';
import '../core/sync_telemetry.dart';
import 'health_catalog.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'sync_gate.dart';
import 'sync_merge.dart';

/// I1 — sahip bebekte sağlık pull'u (R1 "temiz satıra sunucu yazılır") yalnız
/// bu hesabın yerel kümesi bir kez buluta TAM yüklendikten sonra güvenlidir:
/// free→premium geçişinde ve lapse→yeniden abonelikte sunucu kümesi boş/bayat
/// olduğundan pull, v14'te işaretlenmiş TEMİZ (dirty=0, K-4 aşı backfill'i yok)
/// tikleri siler, ardından göç `pushAll` bunu mühürlerdi. Paylaşılan bebek
/// (parent/caregiver) sahibin bulutundan beslenir → kapı yok.
bool healthPullAllowed({
  required bool shared,
  required bool premiumSynced,
  required bool reseedPending,
}) =>
    shared || (premiumSynced && !reseedPending);

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
  /// Aşı/gelişim/diş işareti yerelde değişince çağrılır (K4/O21: ağ beklenmez,
  /// senkron `requestSyncSoon` ile arka planda).
  final void Function(String babyId)? onStatusChanged;
  HealthRepository(this._db, this._api, this._catalog, this._cloudEnabled,
      {this.onPlansChanged, this.onStatusChanged});

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

  /// [dirty] true = kullanıcı işareti (push bekler, pull ezmez — R1);
  /// false = sunucudan gelen/onaylanan değer (`pushError` da temizlenir).
  Future<void> _writeStatus(
      String babyId, String kind, String key, bool done, DateTime? date,
      {required bool dirty}) async {
    await _db.into(_db.healthStatuses).insertOnConflictUpdate(
          HealthStatusesCompanion.insert(
            baby: babyId,
            kind: kind,
            itemKey: key,
            done: Value(done),
            statusDate: Value(done ? date : null),
            dirty: Value(dirty),
            clientUpdatedAt: Value(dirty ? DateTime.now().toUtc() : null),
            pushError: const Value(null),
          ),
        );
  }

  /// Yerel yazım + dirty; AĞ BEKLENMEZ (O21). Bulut açıksa senkron tetiklenir
  /// (`onStatusChanged` → `requestSyncSoon`), delta push `pushDirty` ile gider.
  Future<void> _setStatus(
      String babyId, String kind, String key, bool done, DateTime? date) async {
    await _writeStatus(babyId, kind, key, done, date, dirty: true);
    if (_cloudEnabled(babyId)) onStatusChanged?.call(babyId);
  }

  /// Push'tan sonra yankı bekleyen aşı işaretleri: babyId → {itemKey: (done, damga)}.
  /// O19 güvencesi: sunucu aşıyı ADLA eşler; dil uyuşmazlığında 2xx ama sessiz
  /// no-op olur. `dirty=false` yalnız pull'da aynı ad + aynı değer yankılanınca
  /// yazılır; yankı yoksa satır dirty kalır (R1 pull'dan korur, tik kaybolmaz).
  final Map<String, Map<String, ({bool done, DateTime? date, DateTime? stamp})>>
      _vaccineEcho = {};

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

  /// Cihazdaki TÜM bebeklerin AÇIK hatırlatıcı id'leri — `NotificationService.sync`
  /// mutabakatı bununla yapılır (tek bebeğin listesiyle yapılınca diğer bebeklerin
  /// bildirimleri yetim sanılıp siliniyordu, BULGULAR.md K1).
  /// I5: tombstone (silinmiş) bebeğin hatırlatıcıları "aktif" sayılmaz — aksi
  /// hâlde mutabakat onları hiç yetim görmez, silinmiş bebek için çalmaya
  /// devam ederlerdi.
  Future<Set<int>> activeReminderIds() async {
    final q = _db.select(_db.localReminders).join([
      innerJoin(_db.babies, _db.babies.id.equalsExp(_db.localReminders.baby)),
    ])
      ..where(_db.localReminders.enabled.equals(true) &
          _db.babies.isDeleted.equals(false));
    final rows = await q.get();
    return {for (final r in rows) r.readTable(_db.localReminders).localId};
  }

  /// Bir bebeğin TÜM özel/randevu hatırlatıcı id'leri (bildirim iptali için, I5).
  Future<List<int>> reminderIdsForBaby(String babyId) async {
    final rows = await (_db.select(_db.localReminders)
          ..where((r) => r.baby.equals(babyId)))
        .get();
    return [for (final r in rows) r.localId];
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

  MedicationPlan _toPlan(MedicationPlanRow r, {bool localOnly = false}) =>
      MedicationPlan(
        id: r.localId,
        name: r.name,
        dose: r.dose,
        times: (jsonDecode(r.timesJson) as List).cast<String>(),
        active: r.active,
        createdAt: r.createdAt ?? DateTime.now(),
        localOnly: localOnly,
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

  // I13 / KB-10: "yalnız bu cihazda" = bakıcıda dirty VE sunucunun bildiği bir
  // plan DEĞİL. Sunucunun bildiği plan id'leri her başarılı senkronda prefs'e
  // yazılır (şema değişikliği yok); senkron henüz hiç koşmadıysa küme boştur ve
  // eski kontrat (dirty → yerel-only) geçerli kalır.
  static String _kServerPlanIds(String babyId) => 'med_server_plan_ids_$babyId';

  Future<Set<String>> _serverKnownPlanIds(String babyId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getStringList(_kServerPlanIds(babyId)) ?? const []).toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<void> _rememberServerPlanIds(String babyId, Iterable<String> ids) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kServerPlanIds(babyId), ids.toSet().toList());
    } catch (_) {}
  }

  bool _isLocalOnly(MedicationPlanRow r, Set<String> serverKnown) =>
      r.dirty && !(r.uuid != null && serverKnown.contains(r.uuid));

  Future<List<MedicationPlan>> medicationPlans(String babyId) async {
    // N2/KB-10: bakıcıda sunucuya hiç gitmemiş dirty satır = yerel-only plan.
    final caregiver = await _isCaregiver(babyId);
    final known = caregiver ? await _serverKnownPlanIds(babyId) : const <String>{};
    final rows = await (_db.select(_db.medicationPlans)
          ..where((r) => r.baby.equals(babyId) & r.isDeleted.equals(false))
          // Her cihazda aynı sıra (yerel ekleme sırası cihazdan cihaza değişir).
          ..orderBy([
            (r) => OrderingTerm(expression: r.createdAt),
            (r) => OrderingTerm(expression: r.localId),
          ]))
        .get();
    return rows
        .map((r) => _toPlan(r, localOnly: caregiver && _isLocalOnly(r, known)))
        .toList();
  }

  /// Cihazdaki TÜM bebeklerin aktif (silinmemiş) ilaç planı yerel id'leri —
  /// `NotificationService.syncMedicationPlans` yetim-bildirim mutabakatı için
  /// (BULGULAR.md K5).
  Future<Set<int>> activeMedicationPlanIds() async {
    final rows = await (_db.select(_db.medicationPlans)
          ..where((r) => r.active.equals(true) & r.isDeleted.equals(false)))
        .get();
    return {for (final r in rows) r.localId};
  }

  /// KB-8: bakıcı (caregiver) ilaç planı EKLEYEMEZ/düzenleyemez/silemez —
  /// backend `can_full_write` reddeder, senkron göndermezdi → cihazda hayalet
  /// plan kalırdı. K-7/O20 deseni: repo `StateError`, UI kilit + toast. Bakıcı
  /// yalnız doz işaretler (kayıt senkronu rolden bağımsız gönderir).
  Future<void> _requireFullWrite(String babyId) async {
    final b = await (_db.select(_db.babies)..where((x) => x.id.equals(babyId)))
        .getSingleOrNull();
    if (b?.myRole == 'caregiver') throw StateError('caregiver_readonly: $babyId');
  }

  Future<MedicationPlan> createMedicationPlan(String babyId,
      {required String name, required String dose, required List<String> times}) async {
    await _requireFullWrite(babyId);
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
    await _requireFullWrite(row.baby); // KB-8
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
    // N2/KB-10: bakıcı yalnız KB-8 öncesinden kalmış yerel-only (dirty) planını
    // silebilir — sunucuya hiç gitmemiştir, yerelden kaldırılır (senkron yok).
    if (await _isCaregiver(row.baby)) {
      if (!_isLocalOnly(row, await _serverKnownPlanIds(row.baby))) {
        throw StateError('caregiver_readonly: ${row.baby}'); // I13: sunucu planı
      }
      await (_db.delete(_db.medicationPlans)..where((r) => r.localId.equals(id))).go();
      onPlansChanged?.call(row.baby);
      return;
    }
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
    // I13: sunucunun bildiği plan kümesi (bakıcı "yalnız bu cihazda" ayrımı için).
    await _rememberServerPlanIds(babyId, [for (final sp in plans) sp['id'] as String]);

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

  /// J2 / KB-12 — lapse→yeniden abonelikte yeniden-tohumlama: TAM küme DEĞİL,
  /// **birleşim** semantiği. Backend damgasız son-yazan-kazanır olduğundan tam
  /// küme (damgasız `done=false` dahil) çok cihazlı ailede diğer cihazın
  /// işaretlerini ezerdi. Gönderilen: (1) `done=true` satırlar, (2)
  /// `clientUpdatedAt != null` satırlar (v15'te kullanıcı eliyle değişti; açık
  /// "kaldırma" dahil). Damgasız `done=false` (v14 varsayılanı) gönderilmez.
  /// Gönderilecek satır yoksa istek atılmaz. İlk göç `pushAll` ile tam kümedir.
  Future<void> pushReseed(String babyId) async {
    final rows = await (_db.select(_db.healthStatuses)
          ..where((s) =>
              s.baby.equals(babyId) &
              (s.done.equals(true) | s.clientUpdatedAt.isNotNull())))
        .get();
    if (rows.isEmpty) return;
    List<Map<String, Object?>> items(String kind, String keyField,
        String doneField, String dateField) =>
        [
          for (final r in rows.where((r) => r.kind == kind))
            {
              keyField: r.itemKey,
              doneField: r.done,
              dateField: _d(r.statusDate),
            }
        ];
    await _api.dio.post('/babies/$babyId/health/sync', data: {
      'vaccines': items('vaccine', 'name', 'done', 'done_date'),
      'milestones': items('milestone', 'key', 'achieved', 'achieved_date'),
      'teeth': items('tooth', 'key', 'erupted', 'erupted_date'),
    });
  }

  /// Delta push (K4, R7): yalnız `dirty=true` satırlar `/health/sync`'e gider;
  /// backend yalnız gönderilen kalemleri günceller. 2xx → gelişim/diş satırları
  /// damga değişmediyse temizlenir (R5); aşılar yankı bekler (`pull`, O19).
  /// Kalıcı 4xx → `pushError` (R3), dirty kalır, fırlatmaz. Geçici hata (ağ/5xx/
  /// 401/403) → fırlatır (syncAll 403'ü salt-okunur kapısına, diğerini hadError'a
  /// düşürür), dirty kalır.
  /// Yankılanmayan (dil uyuşmazlığı) aşı anahtarları — M9(a): her 1 dk polling
  /// turunda yeniden POST edilmesin; yalnız tam turlarda (açılış/öne geliş/
  /// işaretleme, `retryUnechoed: true`) yeniden denenir. Süreç ömrü.
  final Map<String, Set<String>> _unechoedVaccines = {};

  Future<void> pushDirty(String babyId, {bool retryUnechoed = true}) async {
    var rows = await (_db.select(_db.healthStatuses)
          ..where((s) => s.baby.equals(babyId) & s.dirty.equals(true)))
        .get();
    if (!retryUnechoed) {
      final skip = _unechoedVaccines[babyId] ?? const <String>{};
      rows = rows.where((r) => !(r.kind == 'vaccine' && skip.contains(r.itemKey))).toList();
    }
    if (rows.isEmpty) return;
    final cat = await _catalog();
    String vaccineName(String key) {
      for (final v in cat.vaccines) {
        if (v.key == key) return v.name;
      }
      return key; // katalogta yok (dil değişti) → ad olarak gönder, yankı bekler
    }

    try {
      await _api.dio.post('/babies/$babyId/health/sync', data: {
        'vaccines': [
          for (final r in rows.where((r) => r.kind == 'vaccine'))
            {
              'name': vaccineName(r.itemKey),
              'done': r.done,
              'done_date': _d(r.statusDate)
            }
        ],
        'milestones': [
          for (final r in rows.where((r) => r.kind == 'milestone'))
            {'key': r.itemKey, 'achieved': r.done, 'achieved_date': _d(r.statusDate)}
        ],
        'teeth': [
          for (final r in rows.where((r) => r.kind == 'tooth'))
            {'key': r.itemKey, 'erupted': r.done, 'erupted_date': _d(r.statusDate)}
        ],
      });
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // K-1: 403 + caregiver (rol düşmüş) → 'role'; kalıcı 4xx → 'HTTP n'.
      final roleErr = status == 403 && await _isCaregiver(babyId);
      if (roleErr || classifyDioError(e) == PushFailure.permanent) {
        final code = roleErr ? 'role' : 'HTTP $status';
        for (final r in rows) {
          await _setPushError(babyId, r.kind, r.itemKey, code);
        }
        return;
      }
      rethrow;
    }
    final echo = _vaccineEcho.putIfAbsent(babyId, () => {});
    for (final r in rows) {
      if (r.kind == 'vaccine') {
        echo[r.itemKey] =
            (done: r.done, date: r.statusDate, stamp: r.clientUpdatedAt);
        continue;
      }
      await _clearDirtyIfUnchanged(
          babyId, r.kind, r.itemKey, r.clientUpdatedAt, r.done, r.statusDate);
    }
  }

  Future<bool> _isCaregiver(String babyId) async {
    final b = await (_db.select(_db.babies)..where((x) => x.id.equals(babyId)))
        .getSingleOrNull();
    return b?.myRole == 'caregiver';
  }

  /// K-1 "geri al": ilgili türün sunucu listesinde kalem varsa sunucu değeri
  /// yazılır (dirty=false, pushError=null); kalem yoksa yerel değer korunur,
  /// yalnız bayraklar temizlenir (sağlıkta silinecek satır yok).
  Future<RevertResult> revertToServer(String babyId, String kind, String key) async {
    final path = switch (kind) {
      'vaccine' => 'vaccines',
      'milestone' => 'milestones',
      _ => 'teeth',
    };
    try {
      final r = await _api.dio.get('/babies/$babyId/$path');
      if (r.statusCode != 200 || r.data is! List) return RevertResult.failed;
      for (final e in r.data as List) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final k = kind == 'vaccine' ? m['vaccine_name'] : m['key'];
        if (k != key) continue;
        final done = switch (kind) {
          'vaccine' => m['status'] == 'done',
          'milestone' => m['achieved'] == true,
          _ => m['erupted'] == true,
        };
        final date = _parse(m[switch (kind) {
          'vaccine' => 'done_date',
          'milestone' => 'achieved_date',
          _ => 'erupted_date',
        }]);
        await _writeStatus(babyId, kind, key, done, date, dirty: false);
        return RevertResult.applied;
      }
      await (_db.update(_db.healthStatuses)
            ..where((s) =>
                s.baby.equals(babyId) & s.kind.equals(kind) & s.itemKey.equals(key)))
          .write(const HealthStatusesCompanion(
              dirty: Value(false), pushError: Value(null)));
      return RevertResult.applied;
    } catch (_) {
      return RevertResult.failed;
    }
  }

  Future<void> _setPushError(
      String babyId, String kind, String key, String? err) async {
    await (_db.update(_db.healthStatuses)
          ..where((s) =>
              s.baby.equals(babyId) & s.kind.equals(kind) & s.itemKey.equals(key)))
        .write(HealthStatusesCompanion(pushError: Value(err)));
  }

  /// R5: gönderim sırasında satır yeniden değiştiyse dirty kalır. Damga saniye
  /// çözünürlüklü saklandığından (drift DateTime = unix saniye) değer de
  /// karşılaştırılır: aynı saniyede geri alınan işaret temizlenmez.
  Future<void> _clearDirtyIfUnchanged(String babyId, String kind, String key,
      DateTime? sentStamp, bool sentDone, DateTime? sentDate) async {
    final cur = await (_db.select(_db.healthStatuses)
          ..where((s) =>
              s.baby.equals(babyId) & s.kind.equals(kind) & s.itemKey.equals(key)))
        .getSingleOrNull();
    if (cur == null ||
        cur.clientUpdatedAt != sentStamp ||
        cur.done != sentDone ||
        cur.statusDate != sentDate) {
      return;
    }
    await (_db.update(_db.healthStatuses)
          ..where((s) =>
              s.baby.equals(babyId) & s.kind.equals(kind) & s.itemKey.equals(key)))
        .write(const HealthStatusesCompanion(
            dirty: Value(false), pushError: Value(null)));
  }

  /// Pull (K-3 tetikleri; R1 tam uygulanır — işaret KALDIRMA da yayılır):
  /// mevcut GET uçlarından üç liste; her sunucu kalemi için yerel satır dirty
  /// ise dokunulmaz, temiz/yoksa sunucu değeri yazılır. Sunucuda olmayan yerel
  /// satır silinmez (katalog × durum; R4 uygulanmaz). Yalnız 200 + List ve boş
  /// olmayan liste uygulanır (K-2 ruhu). Aşı yankısı burada çözülür (O19).
  /// Döner: yerelde bir şey değişti mi (çağıran provider'ları invalidate eder).
  Future<bool> pull(String babyId) async {
    var changed = false;
    // I1 telemetri (TASARIM §5B "ek güvence"): temiz done=true → sunucu
    // pending geçişleri sayılır, Crashlytics non-fatal. Davranış değişmez.
    final clearedDone = <String, int>{};
    final echo = _vaccineEcho[babyId] ??
        const <String, ({bool done, DateTime? date, DateTime? stamp})>{};
    Future<void> apply(String kind, String key, bool done, DateTime? date) async {
      final cur = await (_db.select(_db.healthStatuses)
            ..where((s) =>
                s.baby.equals(babyId) & s.kind.equals(kind) & s.itemKey.equals(key)))
          .getSingleOrNull();
      if (cur != null && cur.dirty) {
        // Yankı: push ettiğimiz aşı sunucuda aynı değerle görünüyorsa onaylandı.
        final e = kind == 'vaccine' ? echo[key] : null;
        if (e != null && e.done == done) {
          await _clearDirtyIfUnchanged(babyId, kind, key, e.stamp, e.done, e.date);
        }
        return; // R1: dirty satır ezilmez
      }
      if (cur != null && cur.done == done && cur.statusDate == (done ? date : null)) {
        return;
      }
      if (cur != null && cur.done && !done) {
        clearedDone[kind] = (clearedDone[kind] ?? 0) + 1;
      }
      await _writeStatus(babyId, kind, key, done, date, dirty: false);
      changed = true;
    }

    Future<List<Map<String, dynamic>>?> fetch(String path) async {
      try {
        final r = await _api.dio.get('/babies/$babyId/$path');
        if (r.statusCode != 200 || r.data is! List) return null;
        final list = (r.data as List)
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
        return list.isEmpty ? null : list;
      } catch (_) {
        return null;
      }
    }

    final vac = await fetch('vaccines');
    // J1(b): sunucu aşı listesi TAMAMEN pending (hiç done yok) iken yerelde
    // temiz done=true aşı satırı varsa sunucu kümesi lazy üretilmiş/hiç
    // yüklenmemiştir → otoriter değildir: aşı kalemleri UYGULANMAZ, hesap
    // yeniden-tohumlama (lapse ile aynı yol) bekler. Gelişim/diş etkilenmez.
    if (vac != null &&
        !vac.any((m) => m['status'] == 'done') &&
        await _hasCleanDoneVaccine(babyId)) {
      final acct = LocalSession.activeAccountId;
      if (acct != null) await LocalSession.markHealthReseedForAccount(acct);
      await SyncTelemetry.report('health_pull_lazy_server_skipped', {
        'baby': babyId,
        'server_items': vac.length,
      });
    } else if (vac != null) {
      // I10: katalogta karşılığı olmayan (başka dilde adlandırılmış) sunucu
      // kalemleri yerelde satır üretmez — ekranda görünmez yetim satırlar
      // birikiyordu. Yankı (echo) kontrolü sunucu listesine bakar, etkilenmez.
      final catKeys = {for (final v in (await _catalog()).vaccines) v.key};
      for (final m in vac) {
        final name = m['vaccine_name'] as String? ?? '';
        if (name.isEmpty || !catKeys.contains(name)) continue;
        await apply('vaccine', name, m['status'] == 'done', _parse(m['done_date']));
      }
      // Yankılanmayan aşılar dirty kalır (dil uyuşmazlığı); bir kez logla.
      final missing =
          echo.keys.where((k) => !vac.any((m) => m['vaccine_name'] == k)).toList();
      if (missing.isNotEmpty) {
        debugPrint(
            '[health-pull] aşı yankısı yok (dil uyuşmazlığı?): ${missing.join(', ')}');
        _unechoedVaccines[babyId] = missing.toSet(); // M9(a)
      } else if (echo.isNotEmpty) {
        _unechoedVaccines.remove(babyId);
      }
    }
    _vaccineEcho.remove(babyId);
    final mil = await fetch('milestones');
    if (mil != null) {
      for (final m in mil) {
        final key = m['key'] as String? ?? '';
        if (key.isEmpty) continue;
        await apply('milestone', key, m['achieved'] == true, _parse(m['achieved_date']));
      }
    }
    final tee = await fetch('teeth');
    if (tee != null) {
      for (final m in tee) {
        final key = m['key'] as String? ?? '';
        if (key.isEmpty) continue;
        await apply('tooth', key, m['erupted'] == true, _parse(m['erupted_date']));
      }
    }
    // Hatırlatıcılar KİŞİSEL (karar 2026-07-07) → buluttan içeri alınmaz.
    if (clearedDone.isNotEmpty) {
      await SyncTelemetry.report('health_pull_cleared_done', {
        'baby': babyId,
        for (final e in clearedDone.entries) e.key: e.value,
      });
    }
    return changed;
  }

  /// Geriye uyumlu ad (ilk import / göç): artık R1 ile tam pull.
  /// J1(b): yerelde temiz (dirty=0) `done=true` aşı satırı var mı?
  Future<bool> _hasCleanDoneVaccine(String babyId) async {
    final row = await (_db.select(_db.healthStatuses)
          ..where((s) =>
              s.baby.equals(babyId) &
              s.kind.equals('vaccine') &
              s.done.equals(true) &
              s.dirty.equals(false))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<void> importFromCloud(String babyId) => pull(babyId);

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
    // İşaret değişti (K4/O21) → aynı yol; delta push + pull syncAll'da.
    onStatusChanged: (_) => ref.read(syncServiceProvider).requestSyncSoon(),
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
