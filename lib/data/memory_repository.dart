import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/memory.dart';

/// Anılar / fotoğraf günlüğü uçları — online CRUD, foto multipart upload.
/// (Offline-first sync'e dahil değil; fotoğraflar çevrimiçi yüklenir.)
class MemoryRepository {
  final ApiClient _api;
  MemoryRepository(this._api);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<List<Memory>> list(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/memories');
    final data = resp.data as List<dynamic>;
    return data.map((e) => Memory.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Memory> create(
    String babyId, {
    required DateTime date,
    String title = '',
    String note = '',
    String firstTag = '',
    String? photoPath,
  }) async {
    final form = FormData.fromMap({
      'date': _ymd(date),
      'title': title,
      'note': note,
      'first_tag': firstTag,
      if (photoPath != null)
        'photo': await MultipartFile.fromFile(photoPath),
    });
    final resp = await _api.dio.post('/babies/$babyId/memories', data: form);
    return Memory.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> delete(String babyId, String id) =>
      _api.dio.delete('/babies/$babyId/memories/$id');
}

final memoryRepositoryProvider = Provider<MemoryRepository>(
    (ref) => MemoryRepository(ref.watch(apiClientProvider)));

/// Aktif bebeğin anıları (tarihe göre yeni→eski; sunucu sıralı).
final memoriesProvider = FutureProvider.family<List<Memory>, String>(
  (ref, babyId) => ref.watch(memoryRepositoryProvider).list(babyId),
);
