import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Senkron alanlarını paylaşan tablo mixin'i. Local-first: her satır telefonda
/// doğar (dirty=true), premium'da cloud'a aynalanır. `isDeleted` tombstone,
/// `clientUpdatedAt` son-yazan-kazanır damgası, `serverUpdatedAt` pull damgası.
mixin _SyncCols on Table {
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get clientUpdatedAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}

/// Kayıtların yerel kopyası (offline-first). Sunucudaki Record ile aynı şema +
/// senkron alanları (dirty = gönderilmemiş yerel değişiklik var).
/// Üretilen satır sınıfı `RecordRow` (domain `Record` ile çakışmasın diye).
@DataClassName('RecordRow')
class Records extends Table with _SyncCols {
  TextColumn get id => text()(); // istemci-üretimli UUID (sunucuyla ortak)
  TextColumn get baby => text()();
  TextColumn get type => text()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get data => text().withDefault(const Constant('{}'))(); // JSON string
  TextColumn get createdBy => text().nullable()(); // ekleyen kullanıcı id

  @override
  Set<Column> get primaryKey => {id};
}

/// Bebek profili (local-first). Free kullanıcıda yalnız telefonda; premium'da
/// `/babies` ile aynalanır. myRole/memberCount paylaşım (cloud) kavramları —
/// yerelde owner/1 varsayılır.
@DataClassName('BabyRow')
class Babies extends Table with _SyncCols {
  TextColumn get id => text()();
  // Hangi hesaba ait (yerel izolasyon). null = eski/sahipsiz (hiçbir hesaba
  // gösterilmez). Cihazda çoklu hesap verisi ayrık tutulur.
  TextColumn get accountId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get gender => text().withDefault(const Constant('unknown'))();
  TextColumn get photo => text().nullable()(); // yerel dosya yolu veya sunucu URL
  TextColumn get status => text().withDefault(const Constant('born'))();
  DateTimeColumn get birthDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get lastMenstrualDate => dateTime().nullable()();
  // Prematüre: doğumdaki gebelik haftası/günü. null hafta = bilinmiyor/zamanında.
  IntColumn get gestationalWeeks => integer().nullable()();
  IntColumn get gestationalDays => integer().withDefault(const Constant(0))();
  TextColumn get myRole => text().nullable()();
  IntColumn get memberCount => integer().withDefault(const Constant(1))();
  // Aile ayarları (units, enabled_types, defaults, reminder_schedule,
  // feed_reminder, quiet_hours) — yerel JSON. Premium'da /babies/{id}/settings.
  TextColumn get settings => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Anı / foto günlüğü (local-first). Free'de foto telefonda (`localPhotoPath`);
/// premium'a geçişte yüklenir ve `photo` sunucu URL'i olur.
@DataClassName('MemoryRow')
class Memories extends Table with _SyncCols {
  TextColumn get id => text()();
  TextColumn get baby => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get photo => text().nullable()(); // sunucu URL'i (premium yüklemesi sonrası)
  TextColumn get localPhotoPath => text().nullable()(); // yerel kopya (free)
  TextColumn get firstTag => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Gebelik modu anne takibi (kilo/randevu/not) — local-first.
@DataClassName('MomEntryRow')
class MomEntries extends Table with _SyncCols {
  TextColumn get id => text()();
  TextColumn get baby => text()();
  TextColumn get kind => text()(); // weight | appointment | note
  DateTimeColumn get date => dateTime()();
  RealColumn get weightKg => real().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Adet/loşia takibi ayarları — kullanıcıya özel tekil satır (id='me').
@DataClassName('CycleSettingsRow')
class CycleSettingsTable extends Table with _SyncCols {
  TextColumn get id => text().withDefault(const Constant('me'))();
  TextColumn get baby => text().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get breastfeeding => text().nullable()();
  DateTimeColumn get firstPeriodDate => dateTime().nullable()();
  TextColumn get reminders => text().withDefault(const Constant('{}'))(); // JSON
  BoolColumn get showFertilityWarning =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  // Tahmin ayarları (manuel/opsiyonel). Ölçülmüş veri yokken tahmine beslenir.
  IntColumn get expectedCycleLength => integer().nullable()();
  IntColumn get periodLength => integer().nullable()();
  IntColumn get lutealPhaseLength => integer().nullable()();
  // Akıllı tahmin (My Calendar pariteli) — AÇIK: son loglardan öğren; KAPALI: sabit.
  BoolColumn get smartPrediction => boolean().withDefault(const Constant(true))();
  // Takvimde haftanın ilk günü Pazar mı (My Calendar "First day of week"). False → Pzt.
  BoolColumn get weekStartsSunday => boolean().withDefault(const Constant(false))();
  // ── Yaşam-döngüsü (Flo-tarzı) ──
  // Aktif mod: tracking (adet) | ttc (gebe kalma) | pregnant | postpartum | loss.
  TextColumn get lifecycleMode =>
      text().withDefault(const Constant('tracking'))();
  // TTC (gebe kalmaya çalışma) moduna ne zaman geçildi (içerik/analitik).
  DateTimeColumn get ttcStartedAt => dateTime().nullable()();
  // Şefkatli gizleme: düşük/postpartum'da doğurganlık tahminlerini gizle.
  BoolColumn get predictionsHidden =>
      boolean().withDefault(const Constant(false))();
  // Son gebelik kaybı (düşük) tarihi — dönüş penceresi/şefkatli akış için.
  DateTimeColumn get lastLossDate => dateTime().nullable()();
  // Akıllı tahmin öğrenme penceresi (kaç döngü ortalanır): null → 6 varsayılan.
  IntColumn get learningWindow => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Günlük adet/loşia girdileri — local-first.
@DataClassName('CycleEntryRow')
class CycleEntries extends Table with _SyncCols {
  TextColumn get id => text()();
  TextColumn get accountId => text().nullable()(); // hesaba özel izolasyon
  DateTimeColumn get date => dateTime()(); // gün (saat önemsiz)
  TextColumn get flow => text().nullable()();
  TextColumn get lochiaColor => text().nullable()();
  TextColumn get symptoms => text().withDefault(const Constant('[]'))(); // JSON list
  IntColumn get mood => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Varlık-başına son sync noktası (delta-sync cursor). Records delta-sync'i
/// `baby` anahtarını kullanır (geriye dönük uyumlu).
class SyncCursors extends Table {
  TextColumn get baby => text()(); // geriye dönük: records cursor anahtarı
  // ISO-8601 STRING (ham sunucu next_cursor) — DİKKAT: DateTimeColumn DEĞİL.
  // drift DateTime'ı Unix SANİYE'ye yuvarlayıp sub-second'ı atıyordu; sunucu
  // updated_at'i mikrosaniyeli olduğundan `updated_at__gt=cursor` filtresinde
  // boundary kaydı her sync'te yeniden dönüp SONSUZ sync döngüsü (saniyede bir,
  // aynı kayıt) oluşuyordu. String, tam hassasiyeti koruyup döngüyü kırar.
  TextColumn get cursor => text().nullable()();

