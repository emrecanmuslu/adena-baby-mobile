import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/mom_entry.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'sync_gate.dart';
import 'sync_merge.dart';

const _uuid = Uuid();

/// Bekleme modu anne takibi (kilo/randevu/not) — **local-first**. Free'de
/// telefonda; premium'da `/babies/{id}/mom-entries` ile aynalanır.
///
/// Senkron kuralları (TASARIM-SENKRON.md §2, O5): R1/R2/R4/R5/R8 — anı ile aynı.
/// Sunucu `updated_at` döndürmediğinden damga karşılaştırması yok: dirty yerel
/// kazanır, temiz yerel sunucuyu alır.
class MomRepository {
  final AppDatabase _db;
  final ApiClient _api;
  final String _localUserId;
  /// Bu BEBEK bulut senkronuna tabi mi? Per-baby (Seçenek 2): paylaşılan bebek
  /// sahibin premium'uyla senkronlanır, kendi bebeğim kendi premium'umla.
  final bool Function(String babyId) _cloudEnabled;

  MomRepository(this._db, this._api, this._localUserId, this._cloudEnabled);

  /// Kalıcı reddedilen push'lar `pushError` kolonunda (K-1).
  Future<bool> _isCaregiver(String babyId) async {
    final b = await (_db.select(_db.babies)..where((x) => x.id.equals(babyId)))
        .getSingleOrNull();
    return b?.myRole == 'caregiver';
  }

  Future<void> _setPushError(String id, String? err) =>
      (_db.update(_db.momEntries)..where((m) => m.id.equals(id)))
          .write(MomEntriesCompanion(pushError: Value(err)));

  /// K-1 "geri al": sunucu listesinde satır varsa uygulanır; yoksa `notOnServer`.
  Future<RevertResult> revertToServer(String babyId, String id) async {
    try {
      final resp = await _api.dio.get('/babies/$babyId/mom-entries');
      if (resp.statusCode != 200 || resp.data is! List) return RevertResult.failed;
      for (final e in resp.data as List) {
        if (e is! Map || e['id'] != id) continue;
        final m = e.cast<String, dynamic>();
        await _db.into(_db.momEntries).insertOnConflictUpdate(
              MomEntriesCompanion.insert(
                id: id,
                baby: babyId,
                kind: (m['kind'] as String?) ?? 'note',
                date: DateTime.parse(m['date'] as String).toLocal(),
                weightKg: Value(m['weight_kg'] == null
                    ? null
                    : double.tryParse(m['weight_kg'].toString())),
                title: Value(m['title'] as String?),
                note: Value(m['note'] as String?),
                createdBy: Value(m['created_by'] as String?),
                isDeleted: const Value(false),
                dirty: const Value(false),
                pushError: const Value(null),
              ),
            );
        return RevertResult.applied;
      }
      return RevertResult.notOnServer;
    } catch (_) {
      return RevertResult.failed;
    }
  }

  Future<void> discardLocal(String id) =>
      (_db.delete(_db.momEntries)..where((m) => m.id.equals(id))).go();

  // ---- Yerel okuma ----

