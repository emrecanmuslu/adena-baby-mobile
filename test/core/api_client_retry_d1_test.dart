import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/token_storage.dart';

class _FakeTokens implements TokenStorage {
  String? access = 'OLD';
  String? refresh = 'R';
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
    access = null;
    refresh = null;
  }
}

/// İlk istek 401, retry (yeni token) 500 döner.
class _SeqAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls++;
    final code = calls == 1 ? 401 : 500;
    return ResponseBody.fromString(jsonEncode({'detail': 'x$code'}), code,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// D1 — refresh başarılı, retry 500/zaman aşımıyla düşerse çağıran GERÇEK hatayı
/// görmeli (eskiden orijinal 401 geçiyor, "tekrar giriş yap" deniyordu).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retry 500 → DioException 500 yüzeye çıkar (401 değil)', () async {
    I18n.instance.apply('tr', const {});
    final tokens = _FakeTokens();
    final refreshDio = Dio(BaseOptions(baseUrl: 'https://x.test'));
    DioAdapter(dio: refreshDio).onPost('/auth/refresh',
        (s) => s.reply(200, {'access': 'NEW', 'refresh': 'NEWR'}),
        data: Matchers.any);
    final api = ApiClient(tokens, refreshClient: refreshDio);
    final seq = _SeqAdapter();
    api.dio.httpClientAdapter = seq;

    DioException? thrown;
    try {
      await api.dio.get('/me');
    } on DioException catch (e) {
      thrown = e;
    }
    expect(seq.calls, 2);
    expect(thrown?.response?.statusCode, 500);
    expect(tokens.access, 'NEW');
  });
}
