import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/push_service.dart';
import 'package:adena_baby/core/token_storage.dart';

class _FakeTokens implements TokenStorage {
  String? access;
  _FakeTokens({this.access});
  @override
  Future<String?> get accessToken async => access;
  @override
  Future<String?> get refreshToken async => null;
  @override
  Future<bool> get hasSession async => access != null;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {
    access = null;
  }
}

/// O1 artığı — FCM cihaz kaydı: `_lastRegistered` yalnız BAŞARILI POST'ta
/// işaretlenir; oturum yokken istek hiç atılmaz. Aksi hâlde zorunlu çıkış →
/// deleteToken → yeni token oturumsuz gelir → "kayıtlı" sanılır → yeniden
/// girişte cihaz hiç kaydolmaz (aile push'u ölü).
void main() {
  late _FakeTokens tokens;
  late ApiClient api;
  late DioAdapter adapter;
  var posts = 0;

  setUp(() {
    PushService.instance.resetForTests();
    posts = 0;
    tokens = _FakeTokens(access: 'ACC');
    api = ApiClient(tokens);
    adapter = DioAdapter(dio: api.dio);
    // Not: onPost geri çağrısı KAYIT anında çalışır → sayaç interceptor'da.
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      posts++;
      h.next(o);
    }));
    adapter.onPost('/me/devices', (s) => s.reply(201, {'ok': true}),
        data: Matchers.any);
  });

  test('oturum yok → POST atılmaz, lastRegistered boş kalır', () async {
    tokens.access = null;
    final ok = await PushService.instance.postToken(api, 'T1');
    expect(ok, isFalse);
    expect(posts, 0);
    expect(PushService.instance.lastRegistered, isNull);
  });

  test('oturum var + 201 → işaretlenir', () async {
    final ok = await PushService.instance.postToken(api, 'T1');
    expect(ok, isTrue);
    expect(posts, 1);
    expect(PushService.instance.lastRegistered, 'T1');
  });

  test('POST düşerse (5xx) işaretlenmez → sonraki deneme yeniden gönderir',
      () async {
    adapter.onPost('/me/devices', (s) => s.reply(503, {}), data: Matchers.any);
    final ok = await PushService.instance.postToken(api, 'T2');
    expect(ok, isFalse);
    expect(PushService.instance.lastRegistered, isNull);
  });

  test(
      'senaryo: zorunlu çıkış sonrası oturumsuz gelen yeni token, yeniden girişte kaydolur',
      () async {
    await PushService.instance.postToken(api, 'OLD');
    expect(PushService.instance.lastRegistered, 'OLD');

    tokens.access = null; // sessionExpired → token silindi, deleteToken → NEW
    await PushService.instance.postToken(api, 'NEW');
    expect(PushService.instance.lastRegistered, 'OLD',
        reason: 'oturumsuz gelen token kayıtlı sayılmamalı');

    tokens.access = 'ACC2'; // yeniden giriş → registerToken NEW != OLD → POST
    expect('NEW' != PushService.instance.lastRegistered, isTrue);
    await PushService.instance.postToken(api, 'NEW');
    expect(posts, 2);
    expect(PushService.instance.lastRegistered, 'NEW');
  });
}
