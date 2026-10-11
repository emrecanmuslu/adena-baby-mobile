# INCELEME — fix/audit-bulgular bağımsız kod incelemesi (2026-10-11)

Kapsam: `git diff main...fix/audit-bulgular` (104 commit, 173 dosya; lib'de 87 dosya / +5007 −696), BULGULAR.md, TASARIM-SENKRON.md, FINAL-RAPOR.md, KARAR-BEKLEYEN.md, YAYIN-KONTROL.md. Yöntem: önceki oturumun gerekçelerinden bağımsız kod okuması; backend davranışı için `../api/apps/*` kaynağına bakıldı; drift migration davranışı için drift 2.34.3 kaynağı okundu; iki şüphe geçici testle doğrulandı (test silindi, commit'lenmedi). `flutter analyze` temiz, `flutter test` **1243 geçti / 0 düştü** (bu incelemede koşuldu).

Not: Odak 4/5/6/7 için planlanan iki paralel alt-inceleme oturum limiti nedeniyle hiç çalışamadı; bu alanlar daha yüzeysel (diff okuması + örneklem test) incelendi ve §4/§5'te buna göre işaretlendi.

---

## 1. Özet

| Önem | Sayı | Kimlik |
|---|---|---|
| KRİTİK | 1 | I1 |
| ORTA | 4 | I2, I3, I4, I5 |
| DÜŞÜK | 9 | I6–I14 |
| ŞÜPHELİ (kanıtsız/teorik) | 2 | I15, I16 |

