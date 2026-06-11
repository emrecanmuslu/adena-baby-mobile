import 'package:dio/dio.dart';

import 'config.dart';
import 'i18n.dart';
import 'token_storage.dart';

/// Dio tabanlı API istemcisi. JWT ekler ve 401'de otomatik token yeniler.
class ApiClient {
  final Dio dio;
  final TokenStorage _tokens;

  ApiClient(this._tokens)
      : dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          contentType: 'application/json',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Aktif dili gönder → sunucu (DRF/Django) hata mesajlarını bu dilde
        // döndürür. Her istekte taze okunur (dil değişimi anında yansır).
        options.headers['Accept-Language'] = I18n.instance.locale;
        // 'noAuth' işaretli isteklere token ekleme (login/register/refresh).
        if (options.extra['noAuth'] != true) {
          final token = await _tokens.accessToken;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final shouldRetry = e.response?.statusCode == 401 &&
            e.requestOptions.extra['retried'] != true &&
            e.requestOptions.extra['noAuth'] != true;
        if (shouldRetry && await _refresh()) {
          final opts = e.requestOptions..extra['retried'] = true;
          final token = await _tokens.accessToken;
          opts.headers['Authorization'] = 'Bearer $token';
          try {
            return handler.resolve(await dio.fetch(opts));
          } catch (_) {/* düşerse aşağıya */}
        }
        handler.next(e);
      },
    ));
  }

  /// Refresh token ile yeni access (ve dönerse refresh) alır.
  Future<bool> _refresh() async {
    final refresh = await _tokens.refreshToken;
    if (refresh == null) return false;
    try {
      final resp = await Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl))
          .post('/auth/refresh', data: {'refresh': refresh});
      await _tokens.saveTokens(
        access: resp.data['access'] as String,
        refresh: resp.data['refresh'] as String?,
      );
      return true;
    } catch (_) {
      await _tokens.clear();
      return false;
    }
  }
}
