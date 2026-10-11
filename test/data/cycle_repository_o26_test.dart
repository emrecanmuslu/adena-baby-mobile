import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/models/cycle.dart';

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'a';
  @override
  Future<String?> get refreshToken async => 'r';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

/// O26 kalanı (TASARIM §8 8b): bulut açıkken `patchSettings`/`saveEntry`/
/// `deleteEntry` (ve D33 `_maintainAnchorAfterRemoval`'ın PATCH'i) satır içinde
/// ağı BEKLEMEZ — dirty yazılır, `onChanged` tetiklenir, gönderim `syncIfCloud`
/// turunda yapılır. Ekran anında döner (önce: 15-35 sn spinner, O8'i tetikler).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late AppDatabase db;
  late CycleRepository repo;
  final requests = <String>[];
  var changed = 0;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      requests.add('${o.method} ${o.path}');
      h.next(o);
    }));
    requests.clear();
    changed = 0;
    db = AppDatabase(NativeDatabase.memory());
    LocalSession.setActiveAccount('u1');
    repo = CycleRepository(db, api, () => true, onChanged: () => changed++);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  test('patchSettings: istek yok, dirty, onChanged', () async {
    final s = await repo.patchSettings({'expected_cycle_length': 31});
    expect(s.expectedCycleLength, 31);
    expect(requests, isEmpty);
    expect(changed, 1);
    final row = await (db.select(db.cycleSettingsTable)).getSingle();
    expect(row.dirty, isTrue);
  });

  test('saveEntry + deleteEntry: istek yok, dirty, onChanged', () async {
    final e = await repo.saveEntry(
        CycleEntry(id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.medium));
    expect(requests, isEmpty);
    // saveEntry ilk adet → otomatik takip başlangıcı (patchSettings) da tetikler;
    // debounce'lu olduğundan birden fazla çağrı zararsız.
    expect(changed, greaterThanOrEqualTo(1));
    final before = changed;
    await repo.deleteEntry(e.id);
    expect(requests, isEmpty);
    expect(changed, greaterThan(before));
    final row = await (db.select(db.cycleEntries)).getSingle();
    expect(row.isDeleted, isTrue);
    expect(row.dirty, isTrue);
  });

  test('D33 çapa taşıması (silme) da satır içi PATCH atmaz', () async {
    await repo.patchSettings({'first_period_date': '2026-06-01'});
    final a = await repo.saveEntry(
        CycleEntry(id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.medium));
    await repo.saveEntry(
        CycleEntry(id: '', date: DateTime(2026, 6, 29), flow: FlowLevel.medium));
    requests.clear();
    await repo.deleteEntry(a.id); // çapa günü kalktı → çapa 29'a taşınır
    expect(requests, isEmpty);
    expect((await repo.getSettings()).firstPeriodDate, DateTime(2026, 6, 29));
  });

  test('bulut kapalı: onChanged çağrılmaz', () async {
    final local = CycleRepository(db, api, () => false, onChanged: () => changed++);
    await local.patchSettings({'enabled': false});
    await local.saveEntry(CycleEntry(id: '', date: DateTime(2026, 6, 1)));
    expect(changed, 0);
    expect(requests, isEmpty);
  });

  test('tur: syncIfCloud dirty ayar + kayıtları gönderir, temizler', () async {
    await repo.patchSettings({'expected_cycle_length': 31});
    final e = await repo.saveEntry(
        CycleEntry(id: '', date: DateTime(2026, 6, 1), flow: FlowLevel.medium));
    adapter
      ..onPatch('/cycle/settings',
          (s) => s.reply(200, {'expected_cycle_length': 31, 'enabled': true}),
          data: Matchers.any)
      ..onPost('/cycle/entries/bulk', (s) => s.reply(200, {'saved': [e.id]}),
          data: Matchers.any)
      ..onGet('/cycle/entries', (s) => s.reply(200, []));
    await repo.syncIfCloud();
    expect(requests, contains('PATCH /cycle/settings'));
    expect(requests, contains('POST /cycle/entries/bulk'));
    expect((await (db.select(db.cycleSettingsTable)).getSingle()).dirty, isFalse);
    expect((await (db.select(db.cycleEntries)).getSingle()).dirty, isFalse);
  });
}
