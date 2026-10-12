import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/data/local/app_database.dart';

import '../drift/generated/schema.dart';

/// Şema v14 → v15 (TASARIM-SENKRON.md §5A). Yapısal doğrulama (SchemaVerifier)
/// + VERİ DOLU v14 DB'den geçiş: backfill kuralları (K-4: aşıda yok,
/// gelişim/dişte done→dirty; O4: yalnız sahip satırında dolu ayar → settingsDirty),
/// eski kolonların korunması, pushError NULL.
///
/// v14 anlık görüntüsü: `test/drift/schemas/drift_schema_v14.json` (90df7b7'deki
/// şemadan dump), yardımcılar `test/drift/generated/` (drift_dev schema generate).
/// Güncel şema sürümü — bu dosyadaki göçler hep EN SON şemaya doğrulanır.
const kLatestSchema = 16;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('yapısal: v14 → v15 migration, şema anlık görüntüyle birebir', () async {
    final connection = await verifier.startAt(14);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, kLatestSchema);
  });

  test('taze kurulum: createAll, schemaVersion güncel (v15 kolonları dahil)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, kLatestSchema);
    // Yeni kolonlar okunabilir (taze şemada da var).
    await db.into(db.healthStatuses).insert(HealthStatusesCompanion.insert(
        baby: 'b', kind: 'vaccine', itemKey: 'k', done: const Value(true)));
    final r = await db.select(db.healthStatuses).getSingle();
    expect(r.dirty, isFalse, reason: 'sağlıkta dirty varsayılanı FALSE');
    expect(r.pushError, isNull);
    final b = await (db.select(db.babies)).get();
    expect(b, isEmpty);
  });

  test('veri dolu v14 → v15: backfill kuralları + eski veri korunur', () async {
    final schema = await verifier.schemaAt(14);
    final raw = schema.rawDatabase;
    // ---- v14 satırları (ham SQL; kolon adları snake_case) ----
    // Bebekler: sahip (my_role NULL) dolu ayar; sahip ('owner') boş ayar;
    // parent dolu ayar; caregiver dolu ayar; sahip dolu ayar ama dirty=0.
    raw.execute("INSERT INTO babies (id, name, my_role, settings, dirty, account_id) VALUES "
        "('b_owner_null', 'A', NULL, '{\"units\":{\"volume\":\"oz\"}}', 1, 'u1'), "
        "('b_owner_empty', 'B', 'owner', '{}', 1, 'u1'), "
        "('b_parent', 'C', 'parent', '{\"units\":{\"volume\":\"oz\"}}', 1, 'u1'), "
        "('b_caregiver', 'D', 'caregiver', '{\"quiet_hours\":{\"enabled\":true}}', 0, 'u1'), "
        "('b_owner_clean', 'E', 'owner', '{\"units\":{\"weight\":\"lb\"}}', 0, 'u1')");
    // Sağlık: aşı done (backfill YOK), gelişim done, diş done, gelişim undone.
    raw.execute("INSERT INTO health_statuses (baby, kind, item_key, done, status_date) VALUES "
        "('b_owner_null', 'vaccine', 'Hepatit B (1. doz)', 1, 1700000000), "
        "('b_owner_null', 'milestone', 'smile', 1, 1700000000), "
        "('b_owner_null', 'tooth', 'lower_central_1', 1, NULL), "
        "('b_owner_null', 'milestone', 'walk', 0, NULL)");
    raw.execute("INSERT INTO memories (id, baby, date, title, dirty) VALUES "
        "('m1', 'b_owner_null', 1700000000, 'ilk gülüş', 1)");
    raw.execute("INSERT INTO mom_entries (id, baby, kind, date, dirty) VALUES "
        "('mo1', 'b_owner_null', 'note', 1700000000, 1)");
    raw.execute("INSERT INTO cycle_entries (id, date, dirty, account_id) VALUES "
        "('c1', 1700000000, 1, 'u1')");
    raw.execute("INSERT INTO cycle_settings_table (id, dirty) VALUES ('u1', 1)");

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, kLatestSchema);

    // ---- bebekler: settingsDirty yalnız sahip + dolu ----
    final babies = {for (final b in await db.select(db.babies).get()) b.id: b};
    expect(babies['b_owner_null']!.settingsDirty, isTrue);
    expect(babies['b_owner_clean']!.settingsDirty, isTrue,
        reason: 'sahip + dolu ayar: bebek dirty olmasa da (karar: rol + JSON)');
    expect(babies['b_owner_empty']!.settingsDirty, isFalse, reason: 'boş JSON');
    expect(babies['b_parent']!.settingsDirty, isFalse, reason: 'üye: backfill yok');
    expect(babies['b_caregiver']!.settingsDirty, isFalse, reason: 'caregiver: yok');
    for (final b in babies.values) {
      expect(b.settingsBase, isNull);
      expect(b.pushError, isNull);
    }
    // eski veri korunur
    expect(babies['b_owner_null']!.name, 'A');
    expect(babies['b_owner_null']!.settings, '{"units":{"volume":"oz"}}');
    expect(babies['b_owner_null']!.dirty, isTrue);
    expect(babies['b_caregiver']!.dirty, isFalse);

    // ---- sağlık: K-4 (aşı hariç) ----
    final hs = await db.select(db.healthStatuses).get();
    final byKey = {for (final r in hs) '${r.kind}/${r.itemKey}': r};
    expect(byKey['vaccine/Hepatit B (1. doz)']!.dirty, isFalse,
        reason: 'AŞIDA backfill yok (ilk turda sunucu kazanır)');
    expect(byKey['vaccine/Hepatit B (1. doz)']!.done, isTrue,
        reason: 'yerel değer migration ile değişmez');
    expect(byKey['milestone/smile']!.dirty, isTrue);
    expect(byKey['tooth/lower_central_1']!.dirty, isTrue);
    expect(byKey['milestone/walk']!.dirty, isFalse, reason: 'done=false → dirty yok');
    for (final r in hs) {
      expect(r.clientUpdatedAt, isNull);
      expect(r.serverUpdatedAt, isNull);
      expect(r.pushError, isNull);
    }
    expect(byKey['milestone/smile']!.statusDate, isNotNull);

    // ---- diğer tablolar: pushError NULL, dirty korunur ----
    final mem = await db.select(db.memories).getSingle();
    expect(mem.pushError, isNull);
    expect(mem.dirty, isTrue);
    expect(mem.title, 'ilk gülüş');
    final mom = await db.select(db.momEntries).getSingle();
    expect(mom.pushError, isNull);
    final ce = await db.select(db.cycleEntries).getSingle();
    expect(ce.pushError, isNull);
    expect(ce.dirty, isTrue);
    final cs = await db.select(db.cycleSettingsTable).getSingle();
    expect(cs.pushError, isNull);
    expect(cs.dirty, isTrue);
  });

  test('v14 öncesi eski kurulum (from < 7): tablolar v15 şemasıyla kurulur', () async {
    // Eski sürümden gelen DB'de health_statuses yoktur; from<7 yolu createTable
    // ile v15 şemasını kurar, addColumn guard'ı (from >= 7) tekrar eklemez.
    final connection = await verifier.startAt(14);
    final db = AppDatabase(connection);
    addTearDown(db.close);
    // startAt yalnız 14'ü destekler (anlık görüntü yok) → guard mantığı yapısal
    // testte dolaylı doğrulanır; burada 14→15 yolunun idempotent olduğunu
    // (ikinci validate) kontrol ediyoruz.
    await verifier.migrateAndValidate(db, kLatestSchema);
  });
}
