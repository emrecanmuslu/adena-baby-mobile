import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../features/auth/auth_controller.dart';
import '../models/cycle.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'sync_gate.dart';

const _uuid = Uuid();

/// Adet Takvimi — **local-first**, kullanıcıya özel (bebek paylaşımından
/// bağımsız). Free'de telefonda; premium'da `/cycle/...` ile aynalanır.
class CycleRepository {
  final AppDatabase _db;
  final ApiClient _api;
  final bool Function() _cloudEnabled;

  CycleRepository(this._db, this._api, this._cloudEnabled);

  /// Adet modülü kullanıcıya özel → yerel satırlar aktif hesaba göre kapsamlanır.
  /// Settings tekil satırının id'si = hesap id'si.
  String? get _acct => LocalSession.activeAccountId;

  // ---- Ayarlar ----

  Future<CycleSettings> getSettings() async {
    final acct = _acct;
    if (acct == null) return const CycleSettings();
    if (_cloudEnabled()) {
      try {
        final resp = await _api.dio.get('/cycle/settings');
        await _writeSettings(
            CycleSettings.fromJson(resp.data as Map<String, dynamic>),
            dirty: false);
      } catch (_) {}
    }
    final row = await (_db.select(_db.cycleSettingsTable)
          ..where((s) => s.id.equals(acct)))
        .getSingleOrNull();
    return _rowToSettings(row);
  }

  CycleSettings _rowToSettings(CycleSettingsRow? row) {
    if (row == null) return const CycleSettings();
    return CycleSettings(
      babyId: row.baby,
      birthDate: row.birthDate,
      breastfeeding: Breastfeeding.fromString(row.breastfeeding),
      firstPeriodDate: row.firstPeriodDate,
      reminders: () {
        try {
          return Map<String, dynamic>.from(jsonDecode(row.reminders) as Map);
        } catch (_) {
          return <String, dynamic>{};
        }
      }(),
      showFertilityWarning: row.showFertilityWarning,
      enabled: row.enabled,
    );
  }

  Future<CycleSettings> patchSettings(Map<String, dynamic> fields) async {
    final current = await getSettings();
    final merged = {...current.toPatchJson(), ...fields};
    final next = CycleSettings.fromJson(merged);
    await _writeSettings(next, dirty: true);
    if (_cloudEnabled()) {
      try {
        await _api.dio.patch('/cycle/settings', data: next.toPatchJson());
        await _markSettingsClean();
      } catch (_) {}
    }
    return next;
  }

  Future<void> _writeSettings(CycleSettings s, {required bool dirty}) async {
    final acct = _acct;
    if (acct == null) return;
    await _db.into(_db.cycleSettingsTable).insertOnConflictUpdate(
          CycleSettingsTableCompanion(
            id: Value(acct),
            baby: Value(s.babyId),
            birthDate: Value(s.birthDate),
            breastfeeding: Value(s.breastfeeding?.name),
            firstPeriodDate: Value(s.firstPeriodDate),
            reminders: Value(jsonEncode(s.reminders)),
            showFertilityWarning: Value(s.showFertilityWarning),
            enabled: Value(s.enabled),
            clientUpdatedAt: Value(DateTime.now().toUtc()),
            dirty: Value(dirty),
          ),
        );
  }

  Future<void> _markSettingsClean() async {
    final acct = _acct;
    if (acct == null) return;
    await (_db.update(_db.cycleSettingsTable)..where((s) => s.id.equals(acct)))
        .write(const CycleSettingsTableCompanion(dirty: Value(false)));
  }

  // ---- Girdiler ----

