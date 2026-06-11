import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/mom_entry.dart';

const _uuid = Uuid();

/// Bekleme modu anne takibi uçları (kilo/randevu/not) — online CRUD.
class MomRepository {
  final ApiClient _api;
  MomRepository(this._api);

  Future<List<MomEntry>> list(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/mom-entries');
    final data = resp.data as List<dynamic>;
    return data.map((e) => MomEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<MomEntry> add(
    String babyId, {
    required MomKind kind,
    required DateTime date,
    double? weightKg,
    String? title,
    String? note,
  }) async {
    final entry = MomEntry(
      id: _uuid.v4(),
      kind: kind,
      date: date,
      weightKg: weightKg,
      title: title,
      note: note,
    );
    final resp = await _api.dio
        .post('/babies/$babyId/mom-entries', data: entry.toCreateJson());
    return MomEntry.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> delete(String babyId, String id) =>
      _api.dio.delete('/babies/$babyId/mom-entries/$id');
}

final momRepositoryProvider =
    Provider<MomRepository>((ref) => MomRepository(ref.watch(apiClientProvider)));

/// Aktif bebeğin anne takibi kayıtları (tarihe göre yeni→eski).
final momEntriesProvider = FutureProvider.family<List<MomEntry>, String>(
  (ref, babyId) => ref.watch(momRepositoryProvider).list(babyId),
);
