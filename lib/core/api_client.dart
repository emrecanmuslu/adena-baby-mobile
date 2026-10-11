import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'config.dart';
import 'i18n.dart';
import 'session_end.dart';
import 'token_storage.dart';

/// Dio tabanlı API istemcisi. JWT ekler ve 401'de otomatik token yeniler.
class ApiClient {
  final Dio dio;
  final TokenStorage _tokens;

  /// Refresh isteğinin atıldığı ayrı Dio. Varsayılan: aynı baseUrl ile taze bir
  /// Dio (üretim davranışı değişmez). Test, buraya DioAdapter'lı bir Dio
  /// enjekte ederek /auth/refresh'i stub'layabilir.
  final Dio _refreshClient;

  /// `/auth/refresh` zaman aşımları (O2). Refresh kısa bir POST'tur; ana Dio'nun
  /// 15/20 sn'sinden daha sıkı tutulur ki ölü/yalancı ağda tek-uçuş kilidini
  /// bekleyen tüm istekler dakikalarca askıda kalmasın. Toplam en kötü durum
  /// 8+10 = 18 sn — FCM arka plan turunun 20 sn bütçesinin (bgPushTimeout)
  /// altında; iOS BGTask (25 sn) için de yeterli.
  static const refreshConnectTimeout = Duration(seconds: 8);
  static const refreshReceiveTimeout = Duration(seconds: 10);