> **Düzeltme turu (2026-10-11, aynı gün):** I1–I16 ele alındı — I1..I11, I13, I16 KODDA düzeltildi (hash'ler tabloda), I12 KB-11, I14/I15 belgelendi; GRUP D (D4/D9/D10/D26/D36/O12/O37 testleri + R4 telemetrisi) tamamlandı. Ayrıntı: §7.

**Genel yargı (düzeltme öncesi): bu hâliyle yayına HAZIR DEĞİL.** Senkron kural seti (R1–R9), `sync_merge` yardımcısı, v15 migration guard'ları, O9 sayfalama, O11 kuyruk, auth epoch/zorunlu çıkış ve K-1 geri-al akışı genel olarak sağlam ve testli. Ancak:

1. **I1 (KRİTİK, veri kaybı):** K-4 "aşıda backfill yok, ilk v15 turunda sunucu kazanır" kararı yalnız *halihazırda premium ve sunucuyla eşit* kullanıcı için güvenli. **Free kullanıcı** (ya da premium'u bitip sonradan yeniden abone olan) v14'te işaretlediği aşılar temiz (dirty=0) satır olarak kalır; premium'a geçince `syncAll` tam turu `MigrationService.pushAll`'dan ÖNCE koşabilir → `pull` sunucunun (henüz boş, lazy üretilen "pending") kümesini temiz satırlara yazar → **tüm aşı tikleri "yapılmadı"ya döner, ardından `pushAll` bu yanlış durumu sunucuya mühürler.** Kod kanıtı ve düzeltme önerisi I1'de. Yayın koşulu: I1 kapatılmadan v15 çıkmamalı.
2. **I2 (ORTA, veri kaybı, DOĞRULANDI):** bebek profil push'u R5'i uygulamıyor; POST sürerken yapılan düzenleme `dirty=false` ile temizleniyor, bir sonraki pull sunucu kopyasıyla eziyor. Aynı desen adet kayıtları bulk'ında (I3). Ucuz düzeltme.
3. **I4 (ORTA):** v15 migration transaction içinde değil (drift böyle çalıştırmıyor); yarıda kesilen migration'da DB kalıcı açılmaz hâle gelir. 14 addColumn + 2 UPDATE için pencere kısa ama geri dönüşsüz.
4. **I5 (ORTA):** O15 "bebeğin TÜM bildirimleri iptal" iddiası özel/randevu hatırlatıcılarını kapsamıyor; mutabakat kümesi tombstone bebeklerin hatırlatıcılarını "aktif" saydığı için bunlar sonsuza dek çalmaya devam eder.

Koşul: I1 + I2/I3 + I4 düzeltilip (I5 tercihen) cihaz listesi (YAYIN-KONTROL §1: 9, 10, 12, 15, 29) koşulduktan sonra kademeli yayın.

---

## 2. Bulgular

| ID | Önem | Dosya:satır | Sorun | Kanıt | Öneri |
|---|---|---|---|---|---|
| **I1** | **KRİTİK** | `lib/data/health_repository.dart:629-651` (`pull.apply`), `lib/data/local/app_database.dart:380-382` (backfill), `lib/features/records/record_controller.dart:296-303` (`_syncHealth` pullToo), `lib/data/migration_service.dart:164-184` (pushAll son adım) | Free→premium (ve lapse→yeniden abone) kullanıcıda v14'te işaretlenmiş aşı tikleri kaybolur. v14 `_setStatus` dirty yazmıyordu (`git show main:lib/data/health_repository.dart:68-76`); v15 backfill'i aşıyı dışlar (`kind IN ('milestone','tooth')`); `pull.apply` temiz satıra `done=false` yazar ("işaret kaldırma yayılır"). Backend `VaccinesView.get` kayıt yoksa takvimi **lazy üretir, hepsi pending** (`../api/apps/health/views.py:74-88`). Premium açılınca `babyCloudEligible` true olur; `syncAll(sharedOnly:false)` (öne geliş/kayıt/`requestSyncSoon`) `_syncHealth(pullToo:true)` → `pull` koşar; `MigrationService.run` ise `localToCloudMigrationProvider` ile aynı anda başlar ve `pushAll` **son adımdır**. syncAll'da göç bitimini bekleyen bir kapı yok (`grep premiumSynced lib/features/records/record_controller.dart` → boş). Satın alma sırasında uygulama mağaza sayfasına gidip döner → öne geliş → tam tur; pull büyük olasılıkla pushAll'dan önce koşar. | `test/data/health_repository_k4_test.dart:186-199` bu davranışı **istenen** olarak sabitler ("temiz done=true, sunucu pending → yapılmadı"); TASARIM §5B'deki "tek cihazlı kullanıcıda etki yok" varsayımı yalnız sunucuyla zaten eşit premium kullanıcı için doğrudur, free kullanıcıda sunucu kümesi boştur. | (a) **Kapı:** sahip bebeklerde sağlık `pull`'u yalnız `LocalSession.premiumSyncedForAccount(acct)` true iken (göç `pushAll` bitmiş) koş; paylaşılan bebekte kapı yok. (b) **Ek güvence:** v15 backfill'i aşıda da `done=1 AND my_role NULL/owner` satırları dirty yapsın — tek cihazlı premium'da push no-op'tur (sunucu zaten done), "kaldırılan tik geri gelir" riski yalnız çok-cihazlı ve ayrışmış ailede var; o risk de kayıp tikten hafif. (c) En azından pull'da "temiz done=true → sunucu pending" geçişini saymakla kalmayıp (TASARIM'daki Crashlytics sayacı kodda YOK) ilk turda uygulamamak. Hangi seçenek olursa olsun K4 testine "free→premium: pushAll öncesi pull aşıyı sıfırlamaz" senaryosu eklenmeli. **DÜZELTİLDİ `a4161f9`** |
| **I2** | **ORTA** (DOĞRULANDI) | `lib/data/baby_repository.dart:528-529` | `pushDirty` 2xx sonrası `dirty=false, pushError=null` **koşulsuz** yazar; POST (özellikle multipart foto, saniyeler) sürerken yapılan `update()` düzenlemesi temizlenir → yerelde temiz ama sunucuda yok → bir sonraki `pullFromServer` sunucu kopyasını uygular, düzenleme kaybolur. R5 ("gönderilen damga ≠ mevcut damga ise dirty kalır") TASARIM §2'de yazılı, `pushSettings` (`unchangedMeanwhile`) ve records/health uyguluyor, profil push'u uygulamıyor. | Geçici test (silindi): yavaş adapter içinde `repo.update('b1', {'name':'Yeni'})` → push bitince satır `name=Yeni dirty=false` (beklenen `dirty=true`). | Gönderim öncesi `clientUpdatedAt`+içerik (ad/foto/alanlar) yakala; yanıt sonrası satır değiştiyse yalnız `pushError=null` yaz, dirty'ye dokunma (health `_clearDirtyIfUnchanged` deseni). Regresyon testi ekle. **DÜZELTİLDİ `562618e`** |
| **I3** | **ORTA** (aynı desen, test edilmedi) | `lib/data/cycle_repository.dart:604-609` (bulk `saved` → dirty=false), `lib/data/mom_repository.dart:273-276`, `lib/data/memory_repository.dart:316-323` | Adet kaydı: `saveEntry` aynı güne mevcut id'yle UPDATE yapar; bulk uçuştayken aynı günü yeniden düzenleyen kullanıcı `saved` ile temizlenir → pull sunucu kopyasını yazar (düzenleme kaybı). Anı/anne'de düzenleme yolu yok; ama uçuşta `delete()` çağrılırsa tombstone `dirty=false` olur → DELETE bir daha gönderilmez, satır yerelde gizli/sunucuda canlı "zombi" kalır (R4 adayı da değil: deleted). | `_pushDirtyEntries` `sentStamp` tutmuyor; records `_applySyncResponse` ise `cur.clientUpdatedAt == sent.stamp && data == …` ile koşulluyor (`record_repository.dart:274-287`). | Bulk upsert'lerde gönderilen `clientUpdatedAt` (+ `isDeleted`) saklanıp temizlik buna koşullansın (3 repo). **DÜZELTİLDİ `1f51066`** |
| **I4** | **ORTA** | `lib/data/local/app_database.dart:262-387` (`onUpgrade`) | Migration transaction'da değil. drift `NativeDatabase` → `_SqliteVersionDelegate extends DynamicVersionDelegate` (`drift-2.34.3/lib/src/sqlite3/database.dart:204`); `_runMigrations` önce `beforeOpen` (onUpgrade) çalıştırır, **sonra** `setSchemaVersion` yazar (`engines.dart:556-563`) — transaction sarmalı yok. v14→v15'te 14 `addColumn` + 2 `UPDATE` arasında süreç ölürse `user_version=14` kalır; sonraki açılışta `addColumn` "duplicate column" → DB hiç açılmaz (M1'in v2/v3'te bulduğu hatanın aynısı, bu kez her kullanıcı için üretilebilir). WAL + bg isolate eşzamanlı açılışta busy_timeout koruyor; ama OOM/force-stop korumuyor. | Mevcut adımlar da aynı risk altındaydı; v15 adım sayısı (16 ifade) ve kademeli yayın planı bunu "kabul edilmiş risk" olmaktan çıkarır. | `onUpgrade` gövdesini `await m.database.transaction(() async { … })` içine al (drift docs'un önerdiği desen; `PRAGMA foreign_keys` kapalıyken). Alternatif/ek: `addColumn` öncesi `PRAGMA table_info` ile kolon varsa atla. Migration testine "yarıda kesilmiş v14.5 DB'den açılış" senaryosu. **DÜZELTİLDİ `d5fe1fc`** |
| **I5** | **ORTA** | `lib/core/notification_service.dart:764-786` (`cancelBabyScheduled`), `lib/data/health_repository.dart:218-225` (`activeReminderIds`), `lib/features/babies/baby_controller.dart:91-95` | Bebek silinince (tombstone; `localReminders` satırları purge DIŞINDA silinmiyor) özel/randevu hatırlatıcıları (id = `localReminders.localId`, `< _cycleBase`) iptal listesinde yok. Üstelik K1 mutabakatı `activeReminderIds()` ile yapılıyor ve bu sorgu **bebek tombstone'una bakmıyor** → silinen bebeğin hatırlatıcıları "aktif" sayılır, hiçbir sync onları yetim görmez. Sonuç: silinmiş bebek için "aşı randevusu"/periyodik hatırlatıcı çalmaya devam eder. YAYIN-KONTROL adım 15 yalnız "aşı/ilaç/beslenme" kontrol ediyor; bu durumu yakalamaz. | `cancelBabyScheduled` id listesi: feed/sleep/breast/vaccine/leap/growth/pregWeek/milestone/tooth + ilaç; `localReminders` yok. `activeReminderIds`: `where enabled` yalnız. | `deleteBaby`'de bebeğin `localReminders` id'lerini de iptal et (ya da satırları sil); `activeReminderIds` `babies.isDeleted=false` ile join'lensin. Test: iki bebek, biri silinir → onun özel hatırlatıcısı pending'de kalmaz. **DÜZELTİLDİ `92c5818`** |
| I6 | DÜŞÜK | `lib/core/notification_service.dart:311` | D18 zaman tabanlı id: `(ms ~/ 10) % 50` → 500 ms periyotlu halka. Ardışık iki aile bildirimi arası 500 ms'nin katı (±10 ms) ise aynı id → üst üste yazılır; pratikte rastgele ~%2 çarpışma. Eski "bg sayacı 0'dan başlar" hatasından iyi ama "düzeltildi" değil. | Aritmetik. | `(ms ~/ 1000) % 50` (saniye çözünürlüğü) ya da prefs'te kalıcı sayaç. **DÜZELTİLDİ `1f68344`** |
| I7 | DÜŞÜK | `lib/data/baby_repository.dart:500-503, 530-538` | Tombstone bebek DELETE'inde 404 = "zaten yok" özel durumu yok (anı/anne/adet'te var). Başka cihazda silinmiş bebeği silen premium kullanıcı → 404 → `classifyPushFailure` permanent → `pushError='HTTP 404'` → banner "1 değişiklik gönderilemedi / Silme gönderilemedi"; kullanıcı elle "geri al → onayla" yapmak zorunda. | Kod akışı. | DELETE 404 → başarı say (dirty=false), diğer repolarla tutarlı. **DÜZELTİLDİ `d2ac131`** |
| I8 | DÜŞÜK | `lib/features/auth/auth_controller.dart:267-280` | KB-9 `wipeAccountData` `SyncService.whileWiping` ile sarılmamış; o anda süren bir `syncAll` turu (`pullFromServer`/anı pull) silinen hesabın satırlarını yeniden ekleyebilir → "bu cihazda kalmaz" sözü tutulmaz (kapsam kapandığı için görünmez ama diskte kalır). Ayrıca wipe `state=null`'dan ÖNCE koşuyor → bebek akışı boşalınca router bir an onboarding'e gidebilir (I16). | `privacy_screen._wipeLocal` `whileWiping` kullanıyor, `deleteAccount` kullanmıyor. | `whileWiping` ile sar; önce `state=null`/kapsam kapat, sonra sil. **DÜZELTİLDİ `ce58ad2`** |
| I9 | DÜŞÜK | `lib/data/cycle_repository.dart:371-383` (`importFromCloud`) | K8 yolu `_writeSettings(..., dirty:false)` çağırır ama `base` vermez → `baseJson` NULL kalır → kullanıcı ilk `syncIfCloud` GET'i gelmeden (ör. çevrimdışı) ayar değiştirirse M2 diff'i "base yok → tam sözlük" gönderir, `baby:null` dahil. M2'nin kapattığı pencere (bayat null bağ çözer) ilk import ile ilk GET arasında açık kalır. | `_syncSettings` temiz yolu `base:_baseOf(srv)` veriyor, `importFromCloud` vermiyor. | `importFromCloud`'da da `base: _baseOf(srv)` yaz. M2 testine "import sonrası ilk patch yalnız değişen alan" ekle. **DÜZELTİLDİ `6b5518c`** |
| I10 | DÜŞÜK | `lib/data/health_repository.dart:678-684` | `pull` aşıları sunucu `vaccine_name` ile anahtarlar; cihaz dili ≠ sunucu takvimi dili ise katalogta olmayan `itemKey`'lerle temiz yetim satırlar üretilir (ekranda görünmez, `health_statuses` şişer). v14'te yalnız ilk import'ta olurdu, şimdi her tam turda. Veri kaybı yok. | Kod akışı. | Katalogta `key`/`name` eşleşmeyen sunucu kalemlerini yazma; backend #3 gelince kalkar. **DÜZELTİLDİ `593b531`** |
| I11 | DÜŞÜK | `test/i18n/translation_keys_test.dart:9-13` | Test `../api/apps/translations/data/*.json`'ı okur; api repo yoksa **ATLANIR** (CI'da vakum geçer). Yerelde yalnız commit'lenmemiş api çalışma ağacı sayesinde geçiyor (YAYIN-KONTROL §2: 32 anahtar commit bekliyor). api değişikliği kaybolursa mobil CI yeşil kalır. | Dosya başlığı. | api commit'i yayın öncesi zorunlu adım (zaten listede); CI'da api checkout'u yoksa test "skip" yerine en azından uyarı artefaktı üretsin. **DÜZELTİLDİ `63df484`** |
| I12 | DÜŞÜK | `lib/features/babies/baby_controller.dart:149-153` | Her `_pull` (öne geliş, login, geri-al sonrası `refresh`) bulut-uygun **her** bebek için `GET /babies/{id}/settings` → N ek istek/tur. Doğruluk sorunu yok, yük. | Kod akışı. | `pullFromServer` yanıtı `updated_at` taşıyor; ayar GET'ini bebek `updated_at` değiştiğinde ya da tam turda bir kez koş. **KARAR-BEKLEYEN KB-11 (yayın sonrası; kod değişikliği yok)** |
| I13 | DÜŞÜK | `lib/data/health_repository.dart:528-537` (`medicationPlans`) | KB-10 "bakıcıda dirty = sunucuya hiç gitmemiş plan" varsayımı KB-8 öncesi **sunucudaki** bir planı düzenlemiş bakıcı için yanlış: satır dirty ama sunucuda var → kartta "yalnız bu cihazda" etiketi + "Sil" hard-delete → bir sonraki `syncMedicationPlans` planı sunucudan geri indirir (kayıp yok, kafa karışıklığı). İlk sync bu dirty'yi zaten temizlediği için pencere "sync hiç koşmadı" ile sınırlı. | `syncMedicationPlans` readOnly'de `editedMidFlight=false` → sunucu ezer. | `localOnly = caregiver && dirty && uuid-sunucuda-yok` (son sync'teki plan id kümesiyle) ya da yalnızca `uuid == null`/hiç `applied` olmamış satır. **DÜZELTİLDİ `593b531`** |
| I14 | DÜŞÜK | `lib/data/cycle_repository.dart:263-290` (`_writeSettings`) | Her yerel yazım `pushError: null` yazar → kalıcı reddedilmiş ayar (banner'da) kullanıcı başka bir alanı değiştirince banner'dan sessizce düşer; sorun çözülmeden görünürlük kaybolur. Tasarım gereği sayılabilir ("yeni değişiklik yeni deneme") ama §6b'de yazılı değil. | Kod. | Ya belgele ya da yalnız başarılı push/geri al temizlesin. **BELGELENDİ — TASARIM §6b notu (kod değişikliği yok)** |
| I15 | ŞÜPHELİ | `lib/data/local_session.dart:99-107` (`ensureLoaded` birleşim) | O35 yüklemede disk ∪ bellek alır. Bellekte `premiumSynced={acct}` varken başka isolate diskte `clearPremiumSyncedForAccount` yaptıysa birleşim bayrağı diriltir → purge sonrası tam yeniden yükleme atlanır. Pratikte `ensureLoaded` bir kez ve açılışta koştuğu, bg isolate bu bayrağı yazmadığı (K9) için gerçekleşmesi zor; kanıtlanmadı. | Mantık. | Çıkarma işlemleri için ayrı "tombstone" ya da `clear` sonrası `loaded` yeniden yüklemesi. **ŞÜPHELİ, BELGELENDİ — TASARIM §8 notu (kod değişikliği yok)** |
| I16 | ŞÜPHELİ | `lib/features/auth/auth_controller.dart:267-289` | KB-9 wipe sırası: bebek satırları silinir → `babyControllerProvider` boş liste yayar → `state` hâlâ User → router "bebek yok → onboarding" yönlendirmesi yapabilir, ardından `state=null` → login. Görsel sıçrama; cihazda doğrulanmadı. | Sıra. | `state=null` + `setActiveAccount(null)` önce, wipe sonra (acct değişkeni önceden alınır). **DÜZELTİLDİ `ce58ad2`** |

### Sorunsuz bulunan noktalar (kanıtla)
- `sync_merge.decideServerRow/staleLocalIds/classifyPushFailure` kurallara uygun; K-2 korumaları (boş liste, >5 ∧ >%50, 200+parse) doğru uygulanıyor; anı/anne/adet pull'ları `resp.data as List` cast'ini **transaction'dan önce** yapıyor (parse hatası hiçbir şey uygulamaz).
- Backend liste uçları tam liste döndürüyor (DRF sayfalama yok: `config/`de `PAGINATION/PAGE_SIZE` yok; `MemoryListCreate` `is_deleted=False` tam liste; `MomEntriesView` tam; `CycleEntriesView` yalnız istenirse `from/to`). R4 "listede yok → sil" bu koşulda güvenli.
- K2-3b: paylaşılan bebek silinmeden önce `GET /babies/{id}` 403/404 doğrulaması; ağ/5xx → dokunma.
- v15 migration guard'ları: `from<4` yolunda tablolar v15 şemasıyla kurulur, `from>=4`/`from>=7` guard'ları doğru; backfill UPDATE'leri taze tablolarda boş çalışır; v4/v6/v10 gerçekten hiç yayınlanmamış (`git log -S'schemaVersion => 4;'` vb. boş). `settings_dirty` yalnız owner/NULL ve `settings != '{}'`.
- O4: `pullSettings` yalnız `babyCloudEligibleProvider` true bebeklerde (`baby_controller.dart:150`), test `baby_controller_test.dart` M5 bunu `verifyNever` ile sabitliyor; `pushSettings` R5 kontrollü (`unchangedMeanwhile`), caregiver dışlanır, `settingsBase` diff'i anahtar bazlı.
- O9: parça başına `since_cursor` ilerliyor, `applied` D3 içerik karşılaştırmalı; boş dirty'de tek pull POST'u; test 500/500/200 + cursor'ı doğruluyor.
- O11: `_pendingDone` takip turu bitince tamamlanıyor; `?? false` bağlantı bilinmezken beklemiyor; test gerçek.
- Auth: `_epoch` logout/deleteAccount/sessionExpired'da artıyor; `_refreshInBackground/_postLogin/recordConsent/updateName` kuşak kontrollü; refresh tek-uçuş kilidi `finally` ile serbest; `RefreshResult.transient` 401 yerine ağ hatası; refresh token yokken prefs nedeni ezilmiyor (`hasSession` kapısı); `postToken` yalnız başarılı POST'ta işaretliyor ve oturum yokken istek atmıyor; `unregister` hatayı yutuyor → `deleteAccount` her durumda çağrılıyor; bg isolate'te kanca/exitGuest/import/RC başlamıyor (test `auth_controller_test.dart:430-490`).
- Bildirim: O16 sonrası `_alarmMode` izin varsa exact (Android 12-13 varsayılan izinli → etkilenmez); M4 diyalog tek seferlik prefs bayrağı; O14 `_storedInterval` prefs'te (soğuk açılışta aralık değişimi yakalanır; prefs boşsa bir kez yeniden kurulur — kabul edilebilir); `syncCycle` 4 id'yi önce iptal edip yeniden kuruyor (idempotent), `CycleNotifSync` `settings.enabled=false` ve kayıp/postpartum'da (`nextPeriod/fertileStart` null) iptal ediyor.
- K-1: sayaç SQL 6 tabloyu hesap kapsamıyla alıyor; `discard` yolları doğru (anı foto dosyası da silinir); tombstone bebek + 404 → önce çocuk purge, sonra satır; "Tümünü geri al" sunucuda olmayanı sessiz silmiyor.
- O23/KB-5: bekleyen bebek `deleteBaby` (tombstone + push) ile kaldırılıyor, `baby:null` + çapa sıfır; O33 wipe dizinleri `wipeAllData` ile aynı kapsam (tüm cihaz) — tutarlı.

---

## 3. "İNCELEME ÖNERİLİR" 10 maddesinin değerlendirmesi

| # | Madde | Risk gerçekleşiyor mu? | Not |
|---|---|---|---|
| 1 | v15 migration + backfill | **Kısmen.** Guard'lar ve backfill koşulları doğru; v12-14'ten veri dolu test var, v2/v3/v5/v7-9/v11 yapısal test var. **Gerçekleşen risk:** transaction yok (I4). "v13/v12'den gelen cihazda addColumn atlanıyor mu" → hayır, atlanmıyor ve atlanmamalı (o tablolar v4/v7'de kuruldu); doğru. | I4 |
| 2 | Sağlık delta push + pull R1 | **EVET, kritik.** "İlk v15 turunda aşıda sunucu kazanır" kararının saha etkisi free→premium ve lapse→yeniden abone kullanıcıda **toplu aşı tiki kaybı** (I1). Dil uyuşmazlığı yankı güvencesi çalışıyor (dirty kalır, pushError yok, M9a polling'de tekrar yok); 403 → readonly kapısı doğru. TASARIM'da sözü edilen "temiz done=true → pending sayacı (Crashlytics)" kodda yok. | I1, I10 |
| 3 | K-1 geri al | **Hayır.** `discard` yolları, tombstone bebek purge sırası ve 6-tablo sayacı doğru (`push_error_repository_test.dart` kapsıyor). Küçük: bebek DELETE 404 banner gürültüsü (I7). | I7 |
| 4 | O4 ayar diff | **Hayır.** `pullSettings` bulut-uygun kapısı var ve testli; owner-only backfill kabul edilmiş karar. Yük notu (I12). | I12 |
| 5 | O26 adet yazımları / M2 | **Büyük ölçüde kapandı.** `baseJson` diff'i bayat null'ı göndermiyor; kalan açık: `importFromCloud` base yazmıyor (I9) — dar pencere. | I9 |
| 6 | O9 sayfalı /sync | **Hayır.** Parça arası cursor ilerliyor, kısmi başarı idempotent, echo'lanan server_changes dirty korumalı. Sunucu tarafı sınır (#7) hâlâ yok ama istemci 500 ile bağımsız. | — |
| 7 | O11 syncAll kuyruk | **Hayır.** İlk açılışta `onlineProvider` çözülmeden kaydeden kullanıcı beklemez, local-first; tur arka planda sürer. | — |
| 8 | O14/O15/O16 bildirim | **Kısmen.** O14/O16 doğru; **O15 eksik:** özel/randevu hatırlatıcıları iptal edilmiyor ve mutabakat onları korur (I5). Android 12-13 izinli kullanıcı etkilenmez. | I5, I6 |
| 9 | Auth artıkları + O10 | **Hayır.** `unregister` hataları yutuyor, `deleteAccount` her durumda çağrılıyor; sıra (ağ → yerel) doğru; epoch kapsamı tam. KB-9 wipe için `whileWiping` yok (I8). | I8, I16 |
| 10 | O23/O24/O32/O33 | **Hayır.** `_wipeLocalPhotoDirs` tüm cihaz — `wipeAllData` zaten tüm hesaplar, tutarlı; KB-9 ise dosya bazlı (yalnız hesap), tutarlı. Export yalnız alan ekliyor (geriye uyumlu). O23 bekleyen bebeği tombstone ile kaldırıyor; çocuk verisi (anne takibi) yerelde kalıyor — mevcut `deleteBaby` davranışıyla aynı, yeni risk değil. | — |

---

## 4. Test kalitesi gözlemleri

**Güçlü / düzeltmeyi gerçekten sabitleyen (okundu, assert'ler eski davranışta düşer):** `migration_all_versions_test` (SchemaVerifier + backfill değerleri), `migration_v15_test`, `record_sync_batching_o9_test` (3 POST + cursor), `sync_service_pending_o11_test` (takip turu gerçekten koşar), `health_repository_k4_test` (delta/echo/pull), `push_error_repository_test`, `baby_repository_test` K2 bölümü (dirty/paylaşılan/sahip ayrımı), `background_sync_test` (dispose sırası, 401 damgası, BabyController kurulmaz), `auth_controller_test` (bg bayrağı, epoch geç yanıt), `sync_merge_test`.

**Gözlemler / zayıflıklar:**
1. **Testin yanlış kontratı mühürlemesi:** `health_repository_k4_test.dart:186` "AŞIDA SUNUCU KAZANIR — temiz done=true, sunucu pending → yapılmadı" tam olarak I1'in veri kaybı yolunu *istenen davranış* olarak sabitliyor. Test doğru çalışıyor, ancak senaryo (free→premium, sunucu boş) hiç modellenmemiş. Bu bir "her durumda geçen test" değil, eksik senaryo.
2. **R5 kapsaması eksik:** bebek `pushDirty` ve adet/anne bulk için uçuş-içi düzenleme testi yok (records D3 ve ilaç planı için var). Bu incelemenin geçici testi I2'yi 1 dakikada ortaya çıkardı.
3. **"test: gerekmedi/hayır" denmiş ama saf/birim testlenebilir mantık taşıyanlar:** D18 (id üretimi — test edilseydi 500 ms periyodu görünürdü, I6), D4 (`appInForeground` yaşam döngüsü eşlemesi — saf bool), D10 (`_starting` guard — iki paralel `run()`), D26 (parse → cache sırası), O12 (RC doğruladıysa refresh hatası — controller düzeyinde mock'lanabilir), D9 (prefs yazımı fırlatınca bellek kimliği), O37 (`createdBy` korunur — tek satır assert), D36 (fetch epoch). O16/O17-NSE/D5/D6/D14/O29-DST gerçekten platform/cihaz gerektiriyor.
4. **Güncellenen mevcut testler zayıflatılmamış:** `api_client_test` 401→ağ hatası (O2 kontratı), `cycle_repository_test` satır içi PATCH→tur (O26), `async_providers_test` Future→Stream (R8), `who_lms` 61 nokta (D29), `medication_plan_sync_test` caregiver StateError (KB-8) — hepsi yeni kontrata uygun ve `verifyNever` ile eski yolu dışlıyor. 
5. **Mock sapması:** `baby_controller_test` `pullSettings/pushSettings/getAll` `any()` stub'ları yalnız kurulum; M5 testi gerçek `verifyNever` kullanıyor. O9 testindeki `_SyncAdapter` sunucu sözleşmesine (`applied/conflicts/server_changes/next_cursor`) uygun. `health_repository_k4_test` sunucu `vaccine_name/status/done_date` alanlarıyla uyumlu (backend serializer ile karşılaştırıldı).
6. `translation_keys_test` api repo yokken atlanıyor (I11); yerelde yalnız commit'lenmemiş api JSON'larıyla geçiyor.
7. Migration testlerinde **yarıda kesilmiş migration** (I4) ve **bg isolate ile eşzamanlı açılış** senaryosu yok (ikincisi birim testte zor; busy_timeout testi `db_pragmas_test` ile dolaylı).

**Kapsam dışı değişiklik taraması:** `lib/core/age.dart` (D31), `legal_links.dart` (O31), `who_lms.dart` (D29), `i18n_repository.dart` statik okuma (M7), `ios/NotificationService.swift` 3 satır (O17), `main.dart` (O18/D4/K7/O25/O3), 13 adet `features/cycle/*` dosyası (K6/O23/O24/O26/D32/D33/D34/KB-5 ve `ref.invalidate` temizlikleri) — hepsi bir bulguya bağlanıyor; ilgisiz refactor bulunmadı. `tasarim-promptlari/` izlenmeyen dizin (2 Claude Design prompt'u, ilaç/vitamin ve "dün nasıl geçti") branch'e ait değil, commit'lenmemiş; dokunulmadı.

---

## 5. Emin olunamayan, cihaz/backend gerektiren noktalar

1. **I1'in gerçek sıklığı:** `syncAll` tam turunun `MigrationService.pushAll`'dan önce koşma oranı cihazda ölçülmeli (satın alma → öne geliş → tur). Kodda engel yok; "olur mu" değil "ne kadar sık" sorusu. Yayın öncesi cihaz adımı: v14'te free iken 3 aşı işaretle → v15'e güncelle → premium satın al → aşı ekranı.
2. **Yarıda kesilen migration (I4):** gerçek cihazda üretmek zor; `adb shell am force-stop` ile migration anında kesme denenebilir (zamanlama şansa bağlı). Crashlytics'te "duplicate column name" araması (YAYIN-KONTROL 38) v15 sonrası da sürdürülmeli.
3. **Backend `HealthSyncView` yarışı:** istemci bakıcı rolünde `pushDirty` atmaz; ancak `can_full_write` sunucuda rol düşünce 403 → `pushError='role'` yolu cihazda görülmedi.
4. **O17 NSE Swift eşiği**, **O16/M4 exact alarm** (Android 14 yeni kurulum vs 12-13 mevcut), **DST** (TR dışı TZ'de `cycle_engine`/TDT) — bu makinede doğrulanamaz; YAYIN-KONTROL §1 adımları 13, 17, 32, 37 geçerli.
5. **1 dk polling'de yankılanmamış aşı (M9a):** `_unechoedVaccines` süreç ömrü; her soğuk açılışta bir kez yeniden POST — sunucu logunda beklenen gürültü, hata değil.
6. **`pullSettings` yükü (I12)** ve **R4 oran koruması**nın sahada "silme atlandı" loglarını ne sıklıkla ürettiği (`debugPrint`, Crashlytics'e gitmiyor) — gözlemlenemez; en az non-fatal kayıt önerilir.
7. **KB-9 çevrimdışı silme denemesi:** `_repo.deleteAccount()` fırlatır, wipe'a gelinmez — kodda açık; cihazda adım 36 ile doğrulanmalı.
8. iOS BGTask 25 sn bütçesinde v15 sonrası ek `GET /settings` × N + sağlık delta push'un sığıp sığmadığı (bg turu `_syncHealth` çağırmıyor, yalnız `repo.sync` — iyi; ama ön plan tam turu uzadı).

---

## 6. Önerilen yayın sırası
1. I1 (kapı + aşı backfill kararını yeniden değerlendir) → K4 testine free→premium senaryosu.
2. I2/I3 (R5 damga koşulu: bebek profili, adet/anne bulk) + regresyon testleri.
3. I4 (migration transaction) + yarıda kesilme testi.
4. I5 (özel hatırlatıcı iptali + `activeReminderIds` tombstone filtresi).
5. I7/I8/I9 ucuz düzeltmeler aynı turda.
6. Sonra YAYIN-KONTROL §1 cihaz listesi (9, 10, 12, 15, 29 + yukarıdaki §5.1) ve kademeli yayın.

---

## 7. Düzeltme turu durumu (2026-10-11)

Kural: her bulgu için önce mevcut koda karşı düşen test (stash'li/geri alınmış lib'e karşı koşularak kanıtlandı), sonra en küçük düzeltme, ayrı commit.

| ID | Durum | Commit | Önce düşen test (kanıt) |
|---|---|---|---|
| I1 | DÜZELTİLDİ — kapı + lapse reseed + telemetri; aşı backfill'i yine YOK (K-4 korunur) | `a4161f9` | `health_pull_gate_i1_test` "free→premium" (önce BCG done=false'a düşüyordu) |
| I2 | DÜZELTİLDİ — profil push R5 | `562618e` | `baby_repository_r5_i2_test` 3/4 düşüyordu |
| I3 | DÜZELTİLDİ — adet bulk / anne bulk / anı POST R5 | `1f51066` | `sync_r5_inflight_i3_test` 3/4 düşüyordu |
| I4 | DÜZELTİLDİ — onUpgrade transaction + `_addColumnIfMissing` + hook | `d5fe1fc` | `migration_interrupted_i4_test` (1): `duplicate column name: settings_dirty` |
| I5 | DÜZELTİLDİ — özel/randevu hatırlatıcı iptali + tombstone dışlama | `92c5818` | `notification_cancel_baby_i5_test`: activeReminderIds {1,2} dönüyordu |
| I6 | DÜZELTİLDİ — prefs sayaç | `1f68344` | yeni API (eski davranışın 500 ms periyodu aritmetik) |
| I7 | DÜZELTİLDİ — DELETE 404 = başarı | `d2ac131` | `baby_delete_404_i7_test`: dirty true / HTTP 404 |
| I8 + I16 | DÜZELTİLDİ — kapsam+state önce, whileWiping | `ce58ad2` | `auth_controller_test` "I8/I16": wiping=false |
| I9 | DÜZELTİLDİ — importFromCloud base yazar | `6b5518c` | m2 testi "I9": PATCH tüm alanları taşıyordu |
| I10 | DÜZELTİLDİ — katalog dışı aşı kalemi yazılmaz | `593b531` | k4 "I10": yetim satır yazılıyordu |
| I11 | DÜZELTİLDİ — CI/REQUIRE_API_TRANSLATIONS'ta FAIL | `63df484` | env tabanlı (yerelde uyarıyla atlama sürer) |
| I12 | KB-11 (yayın sonrası) | — | — |
| I13 | DÜZELTİLDİ — localOnly = sunucuya hiç gitmemiş plan (prefs'te sunucu id kümesi) | `593b531` | `medication_plan_local_only_i13_test` 3/3 düşüyordu |
| I14 | Belgelendi (TASARIM §6b) | — | — |
| I15 | Şüpheli, belgelendi (TASARIM §8) | — | — |
| GRUP D | D4/D9/D10/D26/D36/O12/O37 testleri; R4 telemetrisi | `37260e1`, `d028b43` | düzeltmeler geçici geri alınınca 10 hedef test düştü, 4 kontrol testi geçti (rapor) |

**I1 doğrulama sonuçları:** `MigrationService.pushAll` v15'te hâlâ TAM küme gönderiyor (`vaccines()/milestones()/teeth()` = katalog × durum, temiz satırlar dahil) → göç yolu değişmedi. `premiumSyncedForAccount` lapse'te temizlenmiyor (yalnız `cloud_purged_at` purge'ünde, `subscription_repository.dart:36`) → kapı tek başına yetmezdi; cloudSync true→false geçişinde `health_reseed` bayrağı eklendi, yeniden abonelikte yalnız sağlık tam kümesi gönderilir (tam yeniden yükleme/foto yok), sonra kapı açılır. Ayrıca `_run` "yüklenecek veri yok" dönüşünde artık `premiumSynced` yazılır (aksi hâlde boş/yeni cihazda sahip bebek pull'u hiç açılmazdı — kapı eklenince ortaya çıkan yan etki).

**Yan bulgular (düzeltilmedi, not):**
- `pushAll` gönderdiği satırların `dirty` bayrağını temizlemiyor → göç sonrası ilk delta push aynı değerleri bir kez daha gönderir (zararsız, idempotent). TASARIM §6 "pushAll … dirty'leri temizler" cümlesi koda uymuyor.
- Riverpod 3'te `ref.listen` ile dinlenen `cloudSyncEnabledProvider`, hiçbir widget izlemiyorsa (yalnız container) yeniden hesaplanmıyor; uygulamada widget'lar izlediği için sorun yok, testte `c.listen` gerekti (I1 lapse testi).
- `.github/workflows/*.yml` `flutter test` koşmuyor (yalnız build) → I11'in CI dalı ancak CI'da test koşulursa anlamlı.
