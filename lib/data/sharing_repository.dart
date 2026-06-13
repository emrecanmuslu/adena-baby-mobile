import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/activity_event.dart';

/// Paylaşım/ekip ucu: canlı aktivite akışı (salt-okunur).
class SharingRepository {
  final ApiClient _api;
  SharingRepository(this._api);

  Future<List<ActivityEvent>> activity(String babyId, {DateTime? since}) async {
    final resp = await _api.dio.get(
      '/babies/$babyId/activity',
      queryParameters:
          since != null ? {'since': since.toUtc().toIso8601String()} : null,
    );
    final data = resp.data as List<dynamic>;
    return data.map((e) => ActivityEvent.fromJson(e as Map<String, dynamic>)).toList();
  }
}

final sharingRepositoryProvider = Provider<SharingRepository>(
  (ref) => SharingRepository(ref.watch(apiClientProvider)),
);

/// Aktif bebeğin canlı aktivite akışı (son 50, yeni→eski).
final activityProvider = FutureProvider.family<List<ActivityEvent>, String>(
  (ref, babyId) => ref.watch(sharingRepositoryProvider).activity(babyId),
);
