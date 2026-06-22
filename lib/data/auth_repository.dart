import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../core/token_storage.dart';
import '../models/user.dart';

/// Auth uç noktaları: register/login/me/logout. Token'ları TokenStorage'a yazar.
/// Hatalar DioException olarak yukarı geçer; UI'da apiErrorText ile gösterilir.
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
    final resp = await _dio.post(
      '/auth/register',
      // Yasal rıza kayıt ekranındaki zorunlu kutuyla alınır; backend Consent
      // kaydı yazar. Kutu işaretlenmeden submit edilemez → her zaman true.
      data: {
        'email': email,
        'password': password,
        'name': name,
        'accepted_legal': true,
        'age_confirmed': true,
      },
      options: Options(extra: {'noAuth': true}),
    );
    return _consumeAuth(resp.data as Map<String, dynamic>);
  }

  Future<User> login({required String email, required String password}) async {
    final resp = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
      options: Options(extra: {'noAuth': true}),
    );
    return _consumeAuth(resp.data as Map<String, dynamic>);
  }

  /// Parola sıfırlama kodu ister (POST /auth/password/forgot). Sunucu, hesap
  /// var olsun olmasın her zaman 200 döner (e-posta varlığı sızdırılmaz).
  Future<void> forgotPassword(String email) async {
    await _dio.post(
      '/auth/password/forgot',
      data: {'email': email},
      options: Options(extra: {'noAuth': true}),
    );
  }

  /// Kod + yeni şifreyle sıfırlar (POST /auth/password/reset). Başarılıysa sunucu
  /// token döner → kullanıcı otomatik giriş yapmış olur (login gibi işlenir).
  Future<User> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final resp = await _dio.post(
      '/auth/password/reset',
      data: {'email': email, 'code': code, 'new_password': newPassword},
      options: Options(extra: {'noAuth': true}),
    );
    return _consumeAuth(resp.data as Map<String, dynamic>);
  }

  /// Sosyal giriş: sağlayıcının id_token'ını backend'e doğrulatır (kullanıcı
  /// yoksa oluşturulur), JWT döner. provider: 'google' | 'apple'.
  Future<User> social({required String provider, required String idToken}) async {
    final resp = await _dio.post(
      '/auth/social',
      data: {'provider': provider, 'id_token': idToken},
      options: Options(extra: {'noAuth': true}),
    );
    return _consumeAuth(resp.data as Map<String, dynamic>);
  }

  /// Mevcut oturum sahibini getirir (GET /auth/me). Yanıttaki `consent_required`
  /// kullanıcıya iliştirilir (rıza kapısı yönlendirmesi için).
  Future<User> me() async {
    final resp = await _dio.get('/auth/me');
    final data = resp.data as Map<String, dynamic>;
    return User.fromJson(data['user'] as Map<String, dynamic>)
        .copyWith(consentRequired: data['consent_required'] as bool? ?? false);
  }

  /// Yasal rızayı kaydeder (rıza kapısı / sosyal giriş sonrası). POST /auth/consent.
  Future<void> recordConsent() async {
    await _dio.post('/auth/consent', data: {
      'accepted_legal': true,
      'age_confirmed': true,
      'source': 'gate',
    });
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

  /// Sunucudaki tüm kullanıcı verisinin tam kopyası (GDPR/KVKK taşınabilirlik).
  /// GET /auth/me/export — foto URL'leri, topluluk Q&A, tüm cihaz kayıtları dâhil.
  Future<Map<String, dynamic>> exportData() async {
    final resp = await _dio.get('/auth/me/export');
    return resp.data as Map<String, dynamic>;
  }

  /// Kullanıcı geri bildirimi gönderir (POST /auth/feedback).
  /// [category] = feature | bug | other. Platform ve sürüm otomatik eklenir.
  Future<void> submitFeedback({
    required String category,
    required String message,
  }) async {
    var platform = '';
    if (Platform.isAndroid) {
      platform = 'android';
    } else if (Platform.isIOS) {
      platform = 'ios';
    }
    var version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    await _dio.post('/auth/feedback', data: {
      'category': category,
      'message': message,
      'platform': platform,
      'app_version': version,
    });
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

  /// {user, access, refresh, consent_required} yanıtını işler: token'ları yazar,
  /// User'a rıza durumunu iliştirir, User döner.
  Future<User> _consumeAuth(Map<String, dynamic> data) async {
    await _tokens.saveTokens(
      access: data['access'] as String,
      refresh: data['refresh'] as String?,
    );
    return User.fromJson(data['user'] as Map<String, dynamic>)
        .copyWith(consentRequired: data['consent_required'] as bool? ?? false);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);
