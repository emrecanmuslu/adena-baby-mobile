import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Kayıtların yerel kopyası (offline-first). Sunucudaki Record ile aynı şema +
/// senkron alanları (dirty = gönderilmemiş yerel değişiklik var).
/// Üretilen satır sınıfı `RecordRow` (domain `Record` ile çakışmasın diye).
@DataClassName('RecordRow')
class Records extends Table {
  TextColumn get id => text()(); // istemci-üretimli UUID (sunucuyla ortak)
  TextColumn get baby => text()();
  TextColumn get type => text()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get data => text().withDefault(const Constant('{}'))(); // JSON string
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get clientUpdatedAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()(); // sunucu damgası (pull)
  BoolColumn get dirty => boolean().withDefault(const Constant(true))(); // push bekliyor
  TextColumn get createdBy => text().nullable()(); // ekleyen kullanıcı id (sunucudan)

  @override
  Set<Column> get primaryKey => {id};
}

/// Bebek-bazlı son sync noktası (delta-sync cursor).
class SyncCursors extends Table {
  TextColumn get baby => text()();
  DateTimeColumn get cursor => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {baby};
}

@DriftDatabase(tables: [Records, SyncCursors])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(records, records.createdBy);
          }
        },
      );

  static QueryExecutor _open() => driftDatabase(name: 'adena');
}
