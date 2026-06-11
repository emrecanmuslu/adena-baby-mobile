import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../core/token_storage.dart';
import '../models/user.dart';

/// Kullanıcıya gösterilebilir auth hatası.
class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Auth uç noktaları: register/login/me/logout. Token'ları TokenStorage'a yazar.
class AuthRepository {
  final ApiClient _api;
  final TokenStorage _tokens;

  AuthRepository(this._api, this._tokens);

  Dio get _dio => _api.dio;

  Future<User> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final resp = await _dio.post(
        '/auth/register',
        data: {'email': email, 'password': password, 'name': name},
        options: Options(extra: {'noAuth': true}),
      );
      return _consumeAuth(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AuthException(_friendly(e));
    }
  }

  Future<User> login({required String email, required String password}) async {
    try {
      final resp = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
        options: Options(extra: {'noAuth': true}),
      );
      return _consumeAuth(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw AuthException(_friendly(e));
    }
  }

  /// Mevcut oturum sahibini getirir (GET /auth/me).
  Future<User> me() async {
    final resp = await _dio.get('/auth/me');
    final data = resp.data as Map<String, dynamic>;
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Kullanıcı ayarlarını getirir (GET /auth/me/settings).
  Future<Map<String, dynamic>> settings() async {
    final resp = await _dio.get('/auth/me/settings');
    return resp.data as Map<String, dynamic>;
  }

  /// Kullanıcı ayarlarını günceller (PATCH /auth/me/settings).
  Future<void> updateSettings(Map<String, dynamic> fields) async {
    await _dio.patch('/auth/me/settings', data: fields);
  }

  /// Profil adını günceller (PATCH /auth/me).
  Future<User> updateName(String name) async {
    final resp = await _dio.patch('/auth/me', data: {'name': name});
    return User.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Hesabı ve tüm verisini siler (GDPR — DELETE /auth/me).
  Future<void> deleteAccount() async {
    await _dio.delete('/auth/me');
    await _tokens.clear();
  }

  Future<void> logout() async {
    final refresh = await _tokens.refreshToken;
    try {
      await _dio.post(
        '/auth/logout',
        data: {'refresh': refresh},
        options: Options(extra: {'noAuth': true}),
      );
    } catch (_) {
      // Sunucuda stateless; yine de yerel token'ları temizle.
    }
    await _tokens.clear();
  }

  /// {user, access, refresh} yanıtını işler: token'ları yazar, User döner.
  Future<User> _consumeAuth(Map<String, dynamic> data) async {
    await _tokens.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String?,
    );
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// DRF hata gövdesinden okunabilir Türkçe mesaj çıkarır.
  String _friendly(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['detail'] is String) return data['detail'] as String;
      // Alan bazlı doğrulama hataları: {email: ["..."], password: ["..."]}
      for (final v in data.values) {
        if (v is List && v.isNotEmpty) return v.first.toString();
        if (v is String) return v;
      }
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Sunucuya ulaşılamıyor. Bağlantını kontrol et.';
    }
    return 'Bir şeyler ters gitti. Tekrar dene.';
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);
