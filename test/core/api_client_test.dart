import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/token_storage.dart';

/// Yapılandırılabilir sahte TokenStorage. ApiClient yalnız `accessToken`,
/// `refreshToken`, `saveTokens`, `clear` kullanır; bunları gözlemleriz.
/// `hasSession` gerçek davranışı taklit eder (kontrat tutması için).
class _FakeTokens implements TokenStorage {
  String? access;
  String? refresh;

  int saveCount = 0;
  int clearCount = 0;
  String? lastSavedAccess;
  String? lastSavedRefresh;

  _FakeTokens({this.access, this.refresh});

  @override
  Future<String?> get accessToken async => access;

  @override
  Future<String?> get refreshToken async => refresh;

  @override
  Future<bool> get hasSession async => access != null;

  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    saveCount++;
    lastSavedAccess = access;
    lastSavedRefresh = refresh;
    this.access = access;
    if (refresh != null) this.refresh = refresh;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    access = null;
    refresh = null;
  }
}

/// onError 401 yolunda ApiClient, refresh için **kod içinde yeni bir Dio**
/// üretir: `Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl)).post('/auth/refresh')`.
/// Bu Dio dışarı sızdırılmadığı için DioAdapter takılamaz; testte gerçek ağa
/// çıkar ve (ağ olmadığından) bağlantı hatasıyla başarısız olur. Dolayısıyla:
///  - refresh BAŞARILI senaryosunu (retry + saveTokens) doğrulayamayız → skip.
///  - refresh'in BAŞARISIZ olduğu yol (clear + orijinal 401) güvenle test edilir.
void main() {
  // Her test bilinen locale ile başlasın (I18n global singleton).
  setUp(() {
    I18n.instance.apply('tr', const {});
  });

  group('ApiClient onRequest — başlıklar', () {
    test('Accept-Language başlığı I18n.instance.locale değerini yansıtır',
        () async {
      final api = ApiClient(_FakeTokens());
      final adapter = DioAdapter(dio: api.dio);

      I18n.instance.apply('en', const {});

      late RequestOptions captured;
      adapter.onGet('/ping', (server) => server.reply(200, {'ok': true}));

      // Yakalama interceptor'ı: gönderilen başlıkları görmek için en sona ekle.
      api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ));

      await api.dio.get('/ping');
      expect(captured.headers['Accept-Language'], 'en');
    });

    test('locale tr iken Accept-Language tr olur (her istekte taze okunur)',
        () async {
      final api = ApiClient(_FakeTokens());
      final adapter = DioAdapter(dio: api.dio);
      adapter.onGet('/ping', (server) => server.reply(200, {'ok': true}));

      late RequestOptions captured;
      api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ));

      await api.dio.get('/ping');
      expect(captured.headers['Accept-Language'], 'tr');
    });

    test('token varsa Authorization: Bearer <token> eklenir', () async {
      final api = ApiClient(_FakeTokens(access: 'TOK123'));
      final adapter = DioAdapter(dio: api.dio);
      adapter.onGet('/me', (server) => server.reply(200, {'ok': true}));

      late RequestOptions captured;
      api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ));

      await api.dio.get('/me');
      expect(captured.headers['Authorization'], 'Bearer TOK123');
    });

    test('token yoksa Authorization eklenmez', () async {
      final api = ApiClient(_FakeTokens());
      final adapter = DioAdapter(dio: api.dio);
      adapter.onGet('/me', (server) => server.reply(200, {'ok': true}));

      late RequestOptions captured;
      api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ));

      await api.dio.get('/me');
      expect(captured.headers.containsKey('Authorization'), isFalse);
    });

    test('noAuth=true istekte token olsa bile Authorization eklenmez',
        () async {
      final api = ApiClient(_FakeTokens(access: 'TOK123'));
      final adapter = DioAdapter(dio: api.dio);
      adapter.onPost('/auth/login', (server) => server.reply(200, {'ok': true}));

      late RequestOptions captured;
      api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.next(options);
        },
      ));

      await api.dio.post('/auth/login', options: Options(extra: {'noAuth': true}));
      expect(captured.headers.containsKey('Authorization'), isFalse);
      // Accept-Language yine eklenir (noAuth yalnız Authorization'ı etkiler).
      expect(captured.headers['Accept-Language'], 'tr');
    });
  });

  group('ApiClient onError — 401 refresh yolu', () {
    test(
        '401 + refresh token YOK → refresh denenmez, clear çağrılmaz, 401 yüzeye çıkar',
        () async {
      // _refresh(): refreshToken null → false döner, clear() ÇAĞRILMAZ
      // (clear yalnız refresh POST patlayınca catch içinde çağrılır).
      final tokens = _FakeTokens(access: 'OLD');
      final api = ApiClient(tokens);
      final adapter = DioAdapter(dio: api.dio);
      adapter.onGet('/secure', (server) => server.reply(401, {'detail': 'expired'}));

      DioException? thrown;
      try {
        await api.dio.get('/secure');
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.response?.statusCode, 401);
      expect(tokens.saveCount, 0);
      expect(tokens.clearCount, 0, reason: 'refresh token yokken clear çağrılmamalı');
    });

    test(
        '401 + refresh token VAR ama refresh POST başarısız → tokens.clear() ve orijinal 401 yüzeye çıkar',
        () async {
      // _refresh() kod-içi yeni Dio ile /auth/refresh POST atar; test ortamında
      // ağ yok → POST patlar → catch → clear() → false. shouldRetry false olur,
      // orijinal 401 handler.next(e) ile yüzeye çıkar.
      final tokens = _FakeTokens(access: 'OLD', refresh: 'REF');
      final api = ApiClient(tokens);
      final adapter = DioAdapter(dio: api.dio);
      adapter.onGet('/secure', (server) => server.reply(401, {'detail': 'expired'}));

      DioException? thrown;
      try {
        await api.dio.get('/secure');
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.response?.statusCode, 401);
      expect(tokens.clearCount, 1, reason: 'refresh POST patlayınca clear çağrılmalı');
      expect(tokens.saveCount, 0, reason: 'başarısız refresh saveTokens yapmamalı');
    });

    test('noAuth isteğinde 401 → asla retry edilmez (sonsuz döngü yok)',
        () async {
      // noAuth=true → shouldRetry baştan false; _refresh hiç çağrılmaz.
      final tokens = _FakeTokens(access: 'TOK', refresh: 'REF');
      final api = ApiClient(tokens);
      final adapter = DioAdapter(dio: api.dio);
      adapter.onPost('/auth/login',
          (server) => server.reply(401, {'detail': 'bad creds'}));

      DioException? thrown;
      try {
        await api.dio
            .post('/auth/login', options: Options(extra: {'noAuth': true}));
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.response?.statusCode, 401);
      expect(tokens.clearCount, 0);
      expect(tokens.saveCount, 0);
    });

    test('zaten retried=true istekte 401 → tekrar retry edilmez', () async {
      // retried=true → shouldRetry false; _refresh çağrılmaz, sonsuz döngü olmaz.
      final tokens = _FakeTokens(access: 'TOK', refresh: 'REF');
      final api = ApiClient(tokens);
      final adapter = DioAdapter(dio: api.dio);
      adapter.onGet('/secure', (server) => server.reply(401, {'detail': 'still bad'}));

      DioException? thrown;
      try {
        await api.dio.get('/secure', options: Options(extra: {'retried': true}));
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(thrown!.response?.statusCode, 401);
      expect(tokens.clearCount, 0, reason: 'retried istekte refresh hiç denenmemeli');
    });

    test('401 dışı hata (500) → refresh tetiklenmez, clear çağrılmaz', () async {
      final tokens = _FakeTokens(access: 'TOK', refresh: 'REF');
      final api = ApiClient(tokens);
      final adapter = DioAdapter(dio: api.dio);
      adapter.onGet('/secure', (server) => server.reply(500, {'detail': 'boom'}));

      DioException? thrown;
      try {
        await api.dio.get('/secure');
      } on DioException catch (e) {
        thrown = e;
      }

      expect(thrown!.response?.statusCode, 500);
      expect(tokens.clearCount, 0);
      expect(tokens.saveCount, 0);
    });
  });

  group('ApiClient onError — refresh BAŞARILI yolu', () {
    test(
        '401 → refresh başarılı → yeni token ile retried=true tek deneme → saveTokens',
        () async {
      // Enjekte edilen refreshClient'a DioAdapter takıp /auth/refresh'i 200 ile
      // stub'larız; ana dio /secure'u önce 401, retry'da (retried=true) 200 döner.
      final tokens = _FakeTokens(access: 'OLD', refresh: 'REF');

      final refreshDio = Dio(BaseOptions(baseUrl: 'https://test.local'));
      final refreshAdapter = DioAdapter(dio: refreshDio);
      refreshAdapter.onPost(
        '/auth/refresh',
        (server) => server.reply(200, {'access': 'NEWACCESS', 'refresh': 'NEWREF'}),
        // data matcher şart: gövdeli POST'ta stub'a data verilmezse eşleşmez.
        data: {'refresh': 'REF'},
      );

      final api = ApiClient(tokens, refreshClient: refreshDio);
      final adapter = DioAdapter(dio: api.dio);
      // http_mock_adapter stub'ları tüketmez; eşleşenler arasından SONUNCUyu seçer.
      // Bu yüzden iki /secure stub'ını Authorization başlığıyla ayırırız:
      // ilk istek Bearer OLD (→401), refresh sonrası retry Bearer NEWACCESS (→200).
      adapter
        ..onGet(
          '/secure',
          (server) => server.reply(401, {'detail': 'expired'}),
          headers: {'Authorization': 'Bearer OLD'},
        )
        ..onGet(
          '/secure',
          (server) => server.reply(200, {'ok': true}),
          headers: {'Authorization': 'Bearer NEWACCESS'},
        );

      // Retry edilen isteğin başlıklarını/extra'sını yakalamak için en sona ekle.
      RequestOptions? retryCaptured;
      api.dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.extra['retried'] == true) retryCaptured = options;
          handler.next(options);
        },
      ));

      final resp = await api.dio.get('/secure');

      // Sonuç başarılı 200.
      expect(resp.statusCode, 200);
      expect(resp.data, {'ok': true});

      // Yeni token'lar kaydedildi.
      expect(tokens.saveCount, 1);
      expect(tokens.lastSavedAccess, 'NEWACCESS');
      expect(tokens.lastSavedRefresh, 'NEWREF');
      expect(tokens.clearCount, 0, reason: 'başarılı refresh clear çağırmamalı');

      // Retry edilen istek yeni Bearer + extra['retried']=true taşımalı.
      expect(retryCaptured, isNotNull);
      expect(retryCaptured!.extra['retried'], true);
      expect(retryCaptured!.headers['Authorization'], 'Bearer NEWACCESS');
    });
  });
}