  @override
  Set<Column> get primaryKey => {baby};
}

/// Sağlık durumu (aşı/gelişim/diş işaretleri) — local-first. Katalog (hangi
/// kalemler) içerik olarak ayrı gelir; burada YALNIZ bebeğe özel durum tutulur.
/// `kind` = vaccine|milestone|tooth, `itemKey` = aşı adı / milestone-diş key.
/// Premium'da tüm küme `/health/sync` ile buluta yansıtılır (son-yazan-kazanır).
@DataClassName('HealthStatusRow')
class HealthStatuses extends Table {
  TextColumn get baby => text()();
  TextColumn get kind => text()(); // vaccine | milestone | tooth
  TextColumn get itemKey => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get statusDate => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {baby, kind, itemKey};
}

/// Hatırlatıcı (özel/randevu) — local-first. Bildirim sistemi kimliği olarak
/// yerel autoincrement `localId` kullanılır (NotificationService int id ister).
/// Premium'da tüm küme `/health/sync` ile buluta yansıtılır (replace-set).
@DataClassName('ReminderRow')
class LocalReminders extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get baby => text()();
  TextColumn get type => text().withDefault(const Constant('custom'))();
  TextColumn get scheduleJson => text().withDefault(const Constant('{}'))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
}

@DriftDatabase(tables: [
  Records,
  Babies,
  Memories,
  MomEntries,
  CycleSettingsTable,
  CycleEntries,
  SyncCursors,
  HealthStatuses,
  LocalReminders,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes(m);
          await _createLocalFirstIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(records, records.createdBy);
          }
          if (from < 3) {
            await _createIndexes(m);
          }
          if (from < 4) {
            // Local-first genişlemesi: yeni varlık tabloları.
            await m.createTable(babies);
            await m.createTable(memories);
            await m.createTable(momEntries);
            await m.createTable(cycleSettingsTable);
            await m.createTable(cycleEntries);
            await _createLocalFirstIndexes(m);
          }
          if (from < 5) {
            // Hesap-kapsamlı yerel izolasyon: mevcut satırlar accountId=NULL
            // (sahipsiz → hiçbir hesaba gösterilmez). CycleSettings hesaba özel
            // (id=accountId) olur; eski 'me' satırı sahipsiz kalır.
            await m.addColumn(babies, babies.accountId);
            await m.addColumn(cycleEntries, cycleEntries.accountId);
          }
          if (from < 6) {
            // Prematüre desteği: doğumdaki gebelik yaşı kolonları.
            await m.addColumn(babies, babies.gestationalWeeks);
            await m.addColumn(babies, babies.gestationalDays);
          }
          if (from < 7) {
            // Sağlık local-first: aşı/gelişim/diş durumu + hatırlatıcılar yerelde.
            await m.createTable(healthStatuses);
            await m.createTable(localReminders);
          }
          if (from < 8) {
            // Adet tahmin ayarları: döngü uzunluğu artık yerelde de saklanır
            // (eskiden kolon yoktu → değişiklik kaydolmuyordu) + adet/luteal süresi.
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.expectedCycleLength);
            await m.addColumn(cycleSettingsTable, cycleSettingsTable.periodLength);
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.lutealPhaseLength);
          }
          if (from < 9) {
            // SyncCursors.cursor: DateTime(saniye) → Text(ISO, tam hassasiyet).
            // Sütun tipi değişimi için tabloyu yeniden kur. Cursor kaybı ZARARSIZ:
            // sonraki sync since=null gönderir → tam pull (idempotent, kayıt
            // kaybı yok). Sonsuz sync döngüsü fix'i.
            await m.database.customStatement('DROP TABLE IF EXISTS sync_cursors');
            await m.createTable(syncCursors);
          }
          if (from < 10) {
            // Akıllı tahmin toggle (My Calendar pariteli) yerelde de saklanır.
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.smartPrediction);
          }
          if (from < 11) {
            // Takvim haftanın ilk günü (Pazar/Pazartesi) ayarı.
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.weekStartsSunday);
          }
          if (from < 12) {
            // Yaşam-döngüsü (Flo-tarzı): adet ↔ TTC ↔ gebelik ↔ postpartum ↔ kayıp.
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.lifecycleMode);
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.ttcStartedAt);
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.predictionsHidden);
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.lastLossDate);
            await m.addColumn(
                cycleSettingsTable, cycleSettingsTable.learningWindow);
          }
        },
      );

  /// Home/timeline/grafik sorguları için indeksler. Tüm okumalar `baby`'ye
  /// göre filtreleyip `ts`'e göre sıralar; (baby, type, ts) ise tipe özel
  /// "en son kayıt" (Son Aktivite) ve tip filtreli akışı hızlandırır.
  Future<void> _createIndexes(Migrator m) async {
    await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_records_baby_ts ON records (baby, ts)');
    await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_records_baby_type_ts '
        'ON records (baby, type, ts)');
  }

  Future<void> _createLocalFirstIndexes(Migrator m) async {
    await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_memories_baby_date ON memories (baby, date)');
    await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_mom_baby_date ON mom_entries (baby, date)');
    await m.database.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_cycle_date ON cycle_entries (date)');
  }

  /// Tüm yerel verileri siler (hesapsız "yerel verileri sil" / GDPR). Şema kalır,
  /// satırlar gider — kullanıcı sıfırdan başlar.
  Future<void> wipeAllData() async {
    await transaction(() async {
      for (final t in allTables) {
        await delete(t).go();
      }
    });
  }

  /// `shareAcrossIsolates`: aynı isimdeki DB'yi açan tüm isolate'ler (ör.
  /// `background_sync.dart`'taki workmanager isolate'i) drift'in kendi
  /// isolate-server'ı üzerinden TEK gerçek bağlantıya yönlendirilir — hem
  /// eşzamanlı erişimde "database is locked" (Crashlytics'te görülen
  /// PRAGMA user_version / babies SELECT çökmeleri) engellenir, hem de
  /// stream'ler isolate'ler arası otomatik senkron kalır (eskiden elle
  /// `refreshSyncedStreams()` çağrılarak düzeltiliyordu, artık gerek yok).
  /// `busy_timeout` ek güvenlik ağı: paylaşılan
  /// bağlantı dışında kalan kısa süreli kilitlerde crash yerine bekler.
  static QueryExecutor _open() => driftDatabase(
        name: 'adena',
        native: DriftNativeOptions(
          shareAcrossIsolates: true,
          setup: (db) => db.execute('PRAGMA busy_timeout = 5000;'),
        ),
      );
}
