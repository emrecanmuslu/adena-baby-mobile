import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/data/local/app_database.dart';

import '../drift/generated/schema.dart';

/// M1 — git geçmişindeki HER yayınlanmış şema sürümünden GÜNCEL sürüme (v16)
/// migration. Anlık görüntüler `test/drift/schemas/drift_schema_v{2,3,5,7,8,9,11,12,13,14,15}.json`
/// (ilgili commit'teki `app_database.dart`'tan `drift_dev schema dump`; v4/v6/v10
/// hiç yayınlanmadı — tek commit'te atlandı). Yapısal doğrulama + v12–v15'ten
/// veri dolu geçiş (backfill kuralları, eski kolonlar).
void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  const versions = [2, 3, 5, 7, 8, 9, 11, 12, 13, 14, 15];

  group('yapısal: her sürümden v16', () {
    for (final v in versions) {
      test('v$v → v16', () async {
        final db = AppDatabase(await verifier.startAt(v));
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 16);
      });
    }
  });

  group('veri dolu geçiş', () {
    for (final v in [12, 13, 14, 15]) {
      test('v$v → v16: backfill + eski veri korunur', () async {
        final schema = await verifier.schemaAt(v);
        final raw = schema.rawDatabase;
        raw.execute("INSERT INTO babies (id, name, my_role, settings, dirty, account_id) VALUES "
            "('owner_full', 'A', 'owner', '{\"units\":{\"volume\":\"oz\"}}', 0, 'u1'), "
            "('owner_empty', 'B', NULL, '{}', 1, 'u1'), "
            "('parent_full', 'C', 'parent', '{\"units\":{\"volume\":\"oz\"}}', 1, 'u1'), "
            "('caregiver_full', 'D', 'caregiver', '{\"quiet_hours\":{\"enabled\":true}}', 0, 'u1')");
        raw.execute("INSERT INTO health_statuses (baby, kind, item_key, done, status_date) VALUES "
            "('owner_full', 'vaccine', 'Hepatit B (1. doz)', 1, 1700000000), "
            "('owner_full', 'milestone', 'smile', 1, 1700000000), "
            "('owner_full', 'tooth', 'lower_central_1', 1, NULL), "
            "('owner_full', 'milestone', 'walk', 0, NULL)");
        raw.execute("INSERT INTO memories (id, baby, date, title, dirty) VALUES "
            "('m1', 'owner_full', 1700000000, 'ilk gülüş', 1)");
        raw.execute("INSERT INTO cycle_entries (id, date, dirty, account_id) VALUES "
            "('c1', 1700000000, 1, 'u1')");
        raw.execute("INSERT INTO cycle_settings_table (id, dirty, expected_cycle_length) VALUES ('u1', 1, 30)");
        if (v >= 13) {
          // created_at = 2026-10-01 12:00 UTC (drift DateTime = unix saniye).
          raw.execute("INSERT INTO medication_plans (baby, name, dose, times_json, active, created_at) VALUES "
              "('owner_full', 'D vit', '1 damla', '[\"09:00\"]', 1, 1759320000)");
        }

        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 16);

        final babies = {for (final b in await db.select(db.babies).get()) b.id: b};
        // v14→v15 backfill'i yalnız v<15 kaynağında koşar; v15 kaynağında
        // satırlar zaten v15 şemasında yazıldı (settings_dirty varsayılanı 0) ve
        // v16 adımı onlara dokunmaz.
        expect(babies['owner_full']!.settingsDirty, v < 15);
        expect(babies['owner_empty']!.settingsDirty, isFalse);
        expect(babies['parent_full']!.settingsDirty, isFalse);
        expect(babies['caregiver_full']!.settingsDirty, isFalse);
        expect(babies['owner_full']!.settings, '{"units":{"volume":"oz"}}');
        for (final b in babies.values) {
          expect(b.pushError, isNull);
          expect(b.settingsBase, isNull);
        }
        final hs = {for (final r in await db.select(db.healthStatuses).get()) '${r.kind}/${r.itemKey}': r};
        expect(hs['vaccine/Hepatit B (1. doz)']!.dirty, isFalse);
        expect(hs['vaccine/Hepatit B (1. doz)']!.done, isTrue);
        expect(hs['milestone/smile']!.dirty, v < 15); // K-4 backfill (v14→v15)
        expect(hs['tooth/lower_central_1']!.dirty, v < 15);
        expect(hs['milestone/walk']!.dirty, isFalse);
        final mem = await db.select(db.memories).getSingle();
        expect(mem.title, 'ilk gülüş');
        expect(mem.dirty, isTrue);
        expect(mem.pushError, isNull);
        final cs = await db.select(db.cycleSettingsTable).getSingle();
        expect(cs.expectedCycleLength, 30);
        expect(cs.pushError, isNull);
        expect((await db.select(db.cycleEntries).getSingle()).dirty, isTrue);
        if (v >= 13) {
          final plan = await db.select(db.medicationPlans).getSingle();
          expect(plan.name, 'D vit');
          // v13→14 adımı (ya da v14/v15 varsayılanı): dirty=true ile yüklenir.
          expect(plan.dirty, isTrue);
          expect(plan.isDeleted, isFalse);
          // v16 (İlaç v2): yeni kolonlar varsayılanlı; başlangıç/zamanlama çapası
          // created_at'ten doldurulur.
          expect(plan.kind, 'scheduled');
          expect(plan.freq, 'daily');
          expect(plan.weekdaysJson, '[]');
          expect(plan.pausesJson, '[]');
          expect(plan.intervalHours, isNull);
          expect(plan.everyNDays, isNull);
          expect(plan.endDate, isNull);
          expect(plan.prnMinIntervalMin, isNull);
          expect(plan.prnMaxPerDay, isNull);
          expect(plan.pushError, isNull);
          final created = DateTime.fromMillisecondsSinceEpoch(1759320000 * 1000);
          String ymd(DateTime d) =>
              '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          expect(plan.startDate, ymd(created));
          expect(plan.scheduleFrom, created);
        }
      });
    }
  });
}
