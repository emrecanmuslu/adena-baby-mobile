import 'dart:async';
import 'dart:io' show File;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:uuid/uuid.dart';

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
  // v15 (O4/R6): aile ayarı profilden AYRI bayrak; `settingsBase` = sunucunun
  // son onayladığı JSON (K-5 değişen-alan diff'i için). `pushError` K-1.
  BoolColumn get settingsDirty => boolean().withDefault(const Constant(false))();
  TextColumn get settingsBase => text().nullable()();
  TextColumn get pushError => text().nullable()();

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
  TextColumn get pushError => text().nullable()(); // v15, K-1

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
  TextColumn get pushError => text().nullable()(); // v15, K-1

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
  TextColumn get pushError => text().nullable()(); // v15, K-1
  // v15 (M2): sunucunun son onayladığı ayar JSON'u — dirty PATCH yalnız bundan
  // FARKLI alanları gönderir (aile ayarı `settingsBase` ile aynı yöntem).
  TextColumn get baseJson => text().nullable()();

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

  TextColumn get pushError => text().nullable()(); // v15, K-1

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
  // v15 (K4/O21, R5/R6): satır başına delta push. `dirty` varsayılanı FALSE
  // (diğer tabloların tersine): pull'dan gelen/katalogdan türeyen satır temiz
  // doğar, yalnız kullanıcı işaretlemesi dirty yapar. `serverUpdatedAt` backend
  // #1 gelince pull'da dolar. `pushError` K-1.
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();
  DateTimeColumn get clientUpdatedAt => dateTime().nullable()();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  TextColumn get pushError => text().nullable()();

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

