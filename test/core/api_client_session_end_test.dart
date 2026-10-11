import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/session_end.dart';
import 'package:adena_baby/core/token_storage.dart';

class _FakeTokens implements TokenStorage {
  String? access;
  String? refresh;
  int clearCount = 0;
  _FakeTokens({this.access, this.refresh});
  @override
  Future<String?> get accessToken async => access;
  @override
  Future<String?> get refreshToken async => refresh;
  @override
  Future<bool> get hasSession async => access != null;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
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

/// O1 — refresh reddi sınıflandırması + `onSessionRejected` kancası + prefs.
/// Kural: gövde `code == "session_superseded"` → superseded;
/// `code == "token_not_valid"` → expired; DİĞER HER ŞEY (kodsuz 401/400 dahil)
/// → unknown. `detail` METNİYLE EŞLEME YAPILMAZ. Geçici hatada kanca yok.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeTokens tokens;
  late Dio refreshDio;
  late DioAdapter refreshAdapter;
  late ApiClient api;
  late DioAdapter mainAdapter;
  final received = <SessionEndReason>[];

  setUp(() {
    I18n.instance.apply('tr', const {});
    SharedPreferences.setMockInitialValues({});
    received.clear();
    tokens = _FakeTokens(access: 'OLD', refresh: 'R');
    refreshDio = Dio(BaseOptions(baseUrl: 'https://x.test'));
    refreshAdapter = DioAdapter(dio: refreshDio);
    api = ApiClient(tokens, refreshClient: refreshDio);
    api.onSessionRejected = received.add;
    mainAdapter = DioAdapter(dio: api.dio);
    mainAdapter.onGet('/me', (s) => s.reply(401, {'detail': 'x'}));
  });

  Future<DioException> call() async {
    try {
      await api.dio.get('/me');
      fail('401 bekleniyordu');
    } on DioException catch (e) {
      return e;
    }
  }

  Future<String?> prefsReason() async =>
      (await SharedPreferences.getInstance()).getString(SessionEndCache.key);

  group('sessionEndReasonFromBody', () {
    test('yalnız code alanına bakar; detail metni eşlenmez', () {
      expect(sessionEndReasonFromBody({'code': 'session_superseded'}),
          SessionEndReason.superseded);
      expect(
          sessionEndReasonFromBody({'code': 'token_not_valid', 'detail': 'z'}),
          SessionEndReason.expired);
      expect(
          sessionEndReasonFromBody(
              {'detail': 'Hesabınıza başka bir cihazdan giriş yapıldı.'}),
          SessionEndReason.unknown,
          reason: 'kodsuz gövde superseded SAYILMAZ (metin dil bağımlı)');
      expect(sessionEndReasonFromBody({'code': 'something_else'}),
          SessionEndReason.unknown);
      expect(sessionEndReasonFromBody('html'), SessionEndReason.unknown);
      expect(sessionEndReasonFromBody(null), SessionEndReason.unknown);
    });
  });

  group('ApiClient refresh reddi → onSessionRejected + prefs', () {
    test(
        '401 + code=session_superseded → superseded, token silindi, prefs yazıldı',
        () async {
      refreshAdapter.onPost('/auth/refresh',
          (s) => s.reply(401, {'detail': 'd', 'code': 'session_superseded'}),
          data: Matchers.any);
      final e = await call();
      expect(e.response?.statusCode, 401);
      expect(received, [SessionEndReason.superseded]);
      expect(tokens.clearCount, 1);
      expect(await prefsReason(), 'superseded');
    });

    test('401 + code=token_not_valid → expired', () async {
      refreshAdapter.onPost('/auth/refresh',
          (s) => s.reply(401, {'detail': 'd', 'code': 'token_not_valid'}),
          data: Matchers.any);
      await call();
      expect(received, [SessionEndReason.expired]);
      expect(await prefsReason(), 'expired');
    });

    test('kodsuz 401 (yalnız detail) ve 400 → unknown', () async {
      refreshAdapter.onPost('/auth/refresh',
          (s) => s.reply(401, {'detail': 'Başka cihazdan giriş yapıldı.'}),
          data: Matchers.any);
      await call();
      expect(received, [SessionEndReason.unknown]);

      received.clear();
      tokens.access = 'OLD2';
      tokens.refresh = 'R2';
      refreshAdapter.onPost(
          '/auth/refresh',
          (s) => s.reply(400, {
                'refresh': ['This field is required.']
              }),
          data: Matchers.any);
      await call();
      expect(received, [SessionEndReason.unknown]);
      expect(await prefsReason(), 'unknown');
    });

    test(
        'oturum HİÇ yokken 401 (ör. çıkış sonrası geç istek / onTokenRefresh POST) → prefs nedeni EZİLMEZ, kanca çağrılmaz',
        () async {
      // sessionExpired(superseded) sonrası: token'lar silindi, neden prefs'te.
      tokens.access = null;
      tokens.refresh = null;
      await SessionEndCache.write(SessionEndReason.superseded);

      await call();

      expect(await prefsReason(), 'superseded',
          reason: 'banner "başka cihazdan giriş" yerine genel metne düşmemeli');
      expect(received, isEmpty);
      expect(tokens.clearCount, 0);
    });

    test('access var ama refresh yok (bozuk depo) → unknown kancası (temizlik controller tarafinda)',
        () async {
      tokens.refresh = null;
      await call();
      expect(received, [SessionEndReason.unknown]);
      expect(tokens.clearCount, 0); // eski kontrat: ApiClient burada clear etmez
      expect(await prefsReason(), 'unknown');
    });

    test(
        'geçici hata (5xx / bağlantı) → kanca ÇAĞRILMAZ, prefs yazılmaz, token durur',
        () async {
      refreshAdapter.onPost('/auth/refresh', (s) => s.reply(503, {'e': 1}),
          data: Matchers.any);
      final e1 = await call();
      expect(e1.error, 'refresh_transient');

      refreshAdapter.onPost(
          '/auth/refresh',
          (s) => s.throws(
              0,
              DioException.connectionError(
                  requestOptions: RequestOptions(path: '/auth/refresh'),
                  reason: 'down')),
          data: Matchers.any);
      await call();

      expect(received, isEmpty);
      expect(tokens.clearCount, 0);
      expect(tokens.access, 'OLD');
      expect(await prefsReason(), isNull);
    });

    test('kanca atanmamışsa (bg isolate) yine prefs yazılır, hata yok',
        () async {
      api.onSessionRejected = null;
      refreshAdapter.onPost('/auth/refresh',
          (s) => s.reply(401, {'code': 'session_superseded'}),
          data: Matchers.any);
      await call();
      expect(await prefsReason(), 'superseded');
    });
  });
}
