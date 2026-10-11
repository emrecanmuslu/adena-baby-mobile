import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/memory.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'sync_gate.dart';
import 'sync_merge.dart';

const _uuid = Uuid();

/// Anılar / foto günlüğü — **local-first**. Free'de anı + foto telefonda
/// (`localPhotoPath`); premium'da `/babies/{id}/memories` ile aynalanır ve foto
/// yüklenir (`photo` sunucu URL'i olur). Foto, image_picker'ın geçici yolundan
/// kalıcı uygulama dizinine kopyalanır (geçici dosya silinse de kaybolmasın).
///
/// Senkron kuralları (TASARIM-SENKRON.md §2, O5): pull dirty satırı ezmez (R1),
/// tombstone'u diriltmez (R2), sunucuda olmayan temiz satırı K-2 korumalarıyla
/// siler (R4), dirty yalnız sunucu onayıyla temizlenir (R5); ekran yerel akışı
/// dinler, push/pull arka planda (R8).
class MemoryRepository {
  final AppDatabase _db;
  final ApiClient _api;
  final String _localUserId;
  /// Bu BEBEK bulut senkronuna tabi mi? Per-baby (Seçenek 2): paylaşılan bebek
  /// sahibin premium'uyla senkronlanır, kendi bebeğim kendi premium'umla.
  final bool Function(String babyId) _cloudEnabled;

  MemoryRepository(this._db, this._api, this._localUserId, this._cloudEnabled);

  /// Kalıcı (4xx) reddedilen push'lar `pushError` kolonunda (K-1).
  /// Bebek rolü caregiver mı (403 → `pushError='role'`, K-1).
  Future<bool> _isCaregiver(String babyId) async {
    final b = await (_db.select(_db.babies)..where((x) => x.id.equals(babyId)))
        .getSingleOrNull();
    return b?.myRole == 'caregiver';
  }

  Future<void> _setPushError(String id, String? err) =>
      (_db.update(_db.memories)..where((m) => m.id.equals(id)))
          .write(MemoriesCompanion(pushError: Value(err)));