  Future<List<CycleEntry>> listEntries({DateTime? from, DateTime? to}) async {
    final acct = _acct;
    if (acct == null) return const [];
    if (_cloudEnabled()) {
      try {
        await _pushDirtyEntries();
        await _pullEntries();
      } catch (_) {}
    }
    final q = _db.select(_db.cycleEntries)
      ..where((e) => e.isDeleted.equals(false) & e.accountId.equals(acct));
    if (from != null) {
      q.where((e) => e.date.isBiggerOrEqualValue(_dayOnly(from)));
    }
    if (to != null) {
      q.where((e) => e.date.isSmallerOrEqualValue(_dayOnly(to)));
    }
    q.orderBy([(e) => OrderingTerm.desc(e.date)]);
    final rows = await q.get();
    return rows.map(_toEntry).toList();
  }

  /// Gün başına tek kayıt — aynı tarih varsa onun id'siyle günceller.
  Future<CycleEntry> saveEntry(CycleEntry entry) async {
    final acct = _acct;
    var id = entry.id;
    if (id.isEmpty) {
      final existing = await (_db.select(_db.cycleEntries)
            ..where((e) =>
                e.date.equals(_dayOnly(entry.date)) &
                e.isDeleted.equals(false) &
                e.accountId.equals(acct ?? '')))
          .getSingleOrNull();
      id = existing?.id ?? _uuid.v4();
    }
    await _db.into(_db.cycleEntries).insertOnConflictUpdate(
          CycleEntriesCompanion.insert(
            id: id,
            accountId: Value(acct),
            date: _dayOnly(entry.date),
            flow: Value(entry.flow?.name),
            lochiaColor: Value(entry.lochiaColor?.apiValue),
            symptoms: Value(jsonEncode(entry.symptoms)),
            mood: Value(entry.mood),
            note: Value(entry.note),
            isDeleted: const Value(false),
            clientUpdatedAt: Value(DateTime.now().toUtc()),
            dirty: const Value(true),
          ),
        );
    if (_cloudEnabled()) {
      try {
        await _pushDirtyEntries();
      } catch (_) {}
    }
    final r = await (_db.select(_db.cycleEntries)..where((e) => e.id.equals(id)))
        .getSingle();
    return _toEntry(r);
  }

