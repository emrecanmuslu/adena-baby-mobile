import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/config.dart';
import '../core/i18n.dart';

/// Kullanıcıya gösterilebilir sosyal giriş hatası (apiErrorText bunu olduğu
/// gibi gösterir). İptal durumları hata değildir → `null` döner.
class SocialAuthException implements Exception {
  final String message;
  SocialAuthException(this.message);
  @override
  String toString() => message;
}

/// Sosyal sağlayıcılardan (Google/Apple) `id_token` alır. Token backend'e
/// `POST /auth/social` ile gönderilir (bkz. AuthRepository.social).
/// Kullanıcı sağlayıcı ekranını iptal ederse `null` döner (sessiz).
class SocialAuthService {
  bool _googleInited = false;

  Future<void> _ensureGoogleInit() async {
    if (_googleInited) return;
    if (AppConfig.googleServerClientId.isEmpty &&
        AppConfig.googleIosClientId.isEmpty) {
      throw SocialAuthException(
          tr('Google ile giriş yapılandırılmamış (client ID eksik)'));
    }
    await GoogleSignIn.instance.initialize(
      clientId:
          AppConfig.googleIosClientId.isEmpty ? null : AppConfig.googleIosClientId,
      serverClientId: AppConfig.googleServerClientId.isEmpty
          ? null
          : AppConfig.googleServerClientId,
    );
    _googleInited = true;
  }

  /// Google ile giriş → `id_token`. İptal → `null`.
  Future<String?> google() async {
    await _ensureGoogleInit();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw SocialAuthException(tr('Google id_token alınamadı'));
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw SocialAuthException(
          trp('Google giriş hatası: {e}', {'e': e.code.name}));
    }
  }

  /// Apple ile giriş → `identityToken`. İptal → `null`.
  Future<String?> apple() async {
    final nativeApple = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    if (!nativeApple && AppConfig.appleServiceId.isEmpty) {
      throw SocialAuthException(
          tr('Apple ile giriş bu cihazda yapılandırılmamış'));
    }
    try {
      final cred = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: AppConfig.appleServiceId.isEmpty
            ? null
            : WebAuthenticationOptions(
                clientId: AppConfig.appleServiceId,
                redirectUri: Uri.parse(AppConfig.appleRedirectUri),
              ),
      );
      final token = cred.identityToken;
      if (token == null || token.isEmpty) {
        throw SocialAuthException(tr('Apple kimlik token alınamadı'));
      }
      return token;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw SocialAuthException(
          trp('Apple giriş hatası: {e}', {'e': e.message}));
    }
  }

  /// Apple butonu bu cihazda gösterilmeli mi? (iOS/macOS her zaman; Android'de
  /// yalnızca Services ID yapılandırılmışsa.)
  static bool get appleAvailable {
    if (kIsWeb) return AppConfig.appleServiceId.isNotEmpty;
    if (Platform.isIOS || Platform.isMacOS) return true;
    return AppConfig.appleServiceId.isNotEmpty;
  }
}

final socialAuthServiceProvider =
    Provider<SocialAuthService>((ref) => SocialAuthService());