  /// K-1 "geri al": sunucu listesinde satır varsa uygulanır (tombstone kalkar,
  /// dirty=false, pushError=null; yerel foto kopyası korunur); yoksa `notOnServer`.
  Future<RevertResult> revertToServer(String babyId, String id) async {
    try {
      final resp = await _api.dio.get('/babies/$babyId/memories');
      if (resp.statusCode != 200 || resp.data is! List) return RevertResult.failed;
      for (final e in resp.data as List) {
        if (e is! Map || e['id'] != id) continue;
        final m = e.cast<String, dynamic>();
        await _db.into(_db.memories).insertOnConflictUpdate(
              MemoriesCompanion.insert(
                id: id,
                baby: babyId,
                date: DateTime.parse(m['date'] as String),
                title: Value((m['title'] as String?) ?? ''),
                note: Value((m['note'] as String?) ?? ''),
                photo: Value(m['photo'] as String?),
                firstTag: Value((m['first_tag'] as String?) ?? ''),
                createdBy: Value(m['created_by'] as String?),
                serverUpdatedAt: Value(_parseTs(m['updated_at'])),
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

  /// Kullanıcı onayıyla yerel satırı kaldırır (sunucuda hiç yoktu).
  Future<void> discardLocal(String id) async {
    final r = await (_db.select(_db.memories)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    await _deletePhotoFile(r?.localPhotoPath); // O33
    await (_db.delete(_db.memories)..where((m) => m.id.equals(id))).go();
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---- Yerel okuma ----

  /// Reaktif liste (tarihe göre yeni→eski, tombstone gizli). UI bunu dinler;
  /// ağ beklemez (R8).
  Stream<List<Memory>> watch(String babyId) {
    final q = _db.select(_db.memories)
      ..where((m) => m.baby.equals(babyId) & m.isDeleted.equals(false))
      ..orderBy([(m) => OrderingTerm.desc(m.date)]);
    return q.watch().map((rows) => rows.map(_toModel).toList());
  }

  /// Tek seferlik yerel okuma (dışa aktarma vb.). Ağa ÇIKMAZ.
  Future<List<Memory>> list(String babyId) async {
    final rows = await (_db.select(_db.memories)
          ..where((m) => m.baby.equals(babyId) & m.isDeleted.equals(false))
          ..orderBy([(m) => OrderingTerm.desc(m.date)]))
        .get();
    return rows.map(_toModel).toList();
  }

  /// Bulut uygunsa arka planda push + pull; her hata yutulur (yerel korunur).
  Future<void> syncIfCloud(String babyId) async {
    if (!_cloudEnabled(babyId)) return;
    try {
      await pushDirty(babyId);
      await _pull(babyId);
    } catch (_) {}
  }

  Future<Memory> create(
    String babyId, {
    required DateTime date,
    String title = '',
    String note = '',
    String firstTag = '',
    String? photoPath,
  }) async {
    final id = _uuid.v4();
    final storedPhoto =
        photoPath == null ? null : await _persistPhoto(id, photoPath);
    await _db.into(_db.memories).insertOnConflictUpdate(
          MemoriesCompanion.insert(
            id: id,
            baby: babyId,
            date: date,
            title: Value(title),
            note: Value(note),
            firstTag: Value(firstTag),
            localPhotoPath: Value(storedPhoto),
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
    await (_db.update(_db.memories)..where((m) => m.id.equals(id))).write(
      MemoriesCompanion(
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

  /// Erişim kaldırılınca (paylaşımdan düşme) bu bebeğin tüm anılarını yerelden sil.
  Future<void> purgeBaby(String babyId) async {
    final rows =
        await (_db.select(_db.memories)..where((m) => m.baby.equals(babyId))).get();
    for (final r in rows) {
      await _deletePhotoFile(r.localPhotoPath);
    }
    await (_db.delete(_db.memories)..where((m) => m.baby.equals(babyId))).go();
  }

  /// O33: satır yerelden KALICI silinince yerel fotoğraf dosyası da gitsin
  /// (purge, pull R4, discard, tombstone DELETE başarısı). Sunucu URL'i ve
  /// olmayan dosya sessizce atlanır.
  Future<void> _deletePhotoFile(String? path) async {
    if (path == null || path.startsWith('http')) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static DateTime? _parseTs(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

  Future<void> _pull(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/memories');
    // Yanıt TAMAMEN parse edilmeden hiçbir şey uygulanmaz (R4 güvencesi).
    final rows = (resp.data as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final serverIds = {for (final m in rows) m['id'] as String};
    final local = await (_db.select(_db.memories)
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
      debugPrint('[memories-pull] silme atlandı: ${stale.skippedReason}');
    }
    await _db.transaction(() async {
      for (final m in rows) {
        final id = m['id'] as String;
        final l = localById[id];
        final decision = decideServerRow(
          localExists: l != null,
          localDirty: l?.dirty ?? false,
          localDeleted: l?.isDeleted ?? false,
          localStamp: l?.clientUpdatedAt,
          serverStamp: _parseTs(m['updated_at']),
        );
        if (decision != MergeDecision.apply) continue;
        // `localPhotoPath` companion'da YOK → yerel kopya korunur.
        await _db.into(_db.memories).insertOnConflictUpdate(
              MemoriesCompanion.insert(
                id: id,
                baby: babyId,
                date: DateTime.parse(m['date'] as String),
                title: Value((m['title'] as String?) ?? ''),
                note: Value((m['note'] as String?) ?? ''),
                photo: Value(m['photo'] as String?),
                firstTag: Value((m['first_tag'] as String?) ?? ''),
                createdBy: Value(m['created_by'] as String?),
                serverUpdatedAt: Value(_parseTs(m['updated_at'])),
                dirty: const Value(false),
              ),
            );
      }
      // R4: sunucuda artık olmayan temiz satırlar (başka üye sildi).
      for (final id in stale.ids) {
        await _deletePhotoFile(localById[id]?.localPhotoPath); // O33
        await (_db.delete(_db.memories)..where((m) => m.id.equals(id))).go();
      }
    });
  }

  /// Migrasyonda tam yükleme için bu bebeğin TÜM anılarını dirty işaretle.
  /// Yerel foto kopyası olanların cloud URL'ini de temizle → pushDirty fotoyu
  /// yeniden gönderir (grace-purge sonrası cloud'da foto kalmamış olabilir).
  /// Yerel kopyası olmayanlarda (yalnız cloud URL) foto geri yüklenemez, yalnız
  /// metadata dirty olur.
  Future<void> markAllDirty(String babyId) async {
    await (_db.update(_db.memories)
          ..where((m) => m.baby.equals(babyId) & m.localPhotoPath.isNotNull()))
        .write(const MemoriesCompanion(
            photo: Value(null), dirty: Value(true)));
    await (_db.update(_db.memories)
          ..where((m) => m.baby.equals(babyId) & m.localPhotoPath.isNull()))
        .write(const MemoriesCompanion(dirty: Value(true)));
  }

  /// Yerel dirty anıları sunucuya yollar (premium / migrasyon). Foto varsa
  /// multipart yükler; dönüşte yerel satır sunucu URL'iyle güncellenir.
  /// DELETE 404 = sunucuda zaten yok → başarı sayılır (R3); diğer hatalar
  /// geçici (dirty kalır) / kalıcı (dirty kalır + pushError) diye sınıflanır.
  Future<void> pushDirty(String babyId) async {
    final dirty = await (_db.select(_db.memories)
          ..where((m) => m.baby.equals(babyId) & m.dirty.equals(true)))
        .get();
    for (final r in dirty) {
      if (r.isDeleted) {
        try {
          await _api.dio.delete('/babies/$babyId/memories/${r.id}');
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) {
            await _noteFailure(babyId, r.id, e);
            continue; // tombstone dirty kalır, sonraki tur yeniden dener
          }
          // 404: sunucuda zaten yok → yerel temizliğe düş.
        } catch (_) {
          continue;
        }
        await _deletePhotoFile(r.localPhotoPath); // O33
        await (_db.delete(_db.memories)..where((m) => m.id.equals(r.id))).go();
        continue;
      }
      try {
        // Henüz yüklenmemişse (server URL yok) oluştur; foto'yu da gönder.
        final form = FormData.fromMap({
          'id': r.id,
          'date': _ymd(r.date),
          'title': r.title,
          'note': r.note,
          'first_tag': r.firstTag,
          if (r.photo == null && r.localPhotoPath != null)
            'photo': await MultipartFile.fromFile(r.localPhotoPath!),
        });
        final resp =
            await _api.dio.post('/babies/$babyId/memories', data: form);
        final srv = resp.data as Map<String, dynamic>;
        // R5 / I3: POST (foto yüklemesi) uçuştayken satır silindiyse tombstone
        // dirty KALIR → DELETE bir sonraki turda gider (eskiden dirty=false
        // yazılıp satır yerelde gizli, sunucuda canlı kalıyordu).
        final cur = await (_db.select(_db.memories)..where((m) => m.id.equals(r.id)))
            .getSingleOrNull();
        final unchanged = cur != null &&
            cur.clientUpdatedAt == r.clientUpdatedAt &&
            cur.isDeleted == r.isDeleted &&
            cur.title == r.title &&
            cur.note == r.note &&
            cur.date == r.date &&
            cur.firstTag == r.firstTag &&
            cur.localPhotoPath == r.localPhotoPath;
        await (_db.update(_db.memories)..where((m) => m.id.equals(r.id))).write(
          MemoriesCompanion(
            photo: Value(srv['photo'] as String?),
            serverUpdatedAt: Value(_parseTs(srv['updated_at'])),
            dirty: unchanged ? const Value(false) : const Value.absent(),
            pushError: const Value(null),
          ),
        );
      } on DioException catch (e) {
        await _noteFailure(babyId, r.id, e); // dirty kalır
      } catch (e) {
        // Yerel foto dosyası okunamadı vb. — kalıcı: bir daha başaramaz.
        await _setPushError(r.id, 'local');
        debugPrint('[memories-push] ${r.id}: $e');
      }
    }
  }

  /// R3 + K-1: kalıcı 4xx → `pushError` kolonu; 403 + caregiver → `'role'`
  /// (rol düşmüş, sonsuza dek 403 alırdı).
  Future<void> _noteFailure(String babyId, String id, DioException e) async {
    final code = e.response?.statusCode;
    if (code == 403 && await _isCaregiver(babyId)) {
      await _setPushError(id, 'role');
      return;
    }
    if (classifyDioError(e) == PushFailure.permanent) {
      await _setPushError(id, 'HTTP $code');
      debugPrint('[memories-push] kalıcı red $id: HTTP $code ${e.response?.data}');
    }
  }

  /// Foto'yu kalıcı uygulama dizinine kopyalar, kalıcı yolu döner.
  Future<String?> _persistPhoto(String id, String srcPath) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final mem = Directory(p.join(dir.path, 'memories'));
      if (!await mem.exists()) await mem.create(recursive: true);
      final ext = p.extension(srcPath);
      final dest = p.join(mem.path, '$id$ext');
      await File(srcPath).copy(dest);
      return dest;
    } catch (_) {
      return srcPath; // kopyalanamazsa orijinal yolu kullan
    }
  }

  Future<Memory?> _byId(String id) async {
    final r = await (_db.select(_db.memories)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    return r == null ? null : _toModel(r);
  }

  Memory _toModel(MemoryRow r) => Memory(
        id: r.id,
        date: r.date,
        title: r.title,
        note: r.note,
        // Sunucu URL'i varsa onu, yoksa yerel foto yolunu göster.
        photo: r.photo ?? r.localPhotoPath,
        firstTag: r.firstTag,
      );
}

final memoryRepositoryProvider = Provider<MemoryRepository>(
  (ref) => MemoryRepository(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
    ref.watch(localUserIdProvider),
    (babyId) => ref.read(babyCloudSyncedProvider(babyId)),
  ),
);

/// Aktif bebeğin anıları (tarihe göre yeni→eski) — yerel drift akışı (R8).
/// Kurulunca/yenilenince bulut senkronu ARKA PLANDA tetiklenir; ekran ağı
/// beklemez, sunucudan gelen değişiklik akışa düşünce görünür.
final memoriesProvider = StreamProvider.family<List<Memory>, String>(
  (ref, babyId) {
    final repo = ref.watch(memoryRepositoryProvider);
    unawaited(repo.syncIfCloud(babyId));
    return repo.watch(babyId);
  },
);
