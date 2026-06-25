import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/record.dart';
import 'local/app_database.dart';
import 'sync_diag.dart';

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

  /// Her kayıt tipinin EN SON kaydı (ana sayfa "Son Aktivite" için).
  /// watchRecent'in son-15 penceresine takılmadan seyrek tipleri (banyo,
  /// boy/kilo vb.) de doğru gösterir: tip başına yalnız MAX(ts) satırı.
  Stream<Map<RecordType, Record>> watchLatestByType(String babyId) {
    final q = _db.customSelect(
      'SELECT r.* FROM records r '
      'WHERE r.baby = ?1 AND r.is_deleted = 0 '
      'AND r.ts = (SELECT MAX(r2.ts) FROM records r2 '
      '  WHERE r2.baby = ?1 AND r2.is_deleted = 0 AND r2.type = r.type) '
      'GROUP BY r.type',
      variables: [Variable.withString(babyId)],
      readsFrom: {_db.records},
    );
    return q.watch().map((rows) {
      final out = <RecordType, Record>{};
      for (final row in rows) {
        final rec = _toModel(_db.records.map(row.data));
        out[rec.type] = rec;
      }
      return out;
    });
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

  /// Bir bebeğin TÜM yerel kayıtlarını + sync cursor'ını siler. Aile paylaşımından
  /// çıkarılınca (erişim kaldırılınca) çağrılır — cihazda eski veri kalmasın.
  Future<void> purgeBaby(String babyId) async {
    await (_db.delete(_db.records)..where((r) => r.baby.equals(babyId))).go();
    await (_db.delete(_db.syncCursors)..where((c) => c.baby.equals(babyId))).go();
  }

  // ---- Sync (delta, son-yazan-kazanır) ----

  /// Migrasyonda tam yükleme için bu bebeğin TÜM kayıtlarını dirty işaretle
  /// (silinmiş/tombstone dahil → sync onları da taşır). Bkz. MigrationController.
  Future<void> markAllDirty(String babyId) async {
    await (_db.update(_db.records)..where((r) => r.baby.equals(babyId)))
        .write(const RecordsCompanion(dirty: Value(true)));
  }

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
    // Gönderilen damgayı id başına sakla → applied temizlemesini buna koşulla
    // (uçuş sırasında yeniden düzenlenen kayıt dirty kalmalı, kaybolmamalı).
    final sentStamp = {for (final r in dirtyRows) r.id: r.clientUpdatedAt};

    final sentCursor = cursorRow?.cursor; // ISO string (tam hassasiyet, truncate yok)
    final bid = babyId.length > 6 ? babyId.substring(0, 6) : babyId; // TANI-GEÇİCİ
    try {
      // TANI-GEÇİCİ: try sarmalı yalnız tanı izi içindir; hata yine rethrow edilir.
      final resp = await _api.dio.post('/sync', data: {
        'baby': babyId,
        'since_cursor': sentCursor,
        'changes': changes,
      });
      final data = resp.data as Map<String, dynamic>;

      final applied = (data['applied'] as List? ?? []).cast<String>();
      final conflicts = (data['conflicts'] as List? ?? []);
      final serverChanges = (data['server_changes'] as List? ?? []);
      final nextCursor = data['next_cursor'] as String?;

      // TANI-GEÇİCİ: ne gönderildi / sunucu ne döndü (boş dönerse cross-isolate
      // cursor şüphesi; srv>0 ama Home bayatsa stream körlüğü; ERR ise auth/ağ).
      await SyncDiag.add('sync $bid dirty=${changes.length} '
          'cur=${sentCursor?.substring(5, 19) ?? "-"} '
          'srv=${serverChanges.length} app=${applied.length} '
          'conf=${conflicts.length} next=${nextCursor?.substring(5, 19) ?? "-"}');

      await _db.transaction(() async {
      // Kabul edilenler artık temiz — AMA yalnız GÖNDERDİĞİMİZ sürüm hâlâ duruyorsa.
      // Uçuş sırasında kayıt yeniden düzenlendiyse (clientUpdatedAt değişti) dirty
      // kalsın → yeni düzenleme bir sonraki sync'te gönderilsin (veri kaybı önlenir).
      for (final id in applied) {
        final sent = sentStamp[id];
        await (_db.update(_db.records)
              ..where((t) => sent == null
                  ? t.id.equals(id) & t.clientUpdatedAt.isNull()
                  : t.id.equals(id) & t.clientUpdatedAt.equals(sent)))
            .write(const RecordsCompanion(dirty: Value(false)));
      }
      // Çakışmalar: sunucu OTORİTER kazandı (LWW veya bakıcı-yetki) → her zaman
      // uygula (force), yereldeki dirty düzenleme daha yeni olsa bile geri al.
      for (final c in conflicts) {
        await _applyServerRow(c['server_record'] as Map<String, dynamic>, force: true);
      }
      // Sunucudaki değişiklikler: yerelde upsert (temiz).
      for (final sc in serverChanges) {
        await _applyServerRow(sc as Map<String, dynamic>);
      }
      if (nextCursor != null) {
        await _db.into(_db.syncCursors).insertOnConflictUpdate(
              SyncCursorsCompanion(
                baby: Value(babyId),
                cursor: Value(nextCursor), // ham ISO string sakla → truncate yok
              ),
            );
      }
      });
    } catch (e) {
      // TANI-GEÇİCİ: sync hatasını yakala-kaydet-rethrow (çağıran yine yutar).
      final code = e is DioException ? e.response?.statusCode : null;
      await SyncDiag.add('sync $bid ERR ${e.runtimeType} status=$code');
      rethrow;
    }
  }

  /// Tek-seferlik mevcut-kullanıcı import'u: kayıtları `/sync` POST yerine
  /// salt-okuma `GET /babies/{id}/records` ile sayfalayarak çeker (free kullanıcı
  /// premium-gated /sync'e yazamaz; GET herkese açık). Yerele temiz yazar.
  Future<void> importFromCloud(String babyId) async {
    String? cursor;
    for (var guard = 0; guard < 500; guard++) {
      final qp = <String, dynamic>{'limit': 200};
      if (cursor != null) qp['cursor'] = cursor;
      final resp =
          await _api.dio.get('/babies/$babyId/records', queryParameters: qp);
      final data = resp.data as Map<String, dynamic>;
      final results = (data['results'] as List? ?? []);
      await _db.transaction(() async {
        for (final r in results) {
          await _applyServerRow(r as Map<String, dynamic>);
        }
      });
      cursor = data['next_cursor'] as String?;
      if (cursor == null || results.isEmpty) break;
    }
  }

  /// [force] true (yalnız çakışma yolu): sunucu otoriter kazandı → koşulsuz uygula.
  /// false (server_changes/pull): yerelde gönderilmemiş (dirty) ve sunucununkinden
  /// YENİ düzenleme varsa, sunucu satırını (echo/eski kopya) UYGULAMA → yerel
  /// düzenleme korunur, sonraki sync'te gönderilir. "Uçuşta düzenleme echo ile
  /// eziliyor" + "silinen kayıt diriliyor" fix'i. Backend LWW ile tutarlı.
  Future<void> _applyServerRow(Map<String, dynamic> srv, {bool force = false}) async {
    DateTime? parse(dynamic v) =>
        (v is String && v.isNotEmpty) ? DateTime.parse(v) : null;
    final id = srv['id'] as String;
    final srvCua = parse(srv['client_updated_at']);
    if (!force) {
      final local = await (_db.select(_db.records)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (local != null &&
          local.dirty &&
          local.clientUpdatedAt != null &&
          (srvCua == null || local.clientUpdatedAt!.isAfter(srvCua))) {
        return;
      }
    }
    await _db.into(_db.records).insertOnConflictUpdate(
          RecordsCompanion.insert(
            id: id,
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