/// İlaç/vitamin planı — local-first, AİLE PAYLAŞIMLI (v14'ten beri): plan
/// `/babies/{id}/medication-plans/sync` ile diğer üyelere aynalanır (bkz.
/// HealthRepository.syncMedicationPlans). "Verildi" durumu BURADA tutulmaz — o
/// `Records` (RecordType.medication) ile takip edilir; bu tablo yalnız
/// ZAMANLAMAYI (ad/doz/saatler) taşır. Bildirim kimliği olarak yerel
/// autoincrement `localId` kullanılır (cihaza özel); sunucuyla ortak kimlik
/// `uuid`'dir (v13'ten kalan satırlarda null → ilk senkronda atanır).
@DataClassName('MedicationPlanRow')
class MedicationPlans extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get baby => text()();
  TextColumn get name => text()();
  TextColumn get dose => text().withDefault(const Constant(''))();
  /// Günlük saatler, JSON dizi ("HH:MM"), ör. '["09:00","21:00"]'.
  TextColumn get timesJson => text().withDefault(const Constant('["09:00"]'))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  // ── Senkron (Records'taki _SyncCols ile aynı anlam) ──
  TextColumn get uuid => text().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get clientUpdatedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  // ── İlaç v2 (v16, ILAC-TASARIM §1a) ──
  /// 'scheduled' | 'prn' (ihtiyaç halinde — saatsiz).
  TextColumn get kind => text().withDefault(const Constant('scheduled'))();
  /// 'daily' | 'interval' | 'every_n_days' | 'weekly'.
  TextColumn get freq => text().withDefault(const Constant('daily'))();
  IntColumn get intervalHours => integer().nullable()();
  IntColumn get everyNDays => integer().nullable()();
  /// ISO hafta günleri (1=Pzt … 7=Paz), JSON dizi.
  TextColumn get weekdaysJson => text().withDefault(const Constant('[]'))();
  /// Yerel takvim günü 'YYYY-MM-DD' (saat dilimsiz). Bitiş dahil; null = süresiz.
  TextColumn get startDate => text().nullable()();
  TextColumn get endDate => text().nullable()();
  IntColumn get prnMinIntervalMin => integer().nullable()();
  IntColumn get prnMaxPerDay => integer().nullable()();
  /// Duraklatma geçmişi: [[from_iso, to_iso|null]] (UTC ISO).
  TextColumn get pausesJson => text().withDefault(const Constant('[]'))();
  /// Zamanlama (saatler/sıklık) en son ne zaman değişti — öncesi için beklenen
  /// doz üretilmez (geçmiş ekranı / "Dün nasıl geçti?").
  DateTimeColumn get scheduleFrom => dateTime().nullable()();
  /// Sunucunun reddettiği değişiklik (ör. 'invalid'); null = sorun yok.
  TextColumn get pushError => text().nullable()();
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
  MedicationPlans,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes(m);
          await _createLocalFirstIndexes(m);
        },
        onUpgrade: (m, from, to) async {
          // I4 (INCELEME): drift migration'ı transaction'a ALMAZ ve
          // user_version'ı onUpgrade bittikten SONRA yazar → yarıda kesilen
          // migration'da (OOM/force-stop) eklenen kolonlar kalır, sürüm eski
          // kalır; sonraki açılış "duplicate column" ile DB'yi hiç açamazdı.
          // İki savunma: (1) tüm adımlar TEK transaction (kesinti → geri alınır;
          // PRAGMA journal_mode/busy_timeout `_open` setup'ında, transaction
          // dışında), (2) `_addColumnIfMissing` — transaction commit'i ile
          // user_version yazımı arasındaki ms penceresi için kolon varsa atlar;
          // backfill UPDATE'leri idempotent.
          await transaction(() async {
          if (from < 2) {
            await _addColumnIfMissing(m, records, records.createdBy);
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
          // M1 (2026-10-11): from<4 yolu bebek/anı/anne/adet tablolarını GÜNCEL
          // (v15) tanımla kurar → sonraki addColumn adımları aynı kolonu tekrar
          // eklemeye çalışıp "duplicate column" ile düşüyordu (v2/v3 kurulumları
          // hiç güncellenemiyordu). O tablolara kolon ekleyen her adım `from >= 4`
          // ile korunur (migration_all_versions_test).
          if (from >= 4 && from < 5) {
            // Hesap-kapsamlı yerel izolasyon: mevcut satırlar accountId=NULL
            // (sahipsiz → hiçbir hesaba gösterilmez). CycleSettings hesaba özel
            // (id=accountId) olur; eski 'me' satırı sahipsiz kalır.
            await _addColumnIfMissing(m, babies, babies.accountId);
            await _addColumnIfMissing(m, cycleEntries, cycleEntries.accountId);
          }
          if (from >= 4 && from < 6) {
            // Prematüre desteği: doğumdaki gebelik yaşı kolonları.
            await _addColumnIfMissing(m, babies, babies.gestationalWeeks);
            await _addColumnIfMissing(m, babies, babies.gestationalDays);
          }
          if (from < 7) {
            // Sağlık local-first: aşı/gelişim/diş durumu + hatırlatıcılar yerelde.
            await m.createTable(healthStatuses);
            await m.createTable(localReminders);
          }
          if (from >= 4 && from < 8) {
            // Adet tahmin ayarları: döngü uzunluğu artık yerelde de saklanır
            // (eskiden kolon yoktu → değişiklik kaydolmuyordu) + adet/luteal süresi.
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.expectedCycleLength);
            await _addColumnIfMissing(m, cycleSettingsTable, cycleSettingsTable.periodLength);
            await _addColumnIfMissing(m, 
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
          if (from >= 4 && from < 10) {
            // Akıllı tahmin toggle (My Calendar pariteli) yerelde de saklanır.
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.smartPrediction);
          }
          if (from >= 4 && from < 11) {
            // Takvim haftanın ilk günü (Pazar/Pazartesi) ayarı.
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.weekStartsSunday);
          }
          if (from >= 4 && from < 12) {
            // Yaşam-döngüsü (Flo-tarzı): adet ↔ TTC ↔ gebelik ↔ postpartum ↔ kayıp.
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.lifecycleMode);
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.ttcStartedAt);
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.predictionsHidden);
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.lastLossDate);
            await _addColumnIfMissing(m, 
                cycleSettingsTable, cycleSettingsTable.learningWindow);
          }
          if (from < 13) {
            // İlaç/vitamin takip planları (zamanlama; "verildi" durumu Records'ta).
            await m.createTable(medicationPlans);
          }
          if (from >= 13 && from < 14) {
            // İlaç planları aile paylaşımına alındı: senkron kolonları. Mevcut
            // satırlar dirty=true varsayılanıyla ilk senkronda yüklenir.
            // (from < 13 ise tablo az önce güncel şemayla kuruldu.)
            await _addColumnIfMissing(m, medicationPlans, medicationPlans.uuid);
            await _addColumnIfMissing(m, medicationPlans, medicationPlans.isDeleted);
            await _addColumnIfMissing(m, medicationPlans, medicationPlans.clientUpdatedAt);
            await _addColumnIfMissing(m, medicationPlans, medicationPlans.dirty);
          }
          if (from < 15) {
            // v15 (TASARIM-SENKRON.md §5A): pushError (K-1), sağlık delta
            // kolonları (K4), aile ayarı bayrağı (O4). addColumn YALNIZ tablo bu
            // upgrade'de yeniden kurulmadıysa (from<4 / from<7 yolları tabloyu
            // zaten v15 şemasıyla createTable etti).
            if (from >= 4) {
              await _addColumnIfMissing(m, babies, babies.settingsDirty);
              await _addColumnIfMissing(m, babies, babies.settingsBase);
              await _addColumnIfMissing(m, babies, babies.pushError);
              await _addColumnIfMissing(m, memories, memories.pushError);
              await _addColumnIfMissing(m, momEntries, momEntries.pushError);
              await _addColumnIfMissing(m, cycleSettingsTable, cycleSettingsTable.pushError);
              await _addColumnIfMissing(m, cycleSettingsTable, cycleSettingsTable.baseJson);
              await _addColumnIfMissing(m, cycleEntries, cycleEntries.pushError);
            }
            if (from >= 7) {
              await _addColumnIfMissing(m, healthStatuses, healthStatuses.dirty);
              await _addColumnIfMissing(m, healthStatuses, healthStatuses.clientUpdatedAt);
              await _addColumnIfMissing(m, healthStatuses, healthStatuses.serverUpdatedAt);
              await _addColumnIfMissing(m, healthStatuses, healthStatuses.pushError);
            }
            // Backfill (kararlar, §5A/§5B/§5C):
            // - K-4: gelişim/dişte done=true → dirty (bir kez push); AŞIDA YOK
            //   (ilk v15 turunda sunucu kazanır — yanlış "yapıldı" tehlikeli).
            // - O4: yalnız SAHİP satırlarında (my_role NULL/owner) dolu ayar JSON'u
            //   → settingsDirty (bir kez tam sözlük PATCH). Üye/caregiver yok.
            await m.database.customStatement(
                "UPDATE health_statuses SET dirty = 1 "
                "WHERE done = 1 AND kind IN ('milestone', 'tooth')");
            await m.database.customStatement(
                "UPDATE babies SET settings_dirty = 1 "
                "WHERE settings != '{}' AND (my_role IS NULL OR my_role = 'owner')");
          }
          if (from >= 13 && from < 16) {
            // v16 (İlaç v2): plan türü/sıklık/kür/PRN/duraklatma geçmişi/zamanlama
            // çapası + sunucu ret nedeni. (from < 13 ise tablo az önce güncel
            // şemayla kuruldu.) Başlangıç günü ve çapa created_at'ten doldurulur.
            for (final c in [
              medicationPlans.kind,
              medicationPlans.freq,
              medicationPlans.intervalHours,
              medicationPlans.everyNDays,
              medicationPlans.weekdaysJson,
              medicationPlans.startDate,
              medicationPlans.endDate,
              medicationPlans.prnMinIntervalMin,
              medicationPlans.prnMaxPerDay,
              medicationPlans.pausesJson,
              medicationPlans.scheduleFrom,
              medicationPlans.pushError,
            ]) {
              await _addColumnIfMissing(m, medicationPlans, c);
            }
            await m.database.customStatement(
                "UPDATE medication_plans SET start_date = "
                "date(created_at, 'unixepoch', 'localtime') "
                "WHERE start_date IS NULL AND created_at IS NOT NULL");
            await m.database.customStatement(
                "UPDATE medication_plans SET schedule_from = created_at "
                "WHERE schedule_from IS NULL AND created_at IS NOT NULL");
            // V2 (ILAC-INCELEME-2): v13'ten kalan, hiç senkronlanmamış (free/tek
            // kullanıcı) satırların ortak kimliği yoktu → v2 planlayıcısı onları
            // atlıyordu. Burada atanır (senkronda atanmasını bekleme).
            final missing = await m.database
                .customSelect('SELECT local_id FROM medication_plans WHERE uuid IS NULL')
                .get();
            for (final r in missing) {
              await m.database.customStatement(
                  'UPDATE medication_plans SET uuid = ? WHERE local_id = ?',
                  [const Uuid().v4(), r.read<int>('local_id')]);
            }
          }
          await debugMigrationHook?.call();
          });
        },
      );

  /// Yalnız test (I4): migration transaction'ının SONUNDA çağrılır; fırlatırsa
  /// o açılıştaki tüm migration adımları geri alınır (kesinti simülasyonu).
  @visibleForTesting
  static Future<void> Function()? debugMigrationHook;

  /// I4: kolon zaten varsa (yarıda kesilmiş önceki migration) `ALTER TABLE ADD
  /// COLUMN` tekrarlanmaz — "duplicate column name" DB'yi kalıcı kilitlemesin.
  Future<void> _addColumnIfMissing(
      Migrator m, TableInfo table, GeneratedColumn column) async {
    final rows = await m.database
        .customSelect('PRAGMA table_info(${table.actualTableName})')
        .get();
    for (final r in rows) {
      if (r.read<String>('name') == column.$name) return;
    }
    await m.addColumn(table, column);
  }

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

  /// Kilit hatasında transaction'ın en çok kaç kez BAŞTAN deneneceği.
  static const lockRetryDelays = [
    Duration(milliseconds: 150),
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
  ];

  static final _txZoneKey = Object();

  /// Üst düzey transaction'ları SQLite kilit hatalarında BAŞTAN yeniden dener.
  ///
  /// `SQLITE_BUSY_SNAPSHOT` (517): WAL'da bu bağlantının okuma görüntüsü,
  /// başka bir bağlantı yazdığı için bayatladı. `busy_timeout` bunu ÇÖZMEZ —
  /// SQLite belgesine göre tek çare transaction'ı yeniden başlatmaktır (taze
  /// görüntüyle). 261/5/6 (locked/busy) da aynı şekilde geçicidir. Birincil
  /// önlem tek-yazar kapısıdır (DbOwnerGate); bu, ön plan olmadan açılan arka
  /// plan bağlantısıyla kalan nadir çakışmalar içindir (2026-10-15 olayı).
  ///
  /// İç içe transaction'lar yeniden denenmez (dış transaction tamamını dener).
  /// Gövde yeniden çalıştığından içindeki Dart yan etkileri idempotent olmalı —
  /// mevcut gövdeler satırları transaction içinde yeniden okur.
  @override
  Future<T> transaction<T>(Future<T> Function() action,
      {bool requireNew = false}) async {
    if (Zone.current[_txZoneKey] == true) {
      return super.transaction(action, requireNew: requireNew);
    }
    for (var attempt = 0;; attempt++) {
      try {
        return await runZoned(
            () => super.transaction(action, requireNew: requireNew),
            zoneValues: {_txZoneKey: true});
      } catch (e) {
        if (attempt >= lockRetryDelays.length || !isSqliteLockError(e)) rethrow;
        debugPrint('[db] kilit hatası, transaction yeniden deneniyor '
            '(${attempt + 1}/${lockRetryDelays.length}): $e');
        await Future.delayed(lockRetryDelays[attempt]);
      }
    }
  }

  /// SQLite kilit/meşgul hatası mı (5 BUSY, 6 LOCKED, 261 BUSY_RECOVERY,
  /// 517 BUSY_SNAPSHOT, 262 LOCKED_SHAREDCACHE …)? drift uzak isolate'ten
  /// `DriftRemoteException` içinde metin olarak taşıdığı için mesajdan bakılır.
  static bool isSqliteLockError(Object e) {
    final s = e.toString();
    return s.contains('database is locked') ||
        s.contains('database table is locked') ||
        RegExp(r'SqliteException\((5|6|261|262|517|773)\)').hasMatch(s);
  }

  /// Ön plan stream sorgularını ZORLA yeniden çalıştırır (drift `notifyUpdates`).
  ///
  /// Drift stream'leri yalnız KENDİ bağlantısındaki yazımları izler. Arka plan
  /// isolate'i (workmanager bg sync) ayrı bir bağlantıyla aynı SQLite dosyasına
  /// kayıt yazıp cursor'ı ilerletince, ön plandaki bu bağlantının stream'leri o
  /// yazımdan HABERSİZ kalır → warm-resume'da Home bayat görünür, pull-refresh
  /// no-op olur (cursor ilerlemiş, sunucu boş döner → ön plan da yazmaz → emit
  /// yok) ve yalnız tam kapat-aç düzeltir. Öne gelişte + her sync turundan sonra
  /// çağrılır: tüm sync'li tablo stream'leri dosyayı yeniden okur.
  ///
  /// NOT: `shareAcrossIsolates` denemesi bunu gereksiz kılıyordu ama çok daha
  /// kötü bir hataya yol açtı (bkz. [_open]) — bilinçli olarak geri getirildi.
  void refreshSyncedStreams() {
    notifyUpdates({
      TableUpdate.onTable(records),
      TableUpdate.onTable(babies),
      TableUpdate.onTable(memories),
      TableUpdate.onTable(momEntries),
      TableUpdate.onTable(cycleSettingsTable),
      TableUpdate.onTable(cycleEntries),
      TableUpdate.onTable(healthStatuses),
      TableUpdate.onTable(localReminders),
      TableUpdate.onTable(medicationPlans),
    });
  }

  /// Tüm yerel verileri siler (hesapsız "yerel verileri sil" / GDPR). Şema kalır,
  /// satırlar gider — kullanıcı sıfırdan başlar.
  /// KB-9: hesap silme sunucuda BAŞARDIKTAN sonra yalnız o hesabın yerel
  /// kapsamı silinir (başka hesap/misafir verisi kalır). Döner: silinen
  /// bebeklerin foto yolları + anıların yerel foto yolları (çağıran dosyaları
  /// siler) ve bebek id'leri (bildirim iptali için slot'lar çağıranda).
  Future<({List<String> babyIds, List<String> photoPaths})> wipeAccountData(
      String accountId) async {
    final ownBabies = await (select(babies)..where((b) => b.accountId.equals(accountId))).get();
    final ids = ownBabies.map((b) => b.id).toList();
    final photos = <String>[
      for (final b in ownBabies)
        if (b.photo != null && !b.photo!.startsWith('http')) b.photo!,
    ];
    if (ids.isNotEmpty) {
      for (final m in await (select(memories)..where((m) => m.baby.isIn(ids))).get()) {
        if (m.localPhotoPath != null) photos.add(m.localPhotoPath!);
      }
    }
    await transaction(() async {
      if (ids.isNotEmpty) {
        await (delete(records)..where((r) => r.baby.isIn(ids))).go();
        await (delete(memories)..where((m) => m.baby.isIn(ids))).go();
        await (delete(momEntries)..where((m) => m.baby.isIn(ids))).go();
        await (delete(healthStatuses)..where((h) => h.baby.isIn(ids))).go();
        await (delete(localReminders)..where((r) => r.baby.isIn(ids))).go();
        await (delete(medicationPlans)..where((p) => p.baby.isIn(ids))).go();
        await (delete(syncCursors)..where((c) => c.baby.isIn(ids))).go();
        await (delete(babies)..where((b) => b.id.isIn(ids))).go();
      }
      await (delete(cycleEntries)..where((e) => e.accountId.equals(accountId))).go();
      await (delete(cycleSettingsTable)..where((s) => s.id.equals(accountId))).go();
    });
    return (babyIds: ids, photoPaths: photos);
  }

  Future<void> wipeAllData() async {
    await transaction(() async {
      for (final t in allTables) {
        await delete(t).go();
      }
    });
  }

  /// Her isolate KENDİ sqlite bağlantısını açar (`shareAcrossIsolates` KAPALI).
  ///
  /// ⚠️ Bir dönem `shareAcrossIsolates: true` kullanıldı (bkz. 2a3a218) — ön plan
  /// ile workmanager arka plan isolate'i drift'in spawn ettiği TEK sunucu
  /// isolate'ini paylaşıyordu. iOS'ta BGTask'ı işletim sistemi başlatıp aniden
  /// yıkıyor; o sunucu isolate'i (ve process-global `IsolateNameServer` kayıtları)
  /// tutarsız kalınca drift_flutter'ın yeniden-bağlanma döngüsü (`while (true)`,
  /// toplam timeout'u YOK) ve drift'in timeout'suz remote sorguları yüzünden
  /// **tüm `watch()` stream'leri sessizce sonsuza kadar loading'de kalıyordu**:
  /// uygulama açılıyor ama Son Aktivite/Bugün/Günlük Akış hep skeleton, sync
  /// şeridi hiç kapanmıyor, yalnız uygulamayı öldürüp açmak düzeltiyordu.
  /// Bebek listesi görünmeye devam ettiği için (tek-seferlik `getAll()` ile
  /// state'e girmiş) bug "veri kayboldu" gibi değil "her yer skeleton" gibi
  /// görünüyordu. Bkz. [[drift-shareacrossisolates-skeleton-bugu]].
  ///
  /// O commit'in ASIL çözdüğü "database is locked" çökmesi `shareAcrossIsolates`
  /// değil `busy_timeout` sayesindeydi; burada onu koruyup üstüne **WAL** ekliyoruz:
  /// WAL'da okuyucular yazarı bloklamaz, busy_timeout da kalan kısa kilitlerde
  /// crash yerine bekletir. Bağlantılar bağımsız olduğu için arka plan
  /// isolate'inin yaşam döngüsü ön planı ARTIK ETKİLEYEMEZ.
  ///
  /// Bedeli: ayrı bağlantıların stream'leri birbirinin yazımını duymaz →
  /// [refreshSyncedStreams] (öne gelişte + sync sonrası) bunu telafi eder.
  ///
  /// ⚠️ **Prepared statement önbelleği KAPALI** (2026-10-15, iOS "Senkron
  /// sorunu yalnız kapat-aç ile geçiyor"). drift varsayılanı ifadeleri önbellekte
  /// tutar; bir yazım `SQLITE_BUSY_SNAPSHOT` (517) ile düşünce o ifade sıfırlanmadan
  /// önbellekte kalıyor ve bağlantının okuma görüntüsünü ESKİ anda tutuyordu →
  /// sonraki HER yazım (yeni transaction'lar dahil) yine 517 alıyor, yalnız süreç
  /// ölünce düzeliyordu. `test/data/db_single_writer_test.dart` bunu gerçek iki
  /// bağlantıyla üretir: önbellek açıkken yeniden denemeler sonsuza dek düşer,
  /// kapalıyken ilk yeniden deneme geçer. (Benzer kök: libsql-js#240.) Bedeli
  /// ihmal edilebilir: her sorguda SQL yeniden derlenir (mikrosaniyeler).
  /// `driftDatabase()` bu ayarı dışarı açmadığından bağlantı burada, onunla AYNI
  /// dosya yolu (`<Documents>/adena.sqlite`) ve geçici dizin ayarıyla kurulur.
  static QueryExecutor _open() => DatabaseConnection.delayed(Future(() async {
        if (!_sqliteConfigured) {
          // sqlite3'ün geçici dosyaları için erişilebilir dizin (sandbox; Android
          // /tmp'ye yazamaz) — drift_flutter'ın yaptığının aynısı.
          sqlite3.tempDirectory = (await getTemporaryDirectory()).path;
          _sqliteConfigured = true;
        }
        final dir = await getApplicationDocumentsDirectory();
        return NativeDatabase.createBackgroundConnection(
          File(p.join(dir.path, 'adena.sqlite')),
          setup: (db) => applyPragmas(db.execute),
          cachePreparedStatements: false,
        );
      }));

  static bool _sqliteConfigured = false;

  /// Açılışta uygulanan PRAGMA'lar. `exec` üzerinden çalışır (sqlite3 tipine
  /// bağlanmadan test edilebilsin diye — bkz. `test/data/db_pragmas_test.dart`).
  ///
  /// ⚠️ SIRA ÖNEMLİ ve testle korunuyor: `busy_timeout` YALNIZ kendisinden
  /// sonraki işlemlere uygulanır. v1.4.16–v1.4.17'de WAL pragma'sı önce
  /// geliyordu; WAL'a geçiş kısa bir özel kilit istediği ve o an yürürlükteki
  /// timeout 0 olduğu için, arka plan isolate'i dosyaya dokunuyorken açılan ön
  /// plan bağlantısı BEKLEMEDEN düşüyordu:
  /// `SqliteException(261): database is locked ... PRAGMA journal_mode = WAL`
  /// (iOS 1.4.17'de 30 olay). İstisna `setup`tan kaçınca DB hiç açılmıyor ve
  /// fatal FlutterError'a dönüşüyordu.
  static void applyPragmas(void Function(String sql) exec) {
    // Isolate'ler artık drift tarafından serileştirilmediği (shareAcrossIsolates
    // KAPALI) için kilit çakışması mümkün → 5s yerine 8s tolerans. İLK sırada
    // olmalı ki bundan sonraki her ifade bu toleranstan yararlansın.
    exec('PRAGMA busy_timeout = 8000;');
    // WAL kalıcıdır (dosyaya yazılır); her açılışta idempotent.
    //
    // Hatası YUTULUR çünkü WAL bir optimizasyondur, zorunluluk değil: dosya
    // hangi journal modundaysa DB çalışmaya devam eder. Buraya düşmek için
    // kilidin 8 sn boyunca açılmaması gerekir; o hâlde de doğru davranış
    // "mevcut modda devam et", uygulamayı açılışta düşürmek değil.
    try {
      exec('PRAGMA journal_mode = WAL;');
    } catch (_) {
      // Bilinçli sessiz: bkz. yukarıdaki not. DB kullanılabilir kalır.
    }
  }
}
