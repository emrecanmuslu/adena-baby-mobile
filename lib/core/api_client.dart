import 'package:dio/dio.dart';

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
        if (shouldRetry && await _refreshIfNeeded(e.requestOptions)) {
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

  /// Devam eden refresh turu — **tek-uçuş (single-flight) kilidi**.
  /// Access token'ın ömrü dolduğunda uygulama aynı anda onlarca istek atar
  /// (açılış turu: babies + sync + content + me...); hepsi birden 401 alır.
  /// Kilit olmadan her biri ayrı ayrı `/auth/refresh` çağırıyordu: sunucu
  /// loglarında aynı saniyede 3-4 refresh, rotasyon yarışı ve yarışı kaybeden
  /// isteğin (çoğu kez `/sync`) sessizce düşmesi → sahte "Senkron sorunu".
  Future<bool>? _refreshing;

  /// 401 alan istek için token tazeleme kararı:
  /// - Bu arada BAŞKA bir istek token'ı yenilediyse (istekteki Bearer artık
  ///   güncel değilse) refresh'e hiç gerek yok → doğrudan retry.
  /// - Yenilenmediyse: turu başlat ya da devam eden tura katıl (tek-uçuş).
  Future<bool> _refreshIfNeeded(RequestOptions failed) async {
    final current = await _tokens.accessToken;
    if (current != null && failed.headers['Authorization'] != 'Bearer $current') {
      return true; // token değişmiş → yeni token'la bir kez daha dene
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  /// Refresh token ile yeni access (ve dönerse refresh) alır.
  Future<bool> _refresh() async {
    final refresh = await _tokens.refreshToken;
    if (refresh == null) return false;
    try {
      final resp = await _refreshClient
          .post('/auth/refresh', data: {'refresh': refresh});
      await _tokens.saveTokens(
        access: resp.data['access'] as String,
        refresh: resp.data['refresh'] as String?,
      );
      return true;
    } on DioException catch (e) {
      // Sunucu refresh token'ı AÇIKÇA reddettiyse (süresi dolmuş/geçersiz) oturumu
      // bırak. Ağ/timeout/5xx GEÇİCİ hatalarda token'ları KORU → bir sonraki
      // açılışta (internet/sunucu gelince) oturum sürer, kullanıcı login'e düşmez.
      final code = e.response?.statusCode;
      if (code == 401 || code == 400) {
        await _tokens.clear();
      }
      return false;
    } catch (_) {
      // Beklenmeyen (ör. parse) hata — token'ları koru, oturumu kaybetme.
      return false;
    }
  }
}
