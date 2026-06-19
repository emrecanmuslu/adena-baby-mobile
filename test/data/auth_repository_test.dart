import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/auth_repository.dart';
import 'package:adena_baby/models/user.dart';

/// In-memory [TokenStorage] stand-in that captures save/clear calls so we can
/// assert the repository persisted exactly the tokens the server returned.
class _FakeTokens implements TokenStorage {
  String? access;
  String? refresh;
  int saveCount = 0;
  int clearCount = 0;
  bool refreshNull = false;

  @override
  Future<void> saveTokens({required String access, String? refresh}) async {
    saveCount++;
    this.access = access;
    // Mirror the real impl: a null refresh does NOT overwrite the stored one.
    if (refresh != null) this.refresh = refresh;
  }

  @override
  Future<String?> get accessToken async => access;

  @override
  Future<String?> get refreshToken async => refreshNull ? null : refresh;

  @override
  Future<bool> get hasSession async => access != null;

  @override
  Future<void> clear() async {
    clearCount++;
    access = null;
    refresh = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeTokens tokens;
  late ApiClient api;
  late DioAdapter adapter;
  late AuthRepository repo;

  setUp(() {
    tokens = _FakeTokens();
    api = ApiClient(tokens);
    adapter = DioAdapter(dio: api.dio);
    repo = AuthRepository(api, tokens);
  });

  Map<String, dynamic> userJson({String id = 'u1'}) => {
        'id': id,
        'email': 'a@b.com',
        'name': 'Ada',
        'avatar_color': '#FF8A7A',
        'created_at': '2026-01-01T00:00:00Z',
      };

  group('register', () {
    test('parses User, attaches consent, saves both tokens, sends payload + noAuth',
        () async {
      adapter.onPost(
        '/auth/register',
        (s) => s.reply(200, {
          'user': userJson(),
          'access': 'ACC',
          'refresh': 'REF',
          'consent_required': true,
        }),
        data: {
          'email': 'a@b.com',
          'password': 'pw',
          'name': 'Ada',
          'accepted_legal': true,
          'age_confirmed': true,
        },
      );

      final user = await repo.register(email: 'a@b.com', password: 'pw', name: 'Ada');

      expect(user, isA<User>());
      expect(user.id, 'u1');
      expect(user.email, 'a@b.com');
      expect(user.consentRequired, isTrue);
      expect(tokens.access, 'ACC');
      expect(tokens.refresh, 'REF');
      expect(tokens.saveCount, 1);
    });

    test('register request omits Authorization header (noAuth)', () async {
      tokens.access = 'EXISTING';
      String? authHeader = 'unset';
      adapter.onPost(
        '/auth/register',
        (s) => s.reply(200, {
          'user': userJson(),
          'access': 'ACC',
          'refresh': 'REF',
        }),
        data: Matchers.any,
      );
      api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        if (o.path == '/auth/register') {
          authHeader = o.headers['Authorization'] as String?;
        }
        h.next(o);
      }));

      await repo.register(email: 'a@b.com', password: 'pw', name: 'Ada');
      expect(authHeader, isNull);
    });
  });

  group('login', () {
    test('parses User and saves tokens', () async {
      adapter.onPost(
        '/auth/login',
        (s) => s.reply(200, {
          'user': userJson(),
          'access': 'L_ACC',
          'refresh': 'L_REF',
          'consent_required': false,
        }),
        data: {'email': 'a@b.com', 'password': 'pw'},
      );

      final user = await repo.login(email: 'a@b.com', password: 'pw');
      expect(user.id, 'u1');
      expect(user.consentRequired, isFalse);
      expect(tokens.access, 'L_ACC');
      expect(tokens.refresh, 'L_REF');
    });

    test('login keeps old refresh when server omits it (refresh null)', () async {
      tokens.refresh = 'OLD_REF';
      adapter.onPost(
        '/auth/login',
        (s) => s.reply(200, {
          'user': userJson(),
          'access': 'NEW_ACC',
          // no refresh key
        }),
        data: Matchers.any,
      );

      await repo.login(email: 'a@b.com', password: 'pw');
      expect(tokens.access, 'NEW_ACC');
      expect(tokens.refresh, 'OLD_REF');
    });

    test('error response surfaces as DioException', () async {
      adapter.onPost(
        '/auth/login',
        (s) => s.reply(401, {'detail': 'invalid'}),
        data: Matchers.any,
      );

      expect(
        () => repo.login(email: 'a@b.com', password: 'wrong'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('social', () {
    test('sends provider + id_token, parses User, saves tokens', () async {
      adapter.onPost(
        '/auth/social',
        (s) => s.reply(200, {
          'user': userJson(),
          'access': 'S_ACC',
          'refresh': 'S_REF',
          'consent_required': true,
        }),
        data: {'provider': 'google', 'id_token': 'tok123'},
      );

      final user = await repo.social(provider: 'google', idToken: 'tok123');
      expect(user.consentRequired, isTrue);
      expect(tokens.access, 'S_ACC');
      expect(tokens.refresh, 'S_REF');
    });
  });

  group('me', () {
    test('parses nested user and consent_required flag', () async {
      adapter.onGet(
        '/auth/me',
        (s) => s.reply(200, {
          'user': userJson(id: 'me1'),
          'consent_required': true,
        }),
      );

      final user = await repo.me();
      expect(user.id, 'me1');
      expect(user.consentRequired, isTrue);
    });

    test('defaults consent_required to false when absent', () async {
      adapter.onGet(
        '/auth/me',
        (s) => s.reply(200, {'user': userJson(id: 'me2')}),
      );

      final user = await repo.me();
      expect(user.consentRequired, isFalse);
    });
  });

  group('updateName', () {
    test('PATCHes name and parses returned User (flat, no nesting)', () async {
      adapter.onPatch(
        '/auth/me',
        (s) => s.reply(200, {
          'id': 'u9',
          'email': 'a@b.com',
          'name': 'Yeni Ad',
        }),
        data: {'name': 'Yeni Ad'},
      );

      final user = await repo.updateName('Yeni Ad');
      expect(user.id, 'u9');
      expect(user.name, 'Yeni Ad');
    });
  });

  group('settings', () {
    test('returns server map', () async {
      adapter.onGet(
        '/auth/me/settings',
        (s) => s.reply(200, {'theme': 'dark', 'units': 'metric'}),
      );

      final s = await repo.settings();
      expect(s['theme'], 'dark');
      expect(s['units'], 'metric');
    });

    test('updateSettings PATCHes the given fields', () async {
      adapter.onPatch(
        '/auth/me/settings',
        (s) => s.reply(200, {'ok': true}),
        data: {'theme': 'light'},
      );

      await expectLater(repo.updateSettings({'theme': 'light'}), completes);
    });
  });

  group('recordConsent', () {
    test('POSTs accepted_legal/age_confirmed/source=gate', () async {
      adapter.onPost(
        '/auth/consent',
        (s) => s.reply(200, {'ok': true}),
        data: {'accepted_legal': true, 'age_confirmed': true, 'source': 'gate'},
      );

      await expectLater(repo.recordConsent(), completes);
    });
  });

  group('deleteAccount', () {
    test('DELETEs and clears tokens', () async {
      tokens.access = 'ACC';
      tokens.refresh = 'REF';
      adapter.onDelete('/auth/me', (s) => s.reply(204, null));

      await repo.deleteAccount();
      expect(tokens.clearCount, 1);
      expect(tokens.access, isNull);
    });
  });

  group('exportData', () {
    test('returns server map verbatim', () async {
      adapter.onGet(
        '/auth/me/export',
        (s) => s.reply(200, {
          'photos': ['p1'],
          'records': 3,
        }),
      );

      final data = await repo.exportData();
      expect(data['photos'], ['p1']);
      expect(data['records'], 3);
    });
  });

  group('logout', () {
    test('POSTs refresh then clears tokens', () async {
      tokens.access = 'ACC';
      tokens.refresh = 'REF';
      adapter.onPost(
        '/auth/logout',
        (s) => s.reply(200, {'ok': true}),
        data: {'refresh': 'REF'},
      );

      await repo.logout();
      expect(tokens.clearCount, 1);
      expect(tokens.access, isNull);
      expect(tokens.refresh, isNull);
    });

    test('clears tokens even if logout request fails', () async {
      tokens.access = 'ACC';
      tokens.refresh = 'REF';
      adapter.onPost(
        '/auth/logout',
        (s) => s.reply(500, {'detail': 'boom'}),
        data: Matchers.any,
      );

      await repo.logout();
      expect(tokens.clearCount, 1);
      expect(tokens.access, isNull);
    });
  });
}