  ApiClient(this._tokens, {Dio? refreshClient})
      : dio = Dio(BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          contentType: 'application/json',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        )),
        _refreshClient = refreshClient ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: refreshConnectTimeout,
              receiveTimeout: refreshReceiveTimeout,
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
        if (!shouldRetry) return handler.next(e);
        final result = await _refreshIfNeeded(e.requestOptions);
        switch (result) {
          case RefreshResult.ok:
            final opts = e.requestOptions..extra['retried'] = true;
            final token = await _tokens.accessToken;
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              return handler.resolve(await dio.fetch(opts));
            } on DioException catch (re) {
              // D1: retry'ın GERÇEK hatası (500/zaman aşımı) yüzeye çıksın —
              // orijinal 401 geçerse çağıran "tekrar giriş yap" görürdü.
              if (re.response?.statusCode != 401) return handler.reject(re);
              return handler.next(e);
            } catch (_) {
              return handler.next(e); // beklenmeyen → orijinal hata
            }
          case RefreshResult.transient:
            // O2: refresh ağ/zaman aşımı/5xx ile düştü → bekleyen istek AUTH
            // hatası (401) değil AĞ hatası olarak düşsün: token duruyor, oturum
            // sürüyor; "oturum düştü" yolu (O1) tetiklenmemeli, kullanıcı
            // "sunucuya ulaşılamadı" görmeli.
            return handler.reject(DioException(
              requestOptions: e.requestOptions,
              type: _lastTransientType ?? DioExceptionType.connectionError,
              error: 'refresh_transient',
              message: 'Token yenileme geçici olarak başarısız (ağ/zaman aşımı)',
            ));
          case RefreshResult.rejected:
            return handler.next(e); // gerçek red: 401 yüzeye çıkar (token silindi)
        }
      },
    ));
  }

  /// Yalnız test: üretim refresh Dio'sunun seçenekleri (zaman aşımı doğrulaması).
  @visibleForTesting
  Dio get debugRefreshClient => _refreshClient;

  /// Yerelde oturum (access token) var mı — yetkisiz istek atmamak için.
  Future<bool> get hasSession => _tokens.hasSession;

  /// Sunucu oturumu AÇIKÇA reddettiğinde (refresh 401/400 → token silindi)
  /// çağrılır (O1). AuthController ön planda atar/sıfırlar; bg'de atanmaz.
  /// Çağrıdan ÖNCE neden prefs'e yazılır ([SessionEndCache]) — başka isolate ya
  /// da süreç ön planda bir kez gösterebilsin.
  void Function(SessionEndReason reason)? onSessionRejected;

  /// Devam eden refresh turu — **tek-uçuş (single-flight) kilidi**.
  /// Access token'ın ömrü dolduğunda uygulama aynı anda onlarca istek atar
  /// (açılış turu: babies + sync + content + me...); hepsi birden 401 alır.
  /// Kilit olmadan her biri ayrı ayrı `/auth/refresh` çağırıyordu: sunucu
  /// loglarında aynı saniyede 3-4 refresh, rotasyon yarışı ve yarışı kaybeden
  /// isteğin (çoğu kez `/sync`) sessizce düşmesi → sahte "Senkron sorunu".
  Future<RefreshResult>? _refreshing;

  /// Son geçici refresh hatasının Dio tipi (bekleyenlere aynı tipte yansıtılır).
  DioExceptionType? _lastTransientType;

  /// 401 alan istek için token tazeleme kararı:
  /// - Bu arada BAŞKA bir istek token'ı yenilediyse (istekteki Bearer artık
  ///   güncel değilse) refresh'e hiç gerek yok → doğrudan retry.
  /// - Yenilenmediyse: turu başlat ya da devam eden tura katıl (tek-uçuş).
  Future<RefreshResult> _refreshIfNeeded(RequestOptions failed) async {
    final current = await _tokens.accessToken;
    if (current != null && failed.headers['Authorization'] != 'Bearer $current') {
      return RefreshResult.ok; // token değişmiş → yeni token'la bir kez daha dene
    }
    final inflight = _refreshing;
    if (inflight != null) return inflight;
    final run = _runRefresh();
    _refreshing = run;
    return run;
  }

  /// Tek-uçuş turu: kilit HER durumda (başarı/red/geçici/beklenmeyen) serbest
  /// kalır → sonraki 401 yeni tur açabilir.
  Future<RefreshResult> _runRefresh() async {
    try {
      return await _refresh();
    } finally {
      _refreshing = null;
    }
  }

  /// Refresh token ile yeni access (ve dönerse refresh) alır.
  Future<RefreshResult> _refresh() async {
    final refresh = await _tokens.refreshToken;
    if (refresh == null) {
      // Oturum HİÇ yoksa (çıkış/zorunlu çıkış sonrası geç istek, onTokenRefresh
      // POST'u) bitirilecek oturum da yok: prefs'teki neden EZİLMEZ, kanca yok.
      // Access var ama refresh yoksa (bozuk depo) → bildir; temizliği
      // AuthController.sessionExpired yapar (clear burada çağrılmaz — eski kontrat).
      if (await _tokens.hasSession) await _rejected(SessionEndReason.unknown);
      return RefreshResult.rejected;
    }
    try {
      final resp = await _refreshClient
          .post('/auth/refresh', data: {'refresh': refresh});
      await _tokens.saveTokens(
        access: resp.data['access'] as String,
        refresh: resp.data['refresh'] as String?,
      );
      return RefreshResult.ok;
    } on DioException catch (e) {
      // Sunucu refresh token'ı AÇIKÇA reddettiyse (süresi dolmuş/geçersiz) oturumu
      // bırak. Ağ/timeout/5xx GEÇİCİ hatalarda token'ları KORU → bir sonraki
      // açılışta (internet/sunucu gelince) oturum sürer, kullanıcı login'e düşmez.
      final code = e.response?.statusCode;
      if (code == 401 || code == 400) {
        await _tokens.clear();
        await _rejected(sessionEndReasonFromBody(e.response?.data));
        return RefreshResult.rejected;
      }
      _lastTransientType = e.type;
      return RefreshResult.transient;
    } catch (_) {
      // Beklenmeyen (ör. parse) hata — token'ları koru, oturumu kaybetme.
      _lastTransientType = DioExceptionType.unknown;
      return RefreshResult.transient;
    }
  }

  Future<void> _rejected(SessionEndReason reason) async {
    await SessionEndCache.write(reason);
    try {
      onSessionRejected?.call(reason);
    } catch (_) {}
  }
}

/// `/auth/refresh` turunun sonucu.
enum RefreshResult {
  /// Yeni token alındı (ya da bu arada başka istek yeniledi) → retry.
  ok,

  /// Sunucu refresh token'ı AÇIKÇA reddetti (401/400) → token'lar silindi,
  /// orijinal 401 yüzeye çıkar (oturum düştü — O1 burada ele alır).
  rejected,

  /// Ağ / zaman aşımı / 5xx / beklenmeyen → token KORUNUR, bekleyen istekler
  /// AĞ hatasıyla düşer, sonraki 401 yeni tur açar.
  transient,
}
