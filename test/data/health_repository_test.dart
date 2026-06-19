import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/health_catalog.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';

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

/// Local-first sağlık repo: katalog (içerik) + durum (Drift). cloudEnabled=false
/// → hiç ağ çağrısı yok; tüm doğrulama yerel DB üzerinden.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const catalog = HealthCatalog(
    [
      VaccineCatalogItem('Hepatit B', 0, 'Hepatit B'),
      VaccineCatalogItem('BCG', 2, 'BCG'),
    ],
    [
      MilestoneCatalogItem('roll', 4, 'motor', 'Yuvarlanma', 'desc', 'tip'),
    ],
    [
      ToothCatalogItem('ll1', 'lower', 'left', 1, 'Orta kesici', 6),
    ],
  );

  late ApiClient api;
  late AppDatabase db;
  late HealthRepository repo;

  setUp(() async {
    api = ApiClient(_FakeTokens());
    db = AppDatabase(NativeDatabase.memory());
    repo = HealthRepository(db, api, () async => catalog, (_) => false);
    // Doğum tarihli bebek (aşı due_date üretimi için).
    await db.into(db.babies).insert(
          BabiesCompanion.insert(
            id: 'b1',
            name: 'Test',
            birthDate: Value(DateTime(2026, 1, 1)),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('vaccines', () {
    test('katalog + doğum tarihinden üretilir (due_date = birth + ay)', () async {
      final list = await repo.vaccines('b1');
      expect(list, hasLength(2));
      expect(list[0].name, 'Hepatit B');
      expect(list[0].dueDate, DateTime(2026, 1, 1));
      expect(list[1].name, 'BCG');
      expect(list[1].dueDate, DateTime(2026, 3, 1)); // +2 ay
      expect(list.every((v) => !v.done), isTrue);
    });

    test('doğum tarihi yoksa boş döner', () async {
      await db.into(db.babies).insert(
            BabiesCompanion.insert(id: 'b2', name: 'NoBirth'),
          );
      expect(await repo.vaccines('b2'), isEmpty);
    });

    test('setVaccineDone(true) durumu yerelde saklar + listeye yansır', () async {
      await repo.setVaccineDone('b1', 'BCG',
          done: true, date: DateTime(2026, 3, 4));
      final bcg = (await repo.vaccines('b1')).firstWhere((v) => v.key == 'BCG');
      expect(bcg.done, isTrue);
      expect(bcg.doneDate, DateTime(2026, 3, 4));

      final rows = await db.select(db.healthStatuses).get();
      expect(rows, hasLength(1));
      expect(rows[0].kind, 'vaccine');
      expect(rows[0].itemKey, 'BCG');
      expect(rows[0].done, isTrue);
    });

    test('setVaccineDone(false) geri alır (done=false, date=null)', () async {
      await repo.setVaccineDone('b1', 'BCG', done: true, date: DateTime(2026, 3, 4));
      await repo.setVaccineDone('b1', 'BCG', done: false);
      final bcg = (await repo.vaccines('b1')).firstWhere((v) => v.key == 'BCG');
      expect(bcg.done, isFalse);
      expect(bcg.doneDate, isNull);
    });
  });

  group('milestones', () {
    test('katalogtan üretilir, durum birleşir', () async {
      final list = await repo.milestones('b1');
      expect(list, hasLength(1));
      expect(list[0].key, 'roll');
      expect(list[0].category, 'motor');
      expect(list[0].expectedMonth, 4);
      expect(list[0].achieved, isFalse);
    });

    test('setMilestoneAchieved(true) işaretler + tarih', () async {
      await repo.setMilestoneAchieved('b1', 'roll',
          achieved: true, date: DateTime(2026, 5, 6));
      final m = (await repo.milestones('b1')).single;
      expect(m.achieved, isTrue);
      expect(m.achievedDate, DateTime(2026, 5, 6));
    });

    test('setMilestoneAchieved(false) geri alır', () async {
      await repo.setMilestoneAchieved('b1', 'roll', achieved: true);
      await repo.setMilestoneAchieved('b1', 'roll', achieved: false);
      final m = (await repo.milestones('b1')).single;
      expect(m.achieved, isFalse);
      expect(m.achievedDate, isNull);
    });
  });

  group('teeth', () {
    test('katalogtan üretilir, durum birleşir', () async {
      final list = await repo.teeth('b1');
      expect(list, hasLength(1));
      expect(list[0].key, 'll1');
      expect(list[0].jaw, 'lower');
      expect(list[0].typicalMonth, 6);
      expect(list[0].erupted, isFalse);
    });

    test('setToothErupted(true) işaretler + tarih', () async {
      await repo.setToothErupted('b1', 'll1',
          erupted: true, date: DateTime(2026, 7, 8));
      final t = (await repo.teeth('b1')).single;
      expect(t.erupted, isTrue);
      expect(t.eruptedDate, DateTime(2026, 7, 8));
    });
  });

  group('reminders (yerel CRUD, int id)', () {
    test('createReminder yerel int id üretir + listede görünür', () async {
      final schedule = {'repeat': 'once', 'at': '2026-06-20T09:00:00Z'};
      final r = await repo.createReminder('b1', type: 'appt', schedule: schedule);
      expect(r.id, greaterThan(0));
      expect(r.type, 'appt');
      expect(r.schedule['repeat'], 'once');

      final list = await repo.reminders('b1');
      expect(list, hasLength(1));
      expect(list[0].id, r.id);
      expect(list[0].enabled, isTrue);
    });

    test('setReminderEnabled günceller', () async {
      final r = await repo.createReminder('b1',
          type: 'custom', schedule: {'repeat': 'daily', 'time': '08:00'});
      await repo.setReminderEnabled(r.id, false);
      final list = await repo.reminders('b1');
      expect(list.single.enabled, isFalse);
    });

    test('deleteReminder kaldırır', () async {
      final r = await repo.createReminder('b1',
          type: 'custom', schedule: {'repeat': 'daily', 'time': '08:00'});
      await repo.deleteReminder(r.id);
      expect(await repo.reminders('b1'), isEmpty);
    });
  });

  group('purgeBaby', () {
    test('bebeğin sağlık durumu + hatırlatıcıları siler', () async {
      await repo.setVaccineDone('b1', 'BCG', done: true);
      await repo.createReminder('b1',
          type: 'custom', schedule: {'repeat': 'daily', 'time': '08:00'});
      await repo.purgeBaby('b1');
      expect(await db.select(db.healthStatuses).get(), isEmpty);
      expect(await db.select(db.localReminders).get(), isEmpty);
    });
  });
}
