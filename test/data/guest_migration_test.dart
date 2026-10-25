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

  group('K7 — hasData âdet verisini de sayar', () {
    test('yalnız âdet kaydı olan misafir → true', () async {
      await repo().saveEntry(
          CycleEntry(id: '', date: DateTime(2026, 5, 1), flow: FlowLevel.medium));
      expect(await GuestMigration.hasData(db, newAcct), isTrue);
      expect(await GuestMigration.hasBabyData(db, newAcct), isFalse);
    });

    test('yalnız kurulmuş âdet ayarı olan misafir → true', () async {
      await repo().patchSettings({'breastfeeding': 'exclusive'});
      expect(await GuestMigration.hasData(db, newAcct), isTrue);
    });

    test('hiç veri yok → false; kendi hesabı misafirle aynıysa → false', () async {
      expect(await GuestMigration.hasData(db, newAcct), isFalse);
      expect(await GuestMigration.hasData(db, guestId), isFalse);
    });
  });

  group('K7 — migrateData âdet kayıtlarını taşır', () {
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

  // ───────── K8: misafir göçünde adet ayarı ─────────
  group('K8 — âdet ayarı göçü', () {
    /// initialImport'un yazdığı "sunucu varsayılanı" satırı (kurulum yok:
    /// breastfeeding boş, çapa yok, mode tracking). Backend get_or_create
    /// ile aynen böyle üretir.
    Future<void> seedDefaultRowFor(String acct) async {
      await db.into(db.cycleSettingsTable).insertOnConflictUpdate(
          CycleSettingsTableCompanion(
              id: Value(acct),
              clientUpdatedAt: Value(DateTime.now().toUtc()),
              dirty: const Value(false)));
    }

    Future<void> setupGuestLoss() => repo().patchSettings({
          'breastfeeding': 'mixed',
          'birth_date': '2026-01-10',
          'lifecycle_mode': 'loss',
          'last_loss_date': '2026-04-01',
          'predictions_hidden': true,
          'ttc_started_at': '2026-02-01',
          'learning_window': 4,
          'expected_cycle_length': 31,
          'period_length': 6,
          'luteal_phase_length': 12,
          'smart_prediction': false,
          'week_starts_sunday': true,
          'show_fertility_warning': false,
          'reminders': {'period': {'on': true}},
        });

    test('yeni hesapta yalnız varsayılan (kurulmamış) satır varsa misafir ayarı KORUNUR, tüm alanlar, dirty',
        () async {
      await setupGuestLoss();
      await seedDefaultRowFor(newAcct);

      await GuestMigration.migrateData(db, guestId, newAcct);

      final row = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(newAcct)))
          .getSingle();
      expect(row.dirty, isTrue);
      final s = CycleRepository(db, api, () => false);
      LocalSession.setActiveAccount(newAcct);
      final got = await s.getSettings();
      expect(got.lifecycleMode, CycleLifecycleMode.loss);
      expect(got.lastLossDate, DateTime(2026, 4, 1));
      expect(got.predictionsHidden, isTrue);
      expect(got.ttcStartedAt, isNotNull);
      expect(got.learningWindow, 4);
      expect(got.breastfeeding, Breastfeeding.mixed);
      expect(got.expectedCycleLength, 31);
      expect(got.smartPrediction, isFalse);
      expect(got.weekStartsSunday, isTrue);
      expect(got.reminders['period'], isNotNull);
      // misafir satırı silinmiş
      expect(
          await (db.select(db.cycleSettingsTable)..where((r) => r.id.equals(guestId)))
              .getSingleOrNull(),
          isNull);
    });

    test('TÜM kolonlar kopyalanır (id/senkron damgaları hariç) — yeni kolon unutulmaz',
        () async {
      await setupGuestLoss();
      final guestRow = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(guestId)))
          .getSingle();
      await GuestMigration.migrateData(db, guestId, newAcct);
      final newRow = await (db.select(db.cycleSettingsTable)
            ..where((r) => r.id.equals(newAcct)))
          .getSingle();
      const skip = {'id', 'dirty', 'clientUpdatedAt', 'serverUpdatedAt', 'isDeleted'};
      final g = guestRow.toJson()..removeWhere((k, _) => skip.contains(k));
      final n = newRow.toJson()..removeWhere((k, _) => skip.contains(k));
      expect(n, g, reason: 'tüm iş alanları birebir taşınmalı');
    });

    test('yeni hesapta KURULMUŞ gerçek ayar varsa o korunur, misafirinki atılır', () async {
      await setupGuestLoss();
      await db.into(db.cycleSettingsTable).insertOnConflictUpdate(
          CycleSettingsTableCompanion(
              id: const Value(newAcct),
              breastfeeding: const Value('exclusive'),
              firstPeriodDate: Value(DateTime(2026, 3, 1)),
              dirty: const Value(false)));

      await GuestMigration.migrateData(db, guestId, newAcct);

      LocalSession.setActiveAccount(newAcct);
      final got = await repo().getSettings();
      expect(got.breastfeeding, Breastfeeding.exclusive);
      expect(got.firstPeriodDate, DateTime(2026, 3, 1));
      expect(got.lifecycleMode, CycleLifecycleMode.tracking);
      expect(
          await (db.select(db.cycleSettingsTable)..where((r) => r.id.equals(guestId)))
              .getSingleOrNull(),
          isNull);
    });

    test('yeni hesapta hiç satır yoksa misafir ayarı taşınır (eski davranış korunur)',
        () async {
      await setupGuestLoss();
      await GuestMigration.migrateData(db, guestId, newAcct);
      LocalSession.setActiveAccount(newAcct);
      expect((await repo().getSettings()).lifecycleMode, CycleLifecycleMode.loss);
    });
  });
}
