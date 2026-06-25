import 'package:dio/dio.dart';

import '../data/api_log.dart';
import '../data/sync_diag.dart';
import 'config.dart';
import 'i18n.dart';
import 'token_storage.dart';

/// Dio tabanlı API istemcisi. JWT ekler ve 401'de otomatik token yeniler.
class ApiClient {
  final Dio dio;
  final TokenStorage _tokens;

  /// Refresh isteğinin atıldığı ayrı Dio. Varsayılan: aynı baseUrl ile taze bir
  /// Dio (üretim davranışı değişmez). Test, buraya DioAdapter'lı bir Dio
  /// enjekte ederek /auth/refresh'i stub'layabilir.
  final Dio _refreshClient;

  ApiClient(this._tokens, {Dio? refreshClient})
      : dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          contentType: 'application/json',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        )),
        _refreshClient =
            refreshClient ?? Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl)) {
    // API LOG: her istek/yanıt/hata → ApiLog (method·path·status·süre). Hassas veri
    // (gövde/header/token) YAZILMAZ. En önce eklenir → _t0 en erken damgalanır,
    // onResponse/onError (ters sıra) en son çalışır → nihai durumu yakalar.
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.extra['_t0'] = DateTime.now().millisecondsSinceEpoch;
        handler.next(options);
      },
      onResponse: (resp, handler) {
        final t0 = resp.requestOptions.extra['_t0'] as int?;
        final ms = t0 == null ? -1 : DateTime.now().millisecondsSinceEpoch - t0;
        ApiLog.add('${resp.requestOptions.method} ${resp.requestOptions.uri.path}'
            ' → ${resp.statusCode} (${ms}ms)');
        handler.next(resp);
      },
      onError: (e, handler) {
        final t0 = e.requestOptions.extra['_t0'] as int?;
        final ms = t0 == null ? -1 : DateTime.now().millisecondsSinceEpoch - t0;
        ApiLog.add('${e.requestOptions.method} ${e.requestOptions.uri.path}'
            ' → ERR ${e.response?.statusCode ?? e.type.name} (${ms}ms)');
        handler.next(e);
      },
    ));
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
    if (refresh == null) {
      await SyncDiag.add('refresh SKIP no-token'); // TANI-GEÇİCİ
      return false;
    }
    try {
      final resp = await _refreshClient
          .post('/auth/refresh', data: {'refresh': refresh});
      await _tokens.saveTokens(
        access: resp.data['access'] as String,
        refresh: resp.data['refresh'] as String?,
      );
      await SyncDiag.add('refresh OK'); // TANI-GEÇİCİ
      return true;
    } catch (e) {
      // TANI-GEÇİCİ: token'ı silmeden ÖNCE hatayı kaydet. status=null → geçici
      // ağ/timeout hatası (oturum gereksiz yere siliniyor olabilir); 401 → gerçek
      // geçersiz refresh. Bu ayrım kök-nedeni belirler.
      final code = e is DioException ? e.response?.statusCode : null;
      await SyncDiag.add('refresh FAIL status=$code (${e.runtimeType})');
      await _tokens.clear();
      return false;
    }
  }
}
