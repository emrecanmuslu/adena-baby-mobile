import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/sharing_repository.dart';

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'fake-access';
  @override
  Future<String?> get refreshToken async => 'fake-refresh';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

// NOT (export/share): Görev tanımı SharingRepository için "export (PDF/CSV) +
// share_plus" istiyor; ancak `lib/data/sharing_repository.dart` SADECE
// salt-okunur `activity()` ucunu içerir. Veri dışa aktarımı ayrı bir UI
// fonksiyonunda yaşar: `lib/features/settings/data_export.dart#exportUserData`,
// ki o WidgetRef + BuildContext + path_provider + SharePlus.instance.share'e
// bağlıdır (repository değil, JSON üretir — PDF/CSV değil). Bu unit katmanda
// test edilemez; gerçek API-destekli export ucu ise AuthRepository.exportData()
// (GET /auth/me/export). Bu dosya gerçek SharingRepository'yi (activity) test eder.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late SharingRepository repo;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    repo = SharingRepository(api);
  });

  Map<String, dynamic> eventJson({String id = 'e1', String action = 'created_feed'}) =>
      {
        'id': id,
        'actor': {
          'id': 'u1',
          'email': 'a@b.com',
          'name': 'Anne',
          'avatar_color': '#FF8A7A',
        },
        'action': action,
        'record_ref': 'r1',
        'ts': '2026-06-18T09:00:00Z',
      };

  test('activity(babyId) since yokken queryParameters göndermez + parse', () async {
    adapter.onGet(
      '/babies/b1/activity',
      (s) => s.reply(200, [
        eventJson(id: 'e1', action: 'created_feed'),
        eventJson(id: 'e2', action: 'started_sleep'),
      ]),
    );

    final list = await repo.activity('b1');
    expect(list, hasLength(2));
    expect(list.first.id, 'e1');
    expect(list.first.action, 'created_feed');
    expect(list.first.actor?.name, 'Anne');
    expect(list.first.recordRef, 'r1');
  });

  test('activity since verilince UTC ISO8601 sorgu parametresi ekler', () async {
    final since = DateTime.utc(2026, 6, 18, 8, 30);
    adapter.onGet(
      '/babies/b1/activity',
      (s) => s.reply(200, <dynamic>[]),
      queryParameters: {'since': since.toIso8601String()},
    );

    final list = await repo.activity('b1', since: since);
    expect(list, isEmpty);
  });

  test('activity local saatli since → UTC çevrilip gönderilir', () async {
    final sinceLocal = DateTime(2026, 6, 18, 12, 0);
    adapter.onGet(
      '/babies/b1/activity',
      (s) => s.reply(200, <dynamic>[]),
      queryParameters: {'since': sinceLocal.toUtc().toIso8601String()},
    );

    final list = await repo.activity('b1', since: sinceLocal);
    expect(list, isEmpty);
  });

  test('actor null (SET_NULL) olayını parse eder', () async {
    adapter.onGet(
      '/babies/b1/activity',
      (s) => s.reply(200, [
        {
          'id': 'e9',
          'actor': null,
          'action': 'created_diaper',
          'ts': '2026-06-18T10:00:00Z',
        }
      ]),
    );

    final list = await repo.activity('b1');
    expect(list, hasLength(1));
    expect(list.first.actor, isNull);
    expect(list.first.action, 'created_diaper');
    expect(list.first.recordRef, isNull);
  });
}
