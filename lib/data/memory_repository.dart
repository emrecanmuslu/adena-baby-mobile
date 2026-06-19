import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
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

const _uuid = Uuid();

/// Anılar / foto günlüğü — **local-first**. Free'de anı + foto telefonda
/// (`localPhotoPath`); premium'da `/babies/{id}/memories` ile aynalanır ve foto
/// yüklenir (`photo` sunucu URL'i olur). Foto, image_picker'ın geçici yolundan
/// kalıcı uygulama dizinine kopyalanır (geçici dosya silinse de kaybolmasın).
class MemoryRepository {
  final AppDatabase _db;
  final ApiClient _api;
  final String _localUserId;
  /// Bu BEBEK bulut senkronuna tabi mi? Per-baby (Seçenek 2): paylaşılan bebek
  /// sahibin premium'uyla senkronlanır, kendi bebeğim kendi premium'umla.
  final bool Function(String babyId) _cloudEnabled;

  MemoryRepository(this._db, this._api, this._localUserId, this._cloudEnabled);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<Memory>> list(String babyId) async {
    if (_cloudEnabled(babyId)) {
      try {
        await pushDirty(babyId);
        await _pull(babyId);
      } catch (_) {}
    }
    final rows = await (_db.select(_db.memories)
          ..where((m) => m.baby.equals(babyId) & m.isDeleted.equals(false))
          ..orderBy([(m) => OrderingTerm.desc(m.date)]))
        .get();
    return rows.map(_toModel).toList();
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
    await (_db.delete(_db.memories)..where((m) => m.baby.equals(babyId))).go();
  }

  Future<void> _pull(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/memories');
    final data = resp.data as List<dynamic>;
    await _db.transaction(() async {
      for (final e in data) {
        final m = e as Map<String, dynamic>;
        await _db.into(_db.memories).insertOnConflictUpdate(
              MemoriesCompanion.insert(
                id: m['id'] as String,
                baby: babyId,
                date: DateTime.parse(m['date'] as String),
                title: Value((m['title'] as String?) ?? ''),
                note: Value((m['note'] as String?) ?? ''),
                photo: Value(m['photo'] as String?),
                firstTag: Value((m['first_tag'] as String?) ?? ''),
                createdBy: Value(m['created_by'] as String?),
                dirty: const Value(false),
              ),
            );
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
  Future<void> pushDirty(String babyId) async {
    final dirty = await (_db.select(_db.memories)
          ..where((m) => m.baby.equals(babyId) & m.dirty.equals(true)))
        .get();
    for (final r in dirty) {
      try {
        if (r.isDeleted) {
          await _api.dio.delete('/babies/$babyId/memories/${r.id}');
          await (_db.delete(_db.memories)..where((m) => m.id.equals(r.id))).go();
          continue;
        }
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
        await (_db.update(_db.memories)..where((m) => m.id.equals(r.id))).write(
          MemoriesCompanion(
            photo: Value(srv['photo'] as String?),
            dirty: const Value(false),
          ),
        );
      } catch (_) {
        // çevrimdışı/hata — dirty kalır, sonra tekrar denenir
      }
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

/// Aktif bebeğin anıları (tarihe göre yeni→eski).
final memoriesProvider = FutureProvider.family<List<Memory>, String>(
  (ref, babyId) => ref.watch(memoryRepositoryProvider).list(babyId),
);
