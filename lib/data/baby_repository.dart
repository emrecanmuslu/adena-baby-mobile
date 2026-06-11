import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/baby.dart';
import '../models/membership.dart';

/// Bebek uç noktaları: liste/oluştur + üyelik & davet (rol-bazlı paylaşım).
class BabyRepository {
  final ApiClient _api;
  BabyRepository(this._api);

  Future<List<Baby>> list() async {
    final resp = await _api.dio.get('/babies');
    final data = resp.data as List<dynamic>;
    return data.map((e) => Baby.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Baby> create(Baby baby) async {
    final resp = await _api.dio.post('/babies', data: baby.toCreateJson());
    return Baby.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Baby> update(String babyId, Map<String, dynamic> fields) async {
    final resp = await _api.dio.patch('/babies/$babyId', data: fields);
    return Baby.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> delete(String babyId) => _api.dio.delete('/babies/$babyId');

  // ---- Üyelik & davet ----

  Future<List<Membership>> members(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/members');
    final data = resp.data as List<dynamic>;
    return data.map((e) => Membership.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Davet oluşturur → {invite_code, link, role, expires_at}.
  Future<Map<String, dynamic>> createInvitation(String babyId,
      {required String role, String? email}) async {
    final resp = await _api.dio.post('/babies/$babyId/invitations', data: {
      'role': role,
      if (email != null && email.isNotEmpty) 'email': email,
    });
    return resp.data as Map<String, dynamic>;
  }

  /// Davet kodunu kabul eder → {membership, baby}. Yeni bebek döner.
  Future<Baby> acceptInvitation(String code) async {
    final resp = await _api.dio.post('/invitations/accept', data: {'code': code});
    return Baby.fromJson((resp.data as Map<String, dynamic>)['baby'] as Map<String, dynamic>);
  }

  Future<void> updateMemberRole(String babyId, String userId, String role) =>
      _api.dio.patch('/babies/$babyId/members/$userId', data: {'role': role});

  Future<void> removeMember(String babyId, String userId) =>
      _api.dio.delete('/babies/$babyId/members/$userId');

  // ---- Aile ayarları (birimler vb.) ----

  Future<Map<String, dynamic>> familySettings(String babyId) async {
    final resp = await _api.dio.get('/babies/$babyId/settings');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateFamilySettings(
      String babyId, Map<String, dynamic> fields) async {
    final resp = await _api.dio.patch('/babies/$babyId/settings', data: fields);
    return resp.data as Map<String, dynamic>;
  }
}

final babyRepositoryProvider = Provider<BabyRepository>(
  (ref) => BabyRepository(ref.watch(apiClientProvider)),
);
