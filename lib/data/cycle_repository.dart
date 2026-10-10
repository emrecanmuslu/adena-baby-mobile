import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../features/auth/auth_controller.dart';
import '../models/cycle.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'sync_gate.dart';
import 'sync_merge.dart';

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
      expectedCycleLength: row.expectedCycleLength,
      periodLength: row.periodLength,
      lutealPhaseLength: row.lutealPhaseLength,
      smartPrediction: row.smartPrediction,
      weekStartsSunday: row.weekStartsSunday,
      lifecycleMode: CycleLifecycleMode.fromString(row.lifecycleMode),
      ttcStartedAt: row.ttcStartedAt,
      predictionsHidden: row.predictionsHidden,
      lastLossDate: row.lastLossDate,
      learningWindow: row.learningWindow,
    );
  }

  Future<CycleSettings> patchSettings(Map<String, dynamic> fields) async {
    final current = await getSettings();
    // Durum-makinesi: postpartum/loss'ta İLK ADET işaretlenince (çapa null →
    // dolu) döngü takibine otomatik dönülür ("ilk gerçek adet = yeni Gün 1").
    // Merkezde (patchSettings) yapılır ki hem saveEntry kancası hem adet-düzenleme
    // takvimi hem hızlı giriş aynı geçişi tetiklesin.
    final setsAnchor = fields['first_period_date'] != null;
    final wasPaused = current.lifecycleMode == CycleLifecycleMode.postpartum ||
        current.lifecycleMode == CycleLifecycleMode.loss;
    if (setsAnchor &&
        current.firstPeriodDate == null &&
        wasPaused &&
        !fields.containsKey('lifecycle_mode')) {
      fields = {
        ...fields,
        'lifecycle_mode': CycleLifecycleMode.tracking.name,
        'predictions_hidden': false,
      };
    }
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
            expectedCycleLength: Value(s.expectedCycleLength),
            periodLength: Value(s.periodLength),
            lutealPhaseLength: Value(s.lutealPhaseLength),
            smartPrediction: Value(s.smartPrediction),
            weekStartsSunday: Value(s.weekStartsSunday),
            lifecycleMode: Value(s.lifecycleMode.name),
            ttcStartedAt: Value(s.ttcStartedAt),
            predictionsHidden: Value(s.predictionsHidden),
            lastLossDate: Value(s.lastLossDate),
            learningWindow: Value(s.learningWindow),
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
    // My Calendar pariteti: ilk gerçek adet loglandığında döngü takibi OTOMATİK
    // başlar. Mod `firstPeriodDate`'e bağlı (entry'e değil) → boşsa bu kaydın
    // tarihine set et: bekleme/loşia → aktif geçişi (yoksa log girilse de bekleme).
    // Yalnız sıfırlama olayından (doğum/kayıp) SONRAKİ günler "ilk adet döndü"
    // sayılır: lohusa/kayıp kullanıcı geçmiş bir adetini sonradan işlerse
    // (backfill) bu dönüş değildir — çapa yanlış Gün 1'e kurulur ve istenmeden
    // aktif takibe geçilirdi. Olay gününün kendisi de hariç (o günkü kanama
    // doğum/kayıp kanamasıdır, adet değil).
    if (entry.isPeriod) {
      final s = await getSettings();
      if (_afterLatestReset(entry.date, s)) {
        if (s.firstPeriodDate == null) {
          await patchSettings({'first_period_date': _isoDate(entry.date)});
        } else if (s.predictionsHidden) {
          // Onarım: çapa dolu ama tahminler gizli kalmış (ör. eski sürümden gelen
          // tutarsız durum). Kullanıcı adet logluyorsa takibe dönmek istiyor.
          await patchSettings({
            'predictions_hidden': false,
            if (s.lifecycleMode == CycleLifecycleMode.postpartum ||
                s.lifecycleMode == CycleLifecycleMode.loss)
              'lifecycle_mode': CycleLifecycleMode.tracking.name,
          });
        }
      }
    }
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

  /// Kalıcı reddedilen push'lar: id → açıklama (bellek-içi; kolon v15'te, K-1).
  final Map<String, String> pushErrors = {};

  static DateTime? _parseTs(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

  /// Pull (TASARIM-SENKRON.md R1/R2/R4/R5, O7): dirty yerel satır ezilmez,
  /// tombstone diriltilmez, sunucunun TAM listesinde olmayan temiz satır K-2
  /// korumalarıyla silinir; `updated_at` damga karşılaştırması + `serverUpdatedAt`.
  Future<void> _pullEntries() async {
    final acct = _acct;
    if (acct == null) return;
    final resp = await _api.dio.get('/cycle/entries');
    // Yanıt TAMAMEN parse edilmeden hiçbir şey uygulanmaz (R4 güvencesi).
    final rows = (resp.data as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final parsed = [for (final m in rows) (m, CycleEntry.fromJson(m))];
    final serverIds = {for (final (_, ce) in parsed) ce.id};
    final local = await (_db.select(_db.cycleEntries)
          ..where((e) => e.accountId.equals(acct)))
        .get();
    final localById = {for (final r in local) r.id: r};
    final stale = staleLocalIds(
      local: [
        for (final r in local)
          LocalRowState(r.id, dirty: r.dirty, deleted: r.isDeleted)
      ],
      serverIds: serverIds,
      statusCode: resp.statusCode ?? 0,
      parsedOk: true,
    );
    if (stale.skipped) {
      debugPrint('[cycle-pull] silme atlandı: ${stale.skippedReason}');
    }
    await _db.transaction(() async {
      for (final (m, ce) in parsed) {
        final l = localById[ce.id];
        final decision = decideServerRow(
          localExists: l != null,
          localDirty: l?.dirty ?? false,
          localDeleted: l?.isDeleted ?? false,
          localStamp: l?.clientUpdatedAt,
          serverStamp: _parseTs(m['updated_at']),
        );
        if (decision != MergeDecision.apply) continue;
        await _db.into(_db.cycleEntries).insertOnConflictUpdate(
              CycleEntriesCompanion.insert(
                id: ce.id,
                accountId: Value(acct),
                date: _dayOnly(ce.date),
                flow: Value(ce.flow?.name),
                lochiaColor: Value(ce.lochiaColor?.apiValue),
                symptoms: Value(jsonEncode(ce.symptoms)),
                mood: Value(ce.mood),
                note: Value(ce.note),
                serverUpdatedAt: Value(_parseTs(m['updated_at'])),
                dirty: const Value(false),
              ),
            );
      }
      // R4: sunucuda artık olmayan temiz satırlar (başka cihazda silindi; sunucu
      // hard delete). Çapa (`firstPeriodDate`) settings'te durduğundan motor
      // etkilenmez (bkz. computeStatus: starts = {anchor, …}).
      for (final id in stale.ids) {
        await (_db.delete(_db.cycleEntries)..where((e) => e.id.equals(id))).go();
      }
    });
  }

  /// Silmeler tek tek DELETE (404 = zaten yok → başarı); oluştur/güncellemeler
  /// TEK toplu istek (`/cycle/entries/bulk`). Yalnız `saved` temizlenir; `failed[]`
  /// ve kalıcı (4xx) redler dirty kalır + `pushErrors` (R3/R5).
  Future<void> _pushDirtyEntries() async {
    final acct = _acct;
    if (acct == null) return;
    final dirty = await (_db.select(_db.cycleEntries)
          ..where((e) => e.dirty.equals(true) & e.accountId.equals(acct)))
        .get();
    if (dirty.isEmpty) return;

    final upserts = <CycleEntryRow>[];
    for (final r in dirty) {
      if (!r.isDeleted) {
        upserts.add(r);
        continue;
      }
      try {
        await _api.dio.delete('/cycle/entries/${r.id}');
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) {
          _noteFailure(r.id, e);
          continue; // tombstone dirty kalır, sonraki tur yeniden dener
        }
      } catch (_) {
        continue;
      }
      await (_db.delete(_db.cycleEntries)..where((e) => e.id.equals(r.id))).go();
      pushErrors.remove(r.id);
    }
    if (upserts.isEmpty) return;

    try {
      final resp = await _api.dio.post(
        '/cycle/entries/bulk',
        data: [for (final r in upserts) _toEntry(r).toJson()],
      );
      final body = resp.data as Map;
      final saved =
          ((body['saved'] as List?) ?? const []).map((e) => e.toString()).toSet();
      final failed = <String, String>{
        for (final f in (body['failed'] as List?) ?? const [])
          if (f is Map && f['id'] != null)
            f['id'].toString(): (f['error'] ?? 'failed').toString(),
      };
      await _db.transaction(() async {
        for (final r in upserts) {
          if (saved.contains(r.id)) {
            await (_db.update(_db.cycleEntries)..where((e) => e.id.equals(r.id)))
                .write(const CycleEntriesCompanion(dirty: Value(false)));
            pushErrors.remove(r.id);
          } else if (failed.containsKey(r.id)) {
            pushErrors[r.id] = failed[r.id]!; // sunucu bu öğeyi reddetti (kalıcı)
          }
        }
      });
    } on DioException catch (e) {
      for (final r in upserts) {
        _noteFailure(r.id, e);
      }
    } catch (_) {
      // Beklenmeyen — dirty kalır, sonraki tur.
    }
  }

  void _noteFailure(String id, DioException e) {
    if (classifyDioError(e) == PushFailure.permanent) {
      final code = e.response?.statusCode;
      pushErrors[id] = 'HTTP $code';
      debugPrint('[cycle-push] kalıcı red $id: HTTP $code ${e.response?.data}');
    }
  }

  /// Verilen gün, son sıfırlama olayının (doğum/kayıp) gününden SONRA mı?
  /// Olay yoksa her gün geçerlidir. Olay günü dahil öncesi geçersizdir —
  /// bkz. saveEntry'deki çapa kancası (backfill koruması).
  static bool _afterLatestReset(DateTime day, CycleSettings s) {
    final resets = [
      if (s.birthDate != null) _dayOnly(s.birthDate!),
      if (s.lastLossDate != null) _dayOnly(s.lastLossDate!),
    ];
    if (resets.isEmpty) return true;
    final latest = resets.reduce((a, b) => b.isAfter(a) ? b : a);
    return _dayOnly(day).isAfter(latest);
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
final cycleSettingsProvider = FutureProvider<CycleSettings>((ref) async {
  // Açılış yarışı koruması: oturum çözülmeden (auth loading) activeAccountId
  // null olur ve boş ayarlar "kurulmamış" sanılıp sihirbaz açılırdı. Auth
  // sonuçlanana dek bekle → shell bu sürede spinner gösterir.
  await ref.watch(authControllerProvider.future);
  ref.watch(activeAccountIdProvider);
  return ref.watch(cycleRepositoryProvider).getSettings();
});

/// Tüm adet kayıtları (yeni→eski).
final cycleEntriesProvider = FutureProvider<List<CycleEntry>>((ref) async {
  // bkz. cycleSettingsProvider — aynı açılış yarışı koruması.
  await ref.watch(authControllerProvider.future);
  ref.watch(activeAccountIdProvider);
  return ref.watch(cycleRepositoryProvider).listEntries();
});
