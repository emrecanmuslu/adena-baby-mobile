import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/guest_migration.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/models/cycle.dart';

/// K7 (BULGULAR.md): bebeksiz (cycle-first) misafirin adet verisi hesap
/// açınca sessizce yetim kalıyordu — `hasData` yalnız bebek sayıyordu.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late AppDatabase db;
  late String guestId;
  const newAcct = 'acct-new';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = ApiClient(_FakeTokens());
    DioAdapter(dio: api.dio);
    db = AppDatabase(NativeDatabase.memory());
    await LocalSession.enterGuest(); // localUserId üretir + aktif kapsam = misafir
    guestId = LocalSession.userId;
    expect(guestId, isNotEmpty);
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  CycleRepository repo() => CycleRepository(db, api, () => false);

  group('K7 — hasData adet verisini de sayar', () {
    test('yalnız adet kaydı olan misafir → true', () async {
      await repo().saveEntry(
          CycleEntry(id: '', date: DateTime(2026, 5, 1), flow: FlowLevel.medium));
      expect(await GuestMigration.hasData(db, newAcct), isTrue);
      expect(await GuestMigration.hasBabyData(db, newAcct), isFalse);
    });

    test('yalnız kurulmuş adet ayarı olan misafir → true', () async {
      await repo().patchSettings({'breastfeeding': 'exclusive'});
      expect(await GuestMigration.hasData(db, newAcct), isTrue);
    });

    test('hiç veri yok → false; kendi hesabı misafirle aynıysa → false', () async {
      expect(await GuestMigration.hasData(db, newAcct), isFalse);
      expect(await GuestMigration.hasData(db, guestId), isFalse);
    });
  });

  group('K7 — migrateData adet kayıtlarını taşır', () {
    test('kayıtlar yeni hesap kapsamında görünür ve dirty', () async {
      final e = await repo().saveEntry(
          CycleEntry(id: '', date: DateTime(2026, 5, 1), flow: FlowLevel.medium));
      // Göç öncesi "temiz" olsun ki dirty'nin göçle açıldığı görülsün.
      await (db.update(db.cycleEntries)..where((r) => r.id.equals(e.id)))
          .write(const CycleEntriesCompanion(dirty: Value(false)));

      await GuestMigration.migrateData(db, guestId, newAcct);

      LocalSession.setActiveAccount(newAcct);
      final mine = await repo().listEntries();
      expect(mine.map((x) => x.id), [e.id]);
      final row = await (db.select(db.cycleEntries)..where((r) => r.id.equals(e.id)))
          .getSingle();
      expect(row.accountId, newAcct);
      expect(row.dirty, isTrue);

      LocalSession.setActiveAccount(guestId);
      expect(await repo().listEntries(), isEmpty);
    });
  });
}
