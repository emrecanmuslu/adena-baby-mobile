import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/record.dart';
import 'local/app_database.dart';

/// Kayıtlar için yerel-önce (offline-first) depo.
/// Yazımlar önce drift'e (dirty=true), `/sync` ile sunucuya delta gönderilir.
class RecordRepository {
  final AppDatabase _db;
  final ApiClient _api;

  RecordRepository(this._db, this._api);

  // ---- Yerel okuma (reaktif) ----

  /// Bir bebeğin silinmemiş kayıtları, en yeni önce (tümü) — grafikler için.
  Stream<List<Record>> watch(String babyId) {
    final q = _db.select(_db.records)
      ..where((r) => r.baby.equals(babyId) & r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.desc(r.ts)]);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Son N kayıt (ana sayfa "son kayıtlar" — tümünü çekmez).
  Stream<List<Record>> watchRecent(String babyId, {int limit = 15}) {
    final q = _db.select(_db.records)
      ..where((r) => r.baby.equals(babyId) & r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.desc(r.ts)])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Sayfalı akış (infinite scroll): limit'e kadar, opsiyonel tip filtresi.
  Stream<List<Record>> watchPaged(String babyId,
      {required int limit, RecordType? type}) {
    final q = _db.select(_db.records)
      ..where((r) {
        var e = r.baby.equals(babyId) & r.isDeleted.equals(false);
        if (type != null) e = e & r.type.equals(type.name);
        return e;
      })
      ..orderBy([(r) => OrderingTerm.desc(r.ts)])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// [since]'ten beri kayıtlar (bugünün özeti için).
  Stream<List<Record>> watchSince(String babyId, DateTime since) {
    final q = _db.select(_db.records)
      ..where((r) =>
          r.baby.equals(babyId) &
          r.isDeleted.equals(false) &
          r.ts.isBiggerOrEqualValue(since.toUtc()))
      ..orderBy([(r) => OrderingTerm.desc(r.ts)]);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Belirli bir günün kayıtları (timeline tek-gün görünümü) — en yeni önce.
  Stream<List<Record>> watchDay(String babyId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final q = _db.select(_db.records)
      ..where((r) =>
          r.baby.equals(babyId) &
          r.isDeleted.equals(false) &
          r.ts.isBiggerOrEqualValue(start.toUtc()) &
          r.ts.isSmallerThanValue(end.toUtc()))
      ..orderBy([(r) => OrderingTerm.desc(r.ts)]);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Aktif (bitmemiş) uyku — yalnız en son uyku kaydını kontrol eder (ucuz).
  Stream<Record?> watchOngoingSleep(String babyId) {
    final q = _db.select(_db.records)
      ..where((r) =>
          r.baby.equals(babyId) &
          r.type.equals(RecordType.sleep.name) &
          r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.desc(r.ts)])
      ..limit(1);
    return q.watch().map((rows) {
      if (rows.isEmpty) return null;
      final m = _toModel(rows.first);
      return m.isOngoingSleep ? m : null;
    });
  }

  /// Aktif (bitmemiş) emzirme sayacı — son birkaç beslenme kaydını tarayıp
  /// süren emzirmeyi bulur (araya başka beslenme girse de yakalanır).
  Stream<Record?> watchOngoingBreast(String babyId) {
    final q = _db.select(_db.records)
      ..where((r) =>
          r.baby.equals(babyId) &
          r.type.equals(RecordType.feed.name) &
          r.isDeleted.equals(false))
      ..orderBy([(r) => OrderingTerm.desc(r.ts)])
      ..limit(10);
    return q.watch().map((rows) {
      for (final row in rows) {
        final m = _toModel(row);
        if (m.isOngoingBreast) return m;
      }
      return null;
    });
  }

  /// Kaydı olan tipler (akış filtresi için — tüm kayıtları çekmeden, SQL distinct).
  Future<Set<RecordType>> presentTypes(String babyId) async {
    final q = _db.selectOnly(_db.records)
      ..addColumns([_db.records.type])
      ..where(_db.records.baby.equals(babyId) & _db.records.isDeleted.equals(false))
      ..groupBy([_db.records.type]);
    final rows = await q.get();
    return rows.map((r) => RecordType.fromString(r.read(_db.records.type)!)).toSet();
  }

  // ---- Yerel yazma (offline-first) ----

  Future<void> upsertLocal(Record r) async {
    await _db.into(_db.records).insertOnConflictUpdate(
          RecordsCompanion.insert(
            id: r.id,
            baby: r.baby,
            type: r.type.name,
            ts: r.ts.toUtc(),
            data: Value(jsonEncode(r.data)),
            isDeleted: Value(r.isDeleted),
            clientUpdatedAt: Value(DateTime.now().toUtc()),
            dirty: const Value(true),
            createdBy: Value(r.createdBy),
          ),
        );
  }

  Future<void> softDeleteLocal(String id) async {
    await (_db.update(_db.records)..where((t) => t.id.equals(id))).write(
      RecordsCompanion(
        isDeleted: const Value(true),
        dirty: const Value(true),
        clientUpdatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ---- Sync (delta, son-yazan-kazanır) ----

  /// Bekleyen yerel değişiklikleri gönderir, sunucu değişikliklerini çeker.
  /// Hata atarsa (çevrimdışı vb.) çağıran yutar; yerel veri korunur.
  Future<void> sync(String babyId) async {
    final dirtyRows = await (_db.select(_db.records)
          ..where((r) => r.baby.equals(babyId) & r.dirty.equals(true)))
        .get();
    final cursorRow = await (_db.select(_db.syncCursors)
          ..where((c) => c.baby.equals(babyId)))
        .getSingleOrNull();

    final changes = dirtyRows
        .map((r) => {
              'id': r.id,
              'op': r.isDeleted ? 'delete' : 'upsert',
              'type': r.type,
              'ts': r.ts.toUtc().toIso8601String(),
              'data': jsonDecode(r.data),
              'client_updated_at': r.clientUpdatedAt?.toUtc().toIso8601String(),
            })
        .toList();

    final resp = await _api.dio.post('/sync', data: {
      'baby': babyId,
      'since_cursor': cursorRow?.cursor?.toUtc().toIso8601String(),
      'changes': changes,
    });
    final data = resp.data as Map<String, dynamic>;

    final applied = (data['applied'] as List? ?? []).cast<String>();
    final conflicts = (data['conflicts'] as List? ?? []);
    final serverChanges = (data['server_changes'] as List? ?? []);
    final nextCursor = data['next_cursor'] as String?;

    await _db.transaction(() async {
      // Kabul edilenler: artık temiz.
      for (final id in applied) {
        await (_db.update(_db.records)..where((t) => t.id.equals(id)))
            .write(const RecordsCompanion(dirty: Value(false)));
      }
      // Çakışmalar: sunucu kazandı → server_record ile üzerine yaz.
      for (final c in conflicts) {
        await _applyServerRow(c['server_record'] as Map<String, dynamic>);
      }
      // Sunucudaki değişiklikler: yerelde upsert (temiz).
      for (final sc in serverChanges) {
        await _applyServerRow(sc as Map<String, dynamic>);
      }
      if (nextCursor != null) {
        await _db.into(_db.syncCursors).insertOnConflictUpdate(
              SyncCursorsCompanion(
                baby: Value(babyId),
                cursor: Value(DateTime.parse(nextCursor)),
              ),
            );
      }
    });
  }

  Future<void> _applyServerRow(Map<String, dynamic> srv) async {
    DateTime? parse(dynamic v) =>
        (v is String && v.isNotEmpty) ? DateTime.parse(v) : null;
    await _db.into(_db.records).insertOnConflictUpdate(
          RecordsCompanion.insert(
            id: srv['id'] as String,
            baby: (srv['baby'] ?? srv['baby_id']) as String,
            type: srv['type'] as String,
            ts: DateTime.parse(srv['ts'] as String),
            data: Value(jsonEncode(srv['data'] ?? <String, dynamic>{})),
            isDeleted: Value(srv['is_deleted'] as bool? ?? false),
            clientUpdatedAt: Value(parse(srv['client_updated_at'])),
            serverUpdatedAt: Value(parse(srv['updated_at'])),
            dirty: const Value(false),
            createdBy: Value(srv['created_by'] as String?),
          ),
        );
  }

  Record _toModel(RecordRow row) => Record(
        id: row.id,
        baby: row.baby,
        type: RecordType.fromString(row.type),
        ts: row.ts.toLocal(),
        data: Map<String, dynamic>.from(jsonDecode(row.data) as Map),
        isDeleted: row.isDeleted,
        createdBy: row.createdBy,
      );
}

final recordRepositoryProvider = Provider<RecordRepository>(
  (ref) => RecordRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
  ),
);
