import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
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
  HealthRepository(this._db, this._api, this._catalog, this._cloudEnabled);

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
    await _maybePushReminders(babyId);
    final row = await (_db.select(_db.localReminders)
          ..where((r) => r.localId.equals(id)))
        .getSingle();
    return _toReminder(row);
  }

  Future<void> setReminderEnabled(int id, bool enabled) async {
    final row = await (_db.select(_db.localReminders)
          ..where((r) => r.localId.equals(id)))
        .getSingleOrNull();
    await (_db.update(_db.localReminders)..where((r) => r.localId.equals(id)))
        .write(LocalRemindersCompanion(enabled: Value(enabled)));
    if (row != null) await _maybePushReminders(row.baby);
  }

  Future<void> deleteReminder(int id) async {
    final row = await (_db.select(_db.localReminders)
          ..where((r) => r.localId.equals(id)))
        .getSingleOrNull();
    await (_db.delete(_db.localReminders)..where((r) => r.localId.equals(id))).go();
    if (row != null) await _maybePushReminders(row.baby);
  }

  Future<void> _maybePushReminders(String babyId) async {
    if (!_cloudEnabled(babyId)) return;
    try {
      await pushAll(babyId);
    } catch (_) {}
  }

  // ── Cloud (premium) ──

  /// Tüm sağlık durumunu + hatırlatıcıları buluta iter (son-yazan-kazanır).
  /// Premium push (durum değişimi / migrasyon).
  Future<void> pushAll(String babyId) async {
    final vac = await vaccines(babyId);
    final mil = await milestones(babyId);
    final tee = await teeth(babyId);
    final rem = await reminders(babyId);
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
      'reminders': [
        for (final r in rem)
          {'type': r.type, 'schedule': r.schedule, 'enabled': r.enabled}
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
    // Hatırlatıcılar: yalnız yerel boşsa içeri al (çift kayıt olmasın).
    try {
      final existing = await (_db.select(_db.localReminders)
            ..where((x) => x.baby.equals(babyId)))
          .get();
      if (existing.isEmpty) {
        final r = await _api.dio.get('/babies/$babyId/reminders');
        for (final e in (r.data as List? ?? const [])) {
          final m = e as Map<String, dynamic>;
          await _db.into(_db.localReminders).insert(
                LocalRemindersCompanion.insert(
                  baby: babyId,
                  type: Value(m['type'] as String? ?? 'custom'),
                  scheduleJson: Value(jsonEncode(
                      (m['schedule'] as Map?)?.cast<String, dynamic>() ?? const {})),
                  enabled: Value(m['enabled'] as bool? ?? true),
                  createdAt: Value(DateTime.now()),
                ),
              );
        }
      }
    } catch (_) {}
  }

  Future<void> purgeBaby(String babyId) async {
    await (_db.delete(_db.healthStatuses)..where((s) => s.baby.equals(babyId))).go();
    await (_db.delete(_db.localReminders)..where((r) => r.baby.equals(babyId))).go();
  }
}

final healthRepositoryProvider = Provider<HealthRepository>(
  (ref) => HealthRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    () => ref.read(healthCatalogProvider.future),
    (babyId) => ref.read(babyCloudSyncedProvider(babyId)),
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
