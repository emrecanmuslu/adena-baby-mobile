import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/data/local/app_database.dart';

import '../drift/generated/schema.dart';

/// I4 (INCELEME.md) — migration atomikliği.
/// drift, onUpgrade'i transaction'a almaz ve user_version'ı sonra yazar; kesinti
/// → "duplicate column" ile DB açılmazdı. İki savunma test edilir:
///  (1) yarıda kesilmiş DB (user_version=14, v15 kolonlarının bir kısmı eklenmiş)
///      → açılış başarılı, şema v15 ile birebir, backfill uygulanır;
///  (2) migration içinde bir adım düşerse (hook) hiçbir kolon kalmaz (rollback),
///      sürüm 14'te kalır; sonraki açılış temiz tamamlar.
void main() {
  late SchemaVerifier verifier;
  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));
  tearDown(() => AppDatabase.debugMigrationHook = null);

  /// drift'in `addColumn`'unun üreteceği kolon tanımı (CHECK dahil) — kesinti
  /// anında diske düşmüş olanla birebir.
  String def(AppDatabase ctxDb, GeneratedColumn c) {
    final ctx = GenerationContext.fromDb(ctxDb);
    c.writeColumnDefinition(ctx);
    return ctx.sql;
  }

  Set<String> columns(InitializedSchema schema, String table) => {
        for (final r in schema.rawDatabase.select('PRAGMA table_info($table)'))
          r['name'] as String
      };

  test('(1) yarıda kesilmiş v14→v15: kolonların bir kısmı eklenmiş → açılış başarılı, '
      'şema v15, backfill uygulanır', () async {
    final schema = await verifier.schemaAt(14);
    final raw = schema.rawDatabase;
    final ctxDb = AppDatabase(NativeDatabase.memory()); // yalnız SQL bağlamı
    addTearDown(ctxDb.close);
    raw.execute('ALTER TABLE babies ADD COLUMN ${def(ctxDb, ctxDb.babies.settingsDirty)}');
    raw.execute('ALTER TABLE babies ADD COLUMN ${def(ctxDb, ctxDb.babies.settingsBase)}');
    raw.execute(
        'ALTER TABLE health_statuses ADD COLUMN ${def(ctxDb, ctxDb.healthStatuses.dirty)}');
    raw.execute("INSERT INTO babies (id, name, my_role, settings, dirty, account_id) VALUES "
        "('o', 'A', 'owner', '{\"units\":{\"volume\":\"oz\"}}', 0, 'u1')");
    raw.execute("INSERT INTO health_statuses (baby, kind, item_key, done) VALUES "
        "('o', 'milestone', 'smile', 1), ('o', 'vaccine', 'BCG', 1)");
    expect(raw.userVersion, 14);

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 15);

    final b = await db.select(db.babies).getSingle();
    expect(b.settingsDirty, isTrue, reason: 'backfill yarıda kalmış kolonda da uygulanır');
    final hs = {for (final r in await db.select(db.healthStatuses).get()) r.itemKey: r};
    expect(hs['smile']!.dirty, isTrue);
    expect(hs['BCG']!.dirty, isFalse);
    expect(hs['BCG']!.pushError, isNull);
  });

  test('(2) adım düşerse rollback: kolon kalmaz, sürüm 14; sonraki açılış tamamlar',
      () async {
    final schema = await verifier.schemaAt(14);
    AppDatabase.debugMigrationHook = () async => throw StateError('kesinti');
    final failing = AppDatabase(schema.newConnection());
    await expectLater(failing.customSelect('SELECT 1').get(), throwsA(isA<Object>()));
    try {
      await failing.close();
    } catch (_) {}

    expect(columns(schema, 'babies'), isNot(contains('settings_dirty')),
        reason: 'transaction geri alınmalı');
    expect(columns(schema, 'health_statuses'), isNot(contains('dirty')));
    expect(schema.rawDatabase.userVersion, 14);

    AppDatabase.debugMigrationHook = null;
    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 15);
  });

  test('(3) hook YOKKEN normal v14→v15 (regresyon)', () async {
    final db = AppDatabase(await verifier.startAt(14));
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 15);
  });
}
