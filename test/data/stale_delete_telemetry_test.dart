import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/sync_telemetry.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/memory_repository.dart';

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

/// INCELEME §5.6 — R4 "silme atlandı" (K-2 koruması: boş liste / oran) olayı
/// yalnız debugPrint değil, Crashlytics non-fatal (SyncTelemetry) olarak da
/// raporlanır; sahada ne sıklıkla tetiklendiği görülsün.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ApiClient api;
  late DioAdapter adapter;
  late List<(String, Map<String, Object?>)> reports;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    reports = [];
    SyncTelemetry.override = (e, i) async => reports.add((e, i));
    await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b1', name: 'T'));
  });
  tearDown(() async {
    SyncTelemetry.override = null;
    await db.close();
  });

  Future<void> seedClean(int n) async {
    for (var i = 0; i < n; i++) {
      await db.into(db.memories).insert(MemoriesCompanion.insert(
          id: 'm$i', baby: 'b1', date: DateTime(2026, 1, 1 + i), dirty: const Value(false)));
    }
  }

  test('sunucu boş liste → silme atlanır + stale_delete_skipped(server_list_empty)', () async {
    await seedClean(1);
    adapter.onGet('/babies/b1/memories', (s) => s.reply(200, []));
    await MemoryRepository(db, api, 'me', (_) => true).syncIfCloud('b1');
    expect(await (db.select(db.memories)).get(), hasLength(1));
    expect(reports, hasLength(1));
    expect(reports.single.$1, 'stale_delete_skipped');
    expect(reports.single.$2['table'], 'memories');
    expect(reports.single.$2['reason'], 'server_list_empty');
  });

  test('oran koruması (>5 ∧ >%50) → rapor too_many_deletions', () async {
    await seedClean(7);
    adapter.onGet('/babies/b1/memories', (s) => s.reply(200, [
          {'id': 'other', 'date': '2026-02-01', 'title': 'x', 'note': '', 'photo': null,
            'first_tag': '', 'created_by': null, 'updated_at': '2026-02-01T00:00:00Z'},
        ]));
    await MemoryRepository(db, api, 'me', (_) => true).syncIfCloud('b1');
    expect(reports.single.$2['reason'], startsWith('too_many_deletions'));
    expect(await (db.select(db.memories)).get(), hasLength(8), reason: 'hiçbiri silinmez');
  });

  test('normal pull (silinecek yok) → rapor yok', () async {
    await seedClean(1);
    adapter.onGet('/babies/b1/memories', (s) => s.reply(200, [
          {'id': 'm0', 'date': '2026-01-01', 'title': 'x', 'note': '', 'photo': null,
            'first_tag': '', 'created_by': null, 'updated_at': '2026-02-01T00:00:00Z'},
        ]));
    await MemoryRepository(db, api, 'me', (_) => true).syncIfCloud('b1');
    expect(reports, isEmpty);
  });
}