  /// Reaktif liste (yeni→eski, tombstone gizli); ağ beklemez (R8).
  Stream<List<MomEntry>> watch(String babyId) {
    final q = _db.select(_db.momEntries)
      ..where((m) => m.baby.equals(babyId) & m.isDeleted.equals(false))
      ..orderBy([(m) => OrderingTerm.desc(m.date)]);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Tek seferlik yerel okuma (dışa aktarma vb.). Ağa ÇIKMAZ.
  Future<List<MomEntry>> list(String babyId) async {
    final rows = await (_db.select(_db.momEntries)
          ..where((m) => m.baby.equals(babyId) & m.isDeleted.equals(false))
          ..orderBy([(m) => OrderingTerm.desc(m.date)]))
        .get();
    return rows.map(_toModel).toList();
  }

  /// Bulut uygunsa arka planda push + pull; her hata yutulur.
  Future<void> syncIfCloud(String babyId) async {
    if (!_cloudEnabled(babyId)) return;
    try {
      await pushDirty(babyId);
      await _pull(babyId);
    } catch (_) {}
  }

  Future<MomEntry> add(
    String babyId, {
    required MomKind kind,
    required DateTime date,
    double? weightKg,
    String? title,
    String? note,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.momEntries).insertOnConflictUpdate(
          MomEntriesCompanion.insert(
            id: id,
            baby: babyId,
            kind: kind.name,
            date: date,
            weightKg: Value(weightKg),
            title: Value(title),
            note: Value(note),
            createdBy: Value(_localUserId),
            clientUpdatedAt: Value(DateTime.now().toUtc()),
            dirty: const Value(true),
          ),
        );
    if (_cloudEnabled(babyId)) {
      try {
        await pushDirty(babyId);
      } catch (_) {}
    }
    return (await _byId(id))!;
  }

  Future<void> delete(String babyId, String id) async {
    await (_db.update(_db.momEntries)..where((m) => m.id.equals(id))).write(
      MomEntriesCompanion(
        isDeleted: const Value(true),
        dirty: const Value(true),
        clientUpdatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    if (_cloudEnabled(babyId)) {
      try {
        await pushDirty(babyId);
      } catch (_) {}
    }
  }

  // ---- Cloud senkron (premium) ----

  /// Tek-seferlik mevcut-kullanıcı import'u için (premium gate'inden bağımsız).
  Future<void> importFromCloud(String babyId) => _pull(babyId);

  /// Erişim kaldırılınca (paylaşımdan düşme) bu bebeğin tüm anne kayıtlarını sil.
  Future<void> purgeBaby(String babyId) async {
    await (_db.delete(_db.momEntries)..where((m) => m.baby.equals(babyId))).go();
  }

  Future<void> _pull(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/mom-entries');
    // Yanıt TAMAMEN parse edilmeden hiçbir şey uygulanmaz (R4 güvencesi).
    final rows = (resp.data as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final serverIds = {for (final m in rows) m['id'] as String};
    final local = await (_db.select(_db.momEntries)
          ..where((m) => m.baby.equals(babyId)))
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
      debugPrint('[mom-pull] silme atlandı: ${stale.skippedReason}');
    }
    await _db.transaction(() async {
      for (final m in rows) {
        final id = m['id'] as String;
        final l = localById[id];
        // Sunucu damgası yok → dirty yerel kazanır, temiz yerel sunucuyu alır.
        final decision = decideServerRow(
          localExists: l != null,
          localDirty: l?.dirty ?? false,
          localDeleted: l?.isDeleted ?? false,
        );
        if (decision != MergeDecision.apply) continue;
        await _db.into(_db.momEntries).insertOnConflictUpdate(
              MomEntriesCompanion.insert(
                id: id,
                baby: babyId,
                kind: (m['kind'] as String?) ?? 'note',
                date: DateTime.parse(m['date'] as String).toLocal(),
                weightKg: Value(m['weight_kg'] == null
                    ? null
                    : double.tryParse(m['weight_kg'].toString())),
                title: Value(m['title'] as String?),
                note: Value(m['note'] as String?),
                createdBy: Value(m['created_by'] as String?),
                dirty: const Value(false),
              ),
            );
      }
      // R4: sunucuda artık olmayan temiz satırlar (başka üye sildi; sunucu hard delete).
      for (final id in stale.ids) {
        await (_db.delete(_db.momEntries)..where((m) => m.id.equals(id))).go();
      }
    });
  }

  /// Migrasyonda tam yükleme için bu bebeğin TÜM anne kayıtlarını dirty işaretle.
  Future<void> markAllDirty(String babyId) async {
    await (_db.update(_db.momEntries)..where((m) => m.baby.equals(babyId)))
        .write(const MomEntriesCompanion(dirty: Value(true)));
  }

  /// Silmeler tek tek DELETE (404 = zaten yok → başarı); oluştur/güncellemeler
  /// TEK toplu istek (`/mom-entries/bulk`). `saved` id'leri temizlenir; `failed`
  /// listesindekiler ve kalıcı (4xx) redler `pushErrors`'a yazılır, dirty kalır.
  Future<void> pushDirty(String babyId) async {
    final dirty = await (_db.select(_db.momEntries)
          ..where((m) => m.baby.equals(babyId) & m.dirty.equals(true)))
        .get();
    if (dirty.isEmpty) return;

    final upserts = <MomEntryRow>[];
    for (final r in dirty) {
      if (!r.isDeleted) {
        upserts.add(r);
        continue;
      }
      try {
        await _api.dio.delete('/babies/$babyId/mom-entries/${r.id}');
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) {
          await _noteFailure(babyId, r.id, e);
          continue;
        }
      } catch (_) {
        continue;
      }
      await (_db.delete(_db.momEntries)..where((m) => m.id.equals(r.id))).go();
    }
    if (upserts.isEmpty) return;

    try {
      final resp = await _api.dio.post(
        '/babies/$babyId/mom-entries/bulk',
        data: [for (final r in upserts) _toModel(r).toCreateJson()],
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
            // R5 / I3: bulk uçuştayken silindiyse/değiştiyse dirty KALIR
            // (tombstone bir sonraki turda DELETE olarak gider).
            final cur = await (_db.select(_db.momEntries)
                  ..where((m) => m.id.equals(r.id)))
                .getSingleOrNull();
            final unchanged = cur != null &&
                cur.clientUpdatedAt == r.clientUpdatedAt &&
                cur.isDeleted == r.isDeleted &&
                cur.kind == r.kind &&
                cur.date == r.date &&
                cur.weightKg == r.weightKg &&
                cur.title == r.title &&
                cur.note == r.note;
            await (_db.update(_db.momEntries)..where((m) => m.id.equals(r.id)))
                .write(MomEntriesCompanion(
                    dirty: unchanged ? const Value(false) : const Value.absent(),
                    pushError: const Value(null)));
          } else if (failed.containsKey(r.id)) {
            // sunucu bu öğeyi reddetti (kalıcı)
            await _setPushError(r.id, _short(failed[r.id]!));
          }
        }
      });
    } on DioException catch (e) {
      for (final r in upserts) {
        await _noteFailure(babyId, r.id, e);
      }
    } catch (_) {
      // Beklenmeyen — dirty kalır, sonraki tur.
    }
  }

  static String _short(String s) => s.length > 120 ? s.substring(0, 120) : s;

  /// R3 + K-1: kalıcı 4xx → `pushError`; 403 + caregiver → `'role'`.
  Future<void> _noteFailure(String babyId, String id, DioException e) async {
    final code = e.response?.statusCode;
    if (code == 403 && await _isCaregiver(babyId)) {
      await _setPushError(id, 'role');
      return;
    }
    if (classifyDioError(e) == PushFailure.permanent) {
      await _setPushError(id, 'HTTP $code');
      debugPrint('[mom-push] kalıcı red $id: HTTP $code ${e.response?.data}');
    }
  }

  Future<MomEntry?> _byId(String id) async {
    final r = await (_db.select(_db.momEntries)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    return r == null ? null : _toModel(r);
  }

  MomEntry _toModel(MomEntryRow r) => MomEntry(
        id: r.id,
        kind: MomKind.fromString(r.kind),
        date: r.date.toLocal(),
        weightKg: r.weightKg,
        title: (r.title?.isEmpty ?? true) ? null : r.title,
        note: (r.note?.isEmpty ?? true) ? null : r.note,
      );
}

final momRepositoryProvider = Provider<MomRepository>(
  (ref) => MomRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(localUserIdProvider),
    (babyId) => ref.read(babyCloudSyncedProvider(babyId)),
  ),
);

/// Aktif bebeğin anne takibi kayıtları (yeni→eski) — yerel drift akışı (R8);
/// bulut senkronu arka planda tetiklenir, ekran ağı beklemez.
final momEntriesProvider = StreamProvider.family<List<MomEntry>, String>(
  (ref, babyId) {
    final repo = ref.watch(momRepositoryProvider);
    unawaited(repo.syncIfCloud(babyId));
    return repo.watch(babyId);
  },
);
