import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/mom_entry.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'sync_gate.dart';

const _uuid = Uuid();

/// Bekleme modu anne takibi (kilo/randevu/not) — **local-first**. Free'de
/// telefonda; premium'da `/babies/{id}/mom-entries` ile aynalanır.
class MomRepository {
  final AppDatabase _db;
  final ApiClient _api;
  final String _localUserId;
  final bool Function() _cloudEnabled;

  MomRepository(this._db, this._api, this._localUserId, this._cloudEnabled);

  Future<List<MomEntry>> list(String babyId) async {
    if (_cloudEnabled()) {
      try {
        await pushDirty(babyId);
        await _pull(babyId);
      } catch (_) {}
    }
    final rows = await (_db.select(_db.momEntries)
          ..where((m) => m.baby.equals(babyId) & m.isDeleted.equals(false))
          ..orderBy([(m) => OrderingTerm.desc(m.date)]))
        .get();
    return rows.map(_toModel).toList();
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
    if (_cloudEnabled()) {
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
    if (_cloudEnabled()) {
      try {
        await pushDirty(babyId);
      } catch (_) {}
    }
  }

  // ---- Cloud senkron (premium) ----

  /// Tek-seferlik mevcut-kullanıcı import'u için (premium gate'inden bağımsız).
  Future<void> importFromCloud(String babyId) => _pull(babyId);

  Future<void> _pull(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/mom-entries');
    final data = resp.data as List<dynamic>;
    await _db.transaction(() async {
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        await _db.into(_db.momEntries).insertOnConflictUpdate(
              MomEntriesCompanion.insert(
                id: m['id'] as String,
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
    });
  }

  Future<void> pushDirty(String babyId) async {
    final dirty = await (_db.select(_db.momEntries)
          ..where((m) => m.baby.equals(babyId) & m.dirty.equals(true)))
        .get();
    for (final r in dirty) {
      try {
        if (r.isDeleted) {
          await _api.dio.delete('/babies/$babyId/mom-entries/${r.id}');
          await (_db.delete(_db.momEntries)..where((m) => m.id.equals(r.id)))
              .go();
          continue;
        }
        await _api.dio.post('/babies/$babyId/mom-entries',
            data: _toModel(r).toCreateJson());
        await (_db.update(_db.momEntries)..where((m) => m.id.equals(r.id)))
            .write(const MomEntriesCompanion(dirty: Value(false)));
      } catch (_) {}
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
    () => ref.read(cloudSyncEnabledProvider),
  ),
);

/// Aktif bebeğin anne takibi kayıtları (tarihe göre yeni→eski).
final momEntriesProvider = FutureProvider.family<List<MomEntry>, String>(
  (ref, babyId) => ref.watch(momRepositoryProvider).list(babyId),
);