  Future<void> deleteEntry(String id) async {
    await (_db.update(_db.cycleEntries)..where((e) => e.id.equals(id))).write(
      CycleEntriesCompanion(
        isDeleted: const Value(true),
        dirty: const Value(true),
        clientUpdatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    if (_cloudEnabled()) {
      try {
        await _pushDirtyEntries();
      } catch (_) {}
    }
  }

  // ---- Cloud senkron (premium) ----

  /// Tek-seferlik mevcut-kullanıcı import'u: sunucudaki ayar + girdileri yerele
  /// indirir (premium gate'inden bağımsız).
  Future<void> importFromCloud() async {
    try {
      final resp = await _api.dio.get('/cycle/settings');
      await _writeSettings(
          CycleSettings.fromJson(resp.data as Map<String, dynamic>),
          dirty: false);
    } catch (_) {}
    await _pullEntries();
  }

  /// Migrasyonda tam yükleme için aktif hesabın TÜM adet kayıt + ayarını dirty
  /// işaretle (grace sonrası cloud silinmişse geri yüklensin).
  Future<void> markAllDirty() async {
    final acct = _acct;
    if (acct == null) return;
    await (_db.update(_db.cycleEntries)..where((e) => e.accountId.equals(acct)))
        .write(const CycleEntriesCompanion(dirty: Value(true)));
    await (_db.update(_db.cycleSettingsTable)..where((s) => s.id.equals(acct)))
        .write(const CycleSettingsTableCompanion(dirty: Value(true)));
  }

  /// free→premium migrasyonu: yerel ayar + girdileri sunucuya yollar.
  Future<void> migrateToCloud() async {
    final acct = _acct;
    if (acct == null) return;
    final row = await (_db.select(_db.cycleSettingsTable)
          ..where((s) => s.id.equals(acct)))
        .getSingleOrNull();
    if (row != null && row.dirty) {
      try {
        await _api.dio.patch('/cycle/settings',
            data: _rowToSettings(row).toPatchJson());
        await _markSettingsClean();
      } catch (_) {}
    }
    await _pushDirtyEntries();
  }

  Future<void> _pullEntries() async {
    final resp = await _api.dio.get('/cycle/entries');
    final data = resp.data as List<dynamic>;
    await _db.transaction(() async {
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        final ce = CycleEntry.fromJson(m);
        await _db.into(_db.cycleEntries).insertOnConflictUpdate(
              CycleEntriesCompanion.insert(
                id: ce.id,
                accountId: Value(_acct),
                date: _dayOnly(ce.date),
                flow: Value(ce.flow?.name),
                lochiaColor: Value(ce.lochiaColor?.apiValue),
                symptoms: Value(jsonEncode(ce.symptoms)),
                mood: Value(ce.mood),
                note: Value(ce.note),
                dirty: const Value(false),
              ),
            );
      }
    });
  }

  Future<void> _pushDirtyEntries() async {
    final acct = _acct;
    if (acct == null) return;
    final dirty = await (_db.select(_db.cycleEntries)
          ..where((e) => e.dirty.equals(true) & e.accountId.equals(acct)))
        .get();
    if (dirty.isEmpty) return;

    // Silmeler (nadir) tek tek DELETE; oluştur/güncellemeler TEK toplu istek
    // (/cycle/entries/bulk) — migrasyonda N kayıt için N istek yerine 1 istek.
    final upserts = <CycleEntryRow>[];
    for (final r in dirty) {
      if (r.isDeleted) {
        try {
          await _api.dio.delete('/cycle/entries/${r.id}');
          await (_db.delete(_db.cycleEntries)..where((e) => e.id.equals(r.id)))
              .go();
        } catch (_) {}
      } else {
        upserts.add(r);
      }
    }
    if (upserts.isEmpty) return;

    try {
      final resp = await _api.dio.post(
        '/cycle/entries/bulk',
        data: [for (final r in upserts) _toEntry(r).toJson()],
      );
      // Sunucunun onayladığı id'leri temizle (kısmî başarıda kalanlar dirty kalır).
      final saved = (((resp.data as Map)['saved'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet();
      await _db.transaction(() async {
        for (final r in upserts) {
          if (saved.contains(r.id)) {
            await (_db.update(_db.cycleEntries)..where((e) => e.id.equals(r.id)))
                .write(const CycleEntriesCompanion(dirty: Value(false)));
          }
        }
      });
    } catch (_) {}
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  CycleEntry _toEntry(CycleEntryRow r) => CycleEntry(
        id: r.id,
        date: r.date,
        flow: FlowLevel.fromString(r.flow),
        lochiaColor: LochiaColor.fromString(r.lochiaColor),
        symptoms: () {
          try {
            return (jsonDecode(r.symptoms) as List)
                .map((e) => e.toString())
                .toList();
          } catch (_) {
            return <String>[];
          }
        }(),
        mood: r.mood,
        note: (r.note?.isEmpty ?? true) ? null : r.note,
      );
}

final cycleRepositoryProvider = Provider<CycleRepository>(
  (ref) => CycleRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    () => ref.read(cloudSyncEnabledProvider),
  ),
);

/// Kullanıcının adet modülü ayarı (yerel; premium'da sunucuyla eşlenir).
/// Hesap değişince yeniden yüklenir (aktif hesaba göre kapsamlı).
final cycleSettingsProvider = FutureProvider<CycleSettings>((ref) {
  ref.watch(activeAccountIdProvider);
  return ref.watch(cycleRepositoryProvider).getSettings();
});

/// Tüm adet kayıtları (yeni→eski).
final cycleEntriesProvider = FutureProvider<List<CycleEntry>>((ref) {
  ref.watch(activeAccountIdProvider);
  return ref.watch(cycleRepositoryProvider).listEntries();
});
