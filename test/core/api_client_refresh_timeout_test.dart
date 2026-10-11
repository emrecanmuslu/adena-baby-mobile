import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/token_storage.dart';

/// O2 (BULGULAR.md): refresh Dio'su zaman aşımsızdı; ölü ağda /auth/refresh
/// dakikalarca askıda kalıyor, tek-uçuş kilidi yüzünden 401 alan TÜM istekler
/// onu bekliyordu. Ayrıca geçici refresh hatasında bekleyenler 401 ("oturum
/// gerekli") ile düşüyordu — ağ hatası olarak düşmeli.
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

/// IOHttpClientAdapter'ı taklit eden sahte adaptör: Dio 5'te connect/receive
/// zaman aşımları adaptör İÇİNDE uygulanır. `hang=true` iken istek
/// `options.connectTimeout` kadar bekleyip connectionTimeout fırlatır (zaman
/// aşımı yoksa SONSUZA kadar askıda kalır — eski üretim davranışı);
/// `hang=false` iken 200 + yeni token döner.
class _RefreshAdapter implements HttpClientAdapter {
  bool hang = true;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    if (hang) {
      final t = options.connectTimeout;
      if (t == null || t == Duration.zero) {
        await Completer<void>().future; // zaman aşımsız → askıda
      }
      await Future<void>.delayed(t!);
      throw DioException.connectionTimeout(timeout: t, requestOptions: options);
    }
    return ResponseBody.fromString(
        '{"access":"NEW","refresh":"NEWR"}', 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => I18n.instance.apply('tr', const {}));

  /// Refresh Dio'su: küçük zaman aşımı + sahte adaptör.
  Dio refreshDio(_RefreshAdapter a) => Dio(BaseOptions(
        baseUrl: 'https://test.local',
        connectTimeout: const Duration(milliseconds: 100),
        receiveTimeout: const Duration(milliseconds: 100),
      ))
        ..httpClientAdapter = a;

  void stub401(DioAdapter adapter, String path) => adapter.onGet(
      path, (s) => s.reply(401, {'detail': 'expired'}),
      headers: {'Authorization': 'Bearer OLD'});

  group('O2 — askıda kalan refresh', () {
    test('(a)+(b) refresh zaman aşımı: bekleyen 3 istek kısa sürede AĞ hatasıyla düşer, token silinmez',
        () async {
      final tokens = _FakeTokens(access: 'OLD', refresh: 'REF');
      final ra = _RefreshAdapter();
      final api = ApiClient(tokens, refreshClient: refreshDio(ra));
      final adapter = DioAdapter(dio: api.dio);
      for (final p in ['/a', '/b', '/c']) {
        stub401(adapter, p);
      }

      final sw = Stopwatch()..start();
      final results = await Future.wait([
        for (final p in ['/a', '/b', '/c'])
          api.dio.get(p).then<Object>((r) => r, onError: (Object e) => e),
      ]).timeout(const Duration(seconds: 5));
      sw.stop();

      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      for (final r in results) {
        expect(r, isA<DioException>());
        final e = r as DioException;
        expect(e.response?.statusCode, isNull,
            reason: 'geçici refresh hatası 401 olarak yüzeye çıkmamalı');
        expect(
            e.type,
            anyOf(DioExceptionType.connectionTimeout,
                DioExceptionType.connectionError, DioExceptionType.receiveTimeout),
            reason: 'ağ hatası tipi');
      }
      expect(ra.calls, 1, reason: 'tek-uçuş: üç 401 tek refresh');
      expect(tokens.clearCount, 0);
      expect(tokens.access, 'OLD');
    });

    test('(c) kilit serbest kalır: sonraki 401 yeni refresh başlatır ve başarır', () async {
      final tokens = _FakeTokens(access: 'OLD', refresh: 'REF');
      final ra = _RefreshAdapter();
      final api = ApiClient(tokens, refreshClient: refreshDio(ra));
      final adapter = DioAdapter(dio: api.dio);
      stub401(adapter, '/x');
      adapter
        ..onGet('/y', (s) => s.reply(401, {'detail': 'expired'}),
            headers: {'Authorization': 'Bearer OLD'})
        ..onGet('/y', (s) => s.reply(200, {'ok': true}),
            headers: {'Authorization': 'Bearer NEW'});

      await api.dio.get('/x').then<void>((_) {}, onError: (_) {});
      expect(ra.calls, 1);

      ra.hang = false; // ağ geldi
      final r = await api.dio.get('/y');
      expect(r.statusCode, 200);
      expect(ra.calls, 2, reason: 'kilit açık olmalı, yeni tur');
      expect(tokens.access, 'NEW');
    });

    test('(d) regresyon: refresh 401 → token silinir, orijinal 401 yüzeye çıkar', () async {
      final tokens = _FakeTokens(access: 'OLD', refresh: 'DEAD');
      final rd = Dio(BaseOptions(baseUrl: 'https://test.local'));
      DioAdapter(dio: rd).onPost('/auth/refresh',
          (s) => s.reply(401, {'detail': 'token_not_valid'}),
          data: {'refresh': 'DEAD'});
      final api = ApiClient(tokens, refreshClient: rd);
      final adapter = DioAdapter(dio: api.dio);
      stub401(adapter, '/secure');

      DioException? thrown;
      try {
        await api.dio.get('/secure');
      } on DioException catch (e) {
        thrown = e;
      }
      expect(thrown!.response?.statusCode, 401);
      expect(tokens.clearCount, 1);
    });
  });

  // ───────── YENİ API: üretim refresh Dio'sunun zaman aşımı sabitleri ─────────
  group('O2 — üretim refresh istemcisi', () {
    test('connect/receive zaman aşımları ayarlı (8 s / 10 s)', () {
      final api = ApiClient(_FakeTokens());
      final o = api.debugRefreshClient.options;
      expect(o.connectTimeout, ApiClient.refreshConnectTimeout);
      expect(o.receiveTimeout, ApiClient.refreshReceiveTimeout);
      expect(ApiClient.refreshConnectTimeout, const Duration(seconds: 8));
      expect(ApiClient.refreshReceiveTimeout, const Duration(seconds: 10));
    });
  });
}
