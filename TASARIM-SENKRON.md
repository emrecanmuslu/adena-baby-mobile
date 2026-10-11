# TASARIM — Senkron tutarlılığı (K2, K4, O4, O5, O6, O7, O20, O21)

Durum: kararlar verildi (2026-10-11), uygulama başlıyor. Kaynaklar: `lib/data/*_repository.dart`, `../API_SOZLESME.md`, backend `../api/apps/*` (yalnız "uç var mı, ne döner" için okundu). Backend'e iletilecek talepler: `BACKEND-TALEPLERI.md`.

Ortak kök: pull, push'u başarısız olmuş `dirty` satırı ve silme tombstone'unu sunucu kopyasıyla eziyor; sunucudaki silmeler yerele yayılmıyor; sağlık durumu ve aile ayarları hiç çekilmiyor, tam-küme push sunucuyu eziyor.

---

## 0. Kararlar (inceleme sonrası)

| # | Karar |
|---|---|
| K-1 | **R3:** Kalıcı (4xx) redde yerel değişiklik korunur, satıra `pushError` kaydedilir. Kullanıcıya banner + "değişikliği geri al" seçeneği **ayrı, sonraki iş** (bkz. §8 "Sonraki sürüm"). Şema kolonu v15'e kadar yok → o zamana dek log + bellek-içi/prefs kaydı. |
| K-2 | **R4:** Sunucu boş liste dönerse hiç silme yapılmaz. Silinecek satır sayısı **5'ten fazla VE temiz satırların yarısından fazlaysa** silme atlanır ve loglanır. R4 yalnız **HTTP 200 ve yanıt tamamen parse edildiyse** uygulanır. |
| K-3 | **Sağlık pull sıklığı:** açılış, öne geliş ve işaretleme sonrası. 1 dk polling'e eklenmez. |
| K-4 | **v15 backfill (kesinleşti 6. aşama):** **aşıda backfill YOK** — ilk v15 senkronunda aşı durumu için sunucu kazanır (yanlış "yapıldı" işareti kayıp işaretten tehlikeli). **Gelişim ve dişte** `done=true` satırlar `dirty=true`. |
| K-5 | **Aile ayarları:** son yazan kazanır yeterli; ancak PATCH yalnız **değişen alanları** gönderir. |
| K-6 | `memoriesProvider` drift **Stream**'e geçer (`list()` içindeki ağ beklemesi kalkar, pull arka planda). |
| K-7 | **Caregiver reddi:** repo `StateError` fırlatır, UI toast gösterir. |
| K-8 | **cycle `baby=null`:** backend kontrol edildi — `CycleSettings.baby` `null=True, blank=True` (`apps/cycle/models.py:27-30`), `ModelSerializer` alanı `allow_null=True` üretir → `PATCH {"baby": null}` **kabul edilir**. Backend talebi yok; istemci `toPatchJson`'ın null'ı atması **6. commit'te** düzeltilir. |
| K-9 | **O8 (`bulk` id eşlemesi):** backend talebi (`BACKEND-TALEPLERI.md` #4). İstemcide yalnız çift dokunma koruması. |
| K-10 | **Sürümleme (güncellendi 6. aşama):** kullanıcı kuralı "tüm bulgular bitmeden yayın yok". Şema v15 (commit 7a/7b/8/9) **aynı branch'te** (`fix/audit-bulgular`) yazılır; v15'in ayrı bir sürüm olup olmayacağına **yayın öncesi kullanıcı karar verir**. Kod tarafında tek değişmez: `schemaVersion` 14→15 tek sıçramada (ara sürüm yok). |

---

## 1. Mevcut durum

Referans model: **Records** (`record_repository.dart:210-334`). Delta `POST /sync` (tek round-trip push+pull), `client_updated_at` ile LWW, sunucu tombstone (`is_deleted`) döndürür, `applied` yalnız gönderilen damga hâlâ duruyorsa dirty'yi temizler, `_applyServerRow` dirty+daha-yeni yerel satırı ezmez, cursor ISO string. Bu modelde tek açık nokta tek-POST'ta sınırsız batch (O9, bu tasarımın dışında).

İkinci referans: **İlaç planları** (`health_repository.dart:322-444` + backend `MedicationPlanSyncView`): uuid, `client_updated_at`, tombstone, yanıt otoriter, uçuş-içi düzenleme koruması. Küçük küme için cursor'suz "tam yanıt" deseni.

| Veri tipi | Yerel tablo (dirty / tombstone) | Push | Pull | Sunucu silmesi nasıl öğreniliyor | Sorun |
|---|---|---|---|---|---|
| Records | `records` (dirty ✔ / isDeleted ✔) | `POST /sync` delta, LWW | aynı istek, `server_changes` + `conflicts` | tombstone (`is_deleted`) | — (referans) |
| İlaç planı | `medication_plans` (dirty ✔ / isDeleted ✔, uuid) | `/medication-plans/sync` | aynı istek, tüm küme | tombstone | — (referans) |
| Bebek | `babies` (dirty ✔ / isDeleted ✔) | `POST /babies` (owner) / `PATCH` (parent), satır başına, hata yutulur | `GET /babies` → `insertOnConflictUpdate(dirty:false, photo:srv)` | paylaşılan bebek listede yoksa ve clean ise yerelden silinir; sahip bebek asla | **K2**: pull dirty satırı ve yüklenmemiş fotoyu ezer |
| Aile ayarları | `babies.settings` JSON; bebek `dirty`'sine binmiş, ayrı bayrak yok | bebek push'unda `PATCH /babies/{id}/settings` (tüm sözlük) | **yok** (`GET /babies/{id}/settings` hiç çağrılmıyor) | — | **O4**: yeni cihaz/üye ayarı görmez; son yazan ezer |
| Sağlık durumu | `health_statuses` (dirty ✖ / tombstone ✖) | `POST /health/sync` TAM küme (katalog × done) | yalnız `importFromCloud` (ilk giriş/göç) — `GET /vaccines, /milestones, /teeth`, yalnız done=true ekler | yok (işaret kaldırma yayılmaz) | **K4, O21** |
| Anı | `memories` (dirty ✔ / isDeleted ✔, serverUpdatedAt yazılmıyor) | `POST` multipart satır başına; silme `DELETE` sonra yerel hard-delete | `GET /babies/{id}/memories` (tam liste, `is_deleted=false`) → upsert `dirty:false`, `isDeleted` companion'da yok | **yok** (sunucu soft-delete ama GET tombstone döndürmez) | **O5** |
| Anne takibi | `mom_entries` (dirty ✔ / isDeleted ✔) | `/mom-entries/bulk` (≤1000, `saved` id'leri), silme `DELETE` | `GET /mom-entries` (tam liste) → upsert `dirty:false` | **yok** (sunucu HARD delete, `updated_at` yok) | **O5** |
| Adet ayarı | `cycle_settings_table` (dirty ✔) | `PATCH /cycle/settings` yalnız patch anında; dirty'yi yeniden deneyen yol yok (göç hariç) | `GET /cycle/settings` her `getSettings`'te → `dirty:false` ile ezer | — | **O6** |
| Adet kayıtları | `cycle_entries` (dirty ✔ / isDeleted ✔) | `/cycle/entries/bulk` (`saved`), silme `DELETE` | `GET /cycle/entries` (tam liste, `updated_at` var) → upsert `dirty:false` | **yok** (sunucu HARD delete) | **O7**, O8 (id uyuşmazlığı) |

Not: `Baby` yanıtı `updated_at` taşıyor; anı ve adet kaydı yanıtları `updated_at` taşıyor; anne kaydı ve sağlık uçları taşımıyor.

---

## 2. Ortak kural seti

| # | Kural | Kapattığı bulgu |
|---|---|---|
| R1 | **Pull dirty satırı asla ezmez.** Yerel `dirty=true` ise sunucu kopyası uygulanmaz (records `_applyServerRow` ile aynı). Sunucu damgası varsa ve yerel `clientUpdatedAt`'ten yeniyse → "çakışma": yerel kalır, bir sonraki push LWW'ye bırakır. | K2, O5(b), O6, O7 |
| R2 | **Pull `isDeleted=true` satırı asla geri almaz.** Tombstone'lu yerel satır sunucuda hâlâ görünüyorsa dokunulmaz; DELETE/op:delete bir daha denenir. | O5(b), O7 |
| R3 | **Push başarısızlığı dirty'yi temizlemez; geçici/kalıcı ayrımı yapılır.** Ağ/5xx/401/403/429 → geçici: dirty kalır, sessizce yeniden denenir. Diğer 4xx (400/404/413/422) → *kalıcı red*: yerel değişiklik **korunur**, satıra `pushError` kaydedilir (K-1; kolon v15'e kadar yok → log + prefs). Banner + geri alma sonraki iş. | K2, O5, O21 |
| R4 | **Sunucuda olmayan, yerelde `dirty=false` ve `isDeleted=false` olan satır kaldırılır** — yalnız pull'un TAM liste döndürdüğü tiplerde (anı, anne, adet kaydı, paylaşılan bebek). Korumalar (K-2): yalnız HTTP 200 + tam parse; sunucu listesi boşsa hiç silme; silinecek > 5 VE temiz satırların > %50'si ise silme atlanır ve loglanır. **Bebek listesi istisnası (onaylandı, K2 commit'i):** `GET /babies` için boş-liste ve oran korumaları UYGULANMAZ — boş liste meşru bir durumdur (üyenin tek bebeği paylaşılan bir bebekse ve erişimi kaldırıldıysa) ve mevcut kural zaten yalnız paylaşılan+temiz satırı siler; paylaşılan bebeğin verisi sunucuda sahibinde durduğu için yerel silme geri kazanılabilir. | O5(a), O7 |
| R5 | **`dirty=false` yalnız sunucu onayıyla yazılır** (push yanıtı `saved/applied` ya da pull'dan gelen satır). Uçuş-içi düzenleme koruması: gönderilen damga ≠ mevcut damga ise dirty kalır (records/ilaç planı deseni). | K2, O5, O7 |
| R6 | **Ayrı veri ayrı bayrak.** Aile ayarları bebek profilinden bağımsız `settingsDirty` taşır; sağlık işaretleri satır başına `dirty`. Bir tipin push hatası diğerini kilitlemez. | O4, K4 |
| R7 | **Tam-küme push yasak.** Yalnız dirty satırlar gönderilir; sunucuya "listede olmayan = sil" anlamı yüklenmez. Aile ayarlarında PATCH yalnız değişen alanlar (K-5). | K4, O4 |
| R8 | **Pull, UI'ı değil local-first okumayı besler:** ekran yerel DB'den (Stream) döner, pull arka planda. `list()`/`getSettings()` içinde `await` ile ağ beklenmez (K-6). | O21, O26, O5 |
| R9 | **Rol kapısı tek yerde:** caregiver'ın yazamayacağı veri UI'da kilitlenir; repo `StateError` fırlatır, UI toast gösterir (K-7). | O20 |

---

## 3. Ortak yardımcı: `lib/data/sync_merge.dart` (saf) + repo başına uygulama

- Saf fonksiyonlar (drift'ten bağımsız, birim testli):
  - `decideServerRow(localExists, localDirty, localDeleted, localStamp?, serverStamp?) → MergeDecision { apply, keepLocalDirty, keepLocalDeleted }` (R1, R2).
  - `staleLocalIds(local: [(id, dirty, deleted)], serverIds, {statusCode, parsedOk}) → (ids, skippedReason?)` (R4 + K-2 korumaları).
  - `classifyPushFailure(statusCode?, isNetwork) → PushFailure { transient, permanent }` (R3).
- Artıları: kural tek yerde, test tek yerde; repo kodu kısa. Eksileri: yardımcıyı atlayan repo eski davranışa döner → her repo için "pull dirty'yi ezmez" regresyon testi şart (§8).
- Generic drift mixin reddedildi (companion kolon kümeleri tablo başına farklı; tip güvenliği kaybı).

---

## 4. Backend bağımlılıkları

| Veri | Gereken uç | Mevcut mu | Yalnız istemciyle çözülen | Backend talebi (`BACKEND-TALEPLERI.md`) |
|---|---|---|---|---|
| Bebek | `GET /babies` (`updated_at` ✔) | ✔ | K2'nin tamamı (R1/R3/R5). Foto: yerel yol dirty kaldığı sürece sunucu URL'i yazılmaz. | — |
| Aile ayarları | `GET /babies/{id}/settings` | ✔ (`FamilySettingsView.get`) | O4'ün tamamı: pull + `settingsDirty` + değişen-alan PATCH (K-5). | — |
| Sağlık durumu | GET'ler ✔ ama kalem damgası ✖; `POST /health/sync` ✔ (sözleşmede belgelenmemiş), yalnız gönderilen kalemleri günceller (`filter().update()`) | kısmen | K4'ün ana kısmı: yalnız dirty kalemler gönderilir → ezme biter. Pull: temiz yerel satır sunucuyu alır, dirty korunur. Pull tetikleri K-3. | #1 kalem damgası (gerçek LWW), #2 `/health/sync` sözleşme + yanıtta güncel küme, #3 aşı dil-bağımsız `key` (O19) |
| Anı | `GET` ✔ (`updated_at` ✔, tombstone ✖, tam liste) | ✔ | O5'in tamamı (R1/R2/R4/R5); silme yayılımı "listede yok + yerel temiz → sil". | #5 tombstone / `include_deleted` (R4 riskini sıfırlar) |
| Anne takibi | `GET` ✔ (tam liste, `updated_at` ✖, HARD delete) | ✔ | O5'in tamamı; damga yok → "dirty yerel kazanır, temiz yerel sunucuyu alır". | #6 `updated_at` |
| Adet ayarı | `GET/PATCH /cycle/settings` ✔ (`updated_at` ✔, `baby` null kabul — K-8) | ✔ | O6'nın tamamı + `baby=null` gönderimi. | — |
| Adet kayıtları | `GET` ✔ (`updated_at` ✔, HARD delete), `bulk` ✔ (`saved`) | ✔ | O7: R1/R2/R4/R5. O8: yalnız çift dokunma koruması (K-9). | #4 `bulk` yanıtında `client_id → server_id` |

---

## 5. Şema değişiklikleri (drift v14 → v15) — 6. aşama

Durum (2.–5. aşamadan sonra): `pushError` **kolon yok**; K2/O5/O7 repo'ları kalıcı reddi **bellek-içi** `Map<String,String> pushErrors` + `debugPrint` ile tutuyor (`baby_repository.dart:431`, `memory_repository.dart:43`, `mom_repository.dart:36`, `cycle_repository.dart:402`) — prefs'e YAZILMIYOR (§8 tablosundaki "prefs" notu eskidi). Caregiver temizliği şemasız yapıldı (§7). Sağlık tablosunda dirty/damga yok (`health_statuses: baby, kind, itemKey, done, statusDate`).

### 5A. Migration v14 → v15

| Tablo | Yeni kolon | Varsayılan | Not |
|---|---|---|---|
| `health_statuses` | `dirty` BOOL | false | satır başına delta push (R6/R7) |
| | `clientUpdatedAt` DATETIME? | NULL | uçuş-içi düzenleme koruması (R5); backend #1 gelince LWW damgası |
| | `serverUpdatedAt` DATETIME? | NULL | v15'te yazılmaz; backend #1 gelince pull doldurur (yeni migration gerekmez) |
| | `pushError` TEXT? | NULL | K-1 |
| `babies` | `settingsDirty` BOOL | false | aile ayarı bebek profilinden ayrı bayrak (R6) |
| | `settingsBase` TEXT? | NULL | sunucunun son onayladığı ayar JSON'u — değişen-alan diff'i için (K-5, bkz. 5C) |
| | `pushError` TEXT? | NULL | profil push'u kalıcı reddi |
| `memories`, `mom_entries`, `cycle_entries`, `cycle_settings_table` | `pushError` TEXT? | NULL | K-1 |

**Migration kodu (`onUpgrade`):** mevcut desenle (`if (from < 15)`), fakat **tablo o upgrade içinde yeni kurulduysa `addColumn` çalışmamalı** (ilaç planı deseni `from >= 13 && from < 14` gibi): `babies/memories/mom_entries/cycle_*` için `from >= 4 && from < 15`, `health_statuses` için `from >= 7 && from < 15`. `from < 4`/`from < 7` yolunda `createTable` zaten v15 şemasını kurar.

**Backfill (`UPDATE`, migration içinde, aynı transaction):**
- `babies.settingsDirty = (settings != '{}' AND (myRole IS NULL OR myRole = 'owner'))` — **KARAR (6. aşama):** yalnız sahip satırlarında, yerel JSON doluysa. Üye (parent) / caregiver satırlarında backfill yok; ilk pull sunucuyu uygular. `settingsBase` NULL kalır → ilk diff "tüm alanlar değişmiş" sayar → bir kez tam sözlük PATCH. Seçenek tartışması 5C'de.
- `health_statuses.dirty = (done = 1 AND kind IN ('milestone','tooth'))` — **KARAR (K-4 kesinleşti):** aşıda backfill yok (ilk v15 turunda sunucu kazanır = normal R1), gelişim/dişte done=true → dirty. Bkz. 5B.
- `pushError`: taşınacak veri YOK (bellek-içi haritalar süreç ömrü; prefs'te hiçbir kayıt yok). v15 sonrası haritalar kalkar, kolon yazılır; bekleyen dirty satır bir sonraki turda yeniden denenip kolonu doldurur.

**Eşzamanlılık riski:** DB'yi bg isolate (workmanager/BGTask/FCM) de açar; ilk açan migrasyonu çalıştırır, diğeri `busy_timeout` ile bekler (WAL + PRAGMA sırası 2026-09-01 fix'i). Migration `addColumn` + 1-2 `UPDATE` → ms mertebesi; ek önlem gerekmez. `schemaVersion` tek sıçrama (14→15).

**Migration test stratejisi (`drift_schemas/` YOK → kurulacak):**
1. 7a commit'inin ilk adımı, şema değişmeden: `dart run drift_dev schema dump lib/data/local/app_database.dart drift_schemas/drift_schema_v14.json` (drift_dev 2.33 `schema dump/generate/steps` destekliyor; doğrulandı). Alternatif: v14 dosyasını `git show 90df7b7:lib/data/local/app_database.dart` ile geçici dizine çıkarıp dump.
2. v15 yazıldıktan sonra `drift_schema_v15.json` dump; `dart run drift_dev schema generate drift_schemas/ test/drift/generated/` (commit'lenir).
3. `test/data/migration_v15_test.dart`: `SchemaVerifier(GeneratedHelper())` → `startAt(14)` → `migrateAndValidate(AppDatabase(conn), 15)` (yapısal doğrulama) **+ veri dolu geçiş:** `schemaAt(14)`'e ham SQL ile satırlar basılır (done=true/false sağlık satırları; `dirty=1 settings='{...}'` sahip bebek, `dirty=1 settings='{}'` bebek, caregiver bebek, `dirty=0` bebek; anı/anne/adet satırları) → migrate → v15 DAO ile okunup backfill kuralları ve eski kolonların korunduğu doğrulanır. `make-migrations` (build.yaml konfigürasyonu ister) KULLANILMAZ; elle `onUpgrade` deseni korunur.
4. Regresyon: `test/data/db_pragmas_test.dart` + tüm suite yeşil; `onCreate` yolu (taze kurulum) için `schemaVersion == 15` ve `createAll` testi.

### 5B. K-4 backfill riski — seçenekler (KARAR VERİLDİ: (ii))

**Bugünkü gerçek:** sağlık pull'u yalnız ilk giriş/göçte; her işaretleme `pushAll` ile cihazın **tam** kataloğunu gönderir → sunucu = **en son işaretleme yapan cihazın tam kümesi** (o cihazın her kalemi, done ve undone). Diğer cihazlar bunu hiç öğrenmedi → cihazlar ayrışmış. Tek cihazlı premium kullanıcıda (çoğunluk) sunucu == cihaz; yalnız çevrimdışı yapılmış ve sonra başka işaretlemeyle taşınmamış işaretler sunucuda yok.

| Seçenek | Kaybolabilecek veri | Geri gelebilecek eski veri | Kullanıcıya görünür etki |
|---|---|---|---|
| (i) K-4 aynen: tüm `done=true` → dirty | Yok (done işaretleri birleşir: her cihazın done'ları push edilir, dirty satırı pull ezmez) | **Kaldırılmış işaret geri gelir:** A "yanlışlıkla yapıldı demişim" diye kaldırdı, B'de hâlâ done → B'nin backfill push'u sunucuyu done yapar → A'nın satırı temiz-false → pull done yazar. Aşıda **yanlış "yapıldı"** = en tehlikeli hata (çocuk aşısız sanılmaz). | Kaldırılan aşı/diş/gelişim işareti sessizce geri gelir; kullanıcı fark etmeyebilir. |
| (ii) Aşı: backfill yok + ilk v15 turunda sunucu kazanır; gelişim/diş: K-4 aynen | **Aşı:** sunucuda olmayan done işaretleri (çevrimdışı/yarışı kaybetmiş cihaz) yerelde "yapılmadı"ya döner → kullanıcı yeniden işaretler (güvenli hata yönü). Gelişim/diş: yok. | Aşı: yok (sunucu en son insan-onaylı tam küme). Gelişim/diş: (i) gibi geri gelme — orada yanlış "başarıldı/çıktı" düşük riskli. | Aşıda bazı tikler kaybolabilir (ekranda "yapılmadı"/gecikti görünür → kullanıcı görür, düzeltir). Tek cihazlı kullanıcıda etki yok. |
| (iii) Hiç backfill yok | Sunucuda olmayan tüm done işaretleri (üç türde) yerelde kalkar. | Yok. | En çok "tik kayboldu" şikâyeti; aşı için (ii) ile aynı, gelişim/diş için gereksiz kayıp. |

**Push/pull sırası ilk v15 turunda:** dirty satır varken sıra fark etmez (pull dirty'yi ezmez → push gönderir → sonraki pull aynı değeri döndürür). Backfill olmayan türde push edecek bir şey yok; pull "sunucu kazanır" uygular — bu, v15 sonrası her turun normal R1 davranışıdır, özel bir "ilk tur" kodu gerekmez. Tek özel durum: free→premium göçü (`MigrationService`) **tam küme `pushAll`** olarak kalır (sunucuda hiçbir şey yok, tam yükleme doğru).

**Karar: (ii) (kullanıcı, 6. aşama).** (i) ve (iii) değerlendirildi, seçilmedi: (i) kaldırılmış aşı işaretini geri getirir; (iii) gelişim/dişte gereksiz tik kaybı. Gerekçe: aşıda yanlış "yapıldı" > kayıp tik; sunucu kümesi "en son işaretleme yapan cihaz"ın kümesi olduğundan en güncel insan-onaylı durumdur; kaybolan tik ekranda görünür ve geri alınabilir. Gelişim/diş için (i) birleşim davranışı kabul edilebilir. Ek güvence (ii) için: ilk pull'da "temiz done=true → sunucu pending" sayısı `debugPrint` + Crashlytics non-fatal ile sayılır (saha ölçümü).

### 5C. O4 `settingsDirty` backfill'i ve K-5 değişen-alan PATCH'i

| Seçenek | Risk | Not |
|---|---|---|
| Yalnız sahip rolünde backfill (yerel JSON doluysa dirty) | Sahibin **bayat** cihazı (uzun süredir açılmamış) parent'ın güncel ayarını ezer | Rol tek başına güncelliği söylemez |
| Önce `GET /settings`, sonra yalnız farklı alanlar dirty | Hangi tarafın güncel olduğunu yine bilmiyoruz (damga yok); "farklı = yerel kazanır" demek sunucuyu her zaman ezmektir | Kayıp azalır ama ezme riski kalır |
| Backfill yok (sunucu kazanır) | v14'te **gönderilememiş** (çevrimdışı) ayar değişikliği kaybolur | Düşük riskli ama gerçek kayıp |
| v14 dirty bayrağını taşı: `settingsDirty = (babies.dirty AND settings != '{}' AND rol != caregiver)` | Düşük (dirty+dolu = henüz gidememiş küme) | Değerlendirildi, **seçilmedi**: kullanıcı kararı sahip-rolü kuralı (aşağıda) |
| **KARAR (6. aşama): yalnız sahip rolünde (`myRole` NULL/owner), yerel JSON ≠ `{}`** | Sahibin bayat cihazı üyenin daha yeni ayarını bir kez ezebilir — düşük önemli alanlar (birim/sessiz saat), görünür ve düzeltilebilir; parent/caregiver satırlarında backfill yok → ilk pull sunucuyu uygular | Uygulanan kural; `settingsBase` NULL → ilk PATCH tam sözlük |

**K-5 "neyin değiştiği" nasıl tutulur (seçilen yöntem — en basit güvenilir yol):** `babies.settingsBase` (sunucunun son onayladığı JSON; GET/PATCH yanıtıyla yazılır). Değişen alan = üst-düzey anahtar (`units`, `quiet_hours`, `enabled_types`, `defaults`, `reminder_schedule`, `feed_reminder`) bazında `local[k] != base[k]`. Üst-düzey anahtar doğru birimdir: backend `partial=True` serializer alanı bütünüyle değiştirir (iç içe birleştirme yok); `updateFamilySettings` zaten anahtar bazında yazıyor. Ayrı kolon/ayrı JSON reddedildi (6 alan için 6 bool kolon ya da "changedKeys" listesi → base ile diff daha az durum taşır ve pull'da "değişmemiş alanı sunucudan al" kararını da verir).
- **Push:** `settingsDirty` → PATCH yalnız değişen anahtarlar; 2xx → `settings = yanıt`, `settingsBase = yanıt`, `settingsDirty=false` (R5: PATCH sırasında yerel yeniden değiştiyse — `clientUpdatedAt` karşılaştırması — dirty kalır). Kalıcı 4xx → `pushError`. `pushDirty` artık ayarı bebek profilinin push'una **bağlamaz** (R6).
- **Pull (`pullFromServer` içinde, bulut-uygun bebek için `GET /babies/{id}/settings`):** `settingsDirty=false` → `settings = base = sunucu`. `settingsDirty=true` → yalnız **değişmemiş** anahtarlar (`local[k] == base[k]`) sunucudan güncellenir, değişmişler korunur; base'in değişmemiş anahtarları güncellenir. Yanıt 200 + Map değilse dokunulmaz.
- **Caregiver satırları:** `_requireFullWrite` dirty üretmesini engeller; migration backfill'i caregiver'ı dışlar; pull her zaman sunucu kazanır; push rol filtresi (owner/parent) korunur. Rol düşmesi (parent→caregiver) sonrası kalan dirty ayar → PATCH 403 → §6b "rol" kuralı.
- `familySettingsProvider` (Future) pull sonrası `invalidate` edilir (Stream'e geçiş isteğe bağlı, kapsam dışı).

---

## 6. Sağlık durumu (K4 / O21) — 6. aşama tasarımı

- **Yazım (`_setStatus`):** satır `done/statusDate` + `dirty=true` + `clientUpdatedAt=now` ile yazılır; ağ **beklenmez**: `onStatusChanged?.call(babyId)` → `syncService.requestSyncSoon()` (ilaç planı deseni, 1,2 sn debounce). Ekran yerel yazımdan hemen sonra tazelenir (O21). Free/bulutsuz bebekte dirty yine yazılır (göçte `pushAll` tam küme gönderir ve dirty'leri temizler).
- **Delta push (`pushDirty(babyId)`):** yalnız `dirty=true` satırlar → `POST /babies/{id}/health/sync` (`vaccines[{name,done,done_date}]`, `milestones[{key,…}]`, `teeth[{key,…}]`; `reminders` anahtarı gönderilmez). Backend yalnız gönderilen kalemleri `update` eder (`HealthSyncView`, `filter().update()`), listede olmayana dokunmaz → tam-küme ezmesi biter (R7). 2xx → gönderilen satırlar için `clientUpdatedAt` değişmediyse `dirty=false, pushError=null` (R5). Kalıcı 4xx → `pushError` (R3); 403 geçici (`cloudReadonly` kapısı syncAll'da). `pushAll` yalnız göç için kalır.
- **Pull (`pull(babyId)`; eski `importFromCloud` yerine, R1 tam uygulanır):** `GET /vaccines|/milestones|/teeth` (200 + List parse şart; boş liste → o tür atlanır, K-2 ruhu). Her sunucu kalemi için: yerel satır **dirty ise dokunma**; temiz/yok ise `done/date` sunucudan yazılır — **işaret kaldırma da yayılır** (`done=false`). Sunucuda olmayan yerel satır silinmez (katalog × durum, kullanıcı varlığı değil; R4 uygulanmaz). Bitince ilgili `vaccinesProvider/milestonesProvider/teethProvider(babyId)` invalidate.
- **Tetikler (K-3):** `syncAll` tam turlarında (`sharedOnly=false`: açılış, öne geliş, `requestSyncSoon`) bebek döngüsünde `repo.sync` + `_syncMedicationPlans`'tan sonra `_syncHealth(b.id)` = `pushDirty` → `pull` (aynı try: 403 → readonly). 1 dk polling (`sharedOnly=true`) turlarında **yalnız dirty satır varsa push** (ucuz), pull yok (K-3). `InitialImport`/`MigrationService` pull adımı `pull`'u çağırır (artık işaret kaldırmayı da uygular).
- **İki cihaz aynı kalemi ters yöne çekerse (backend #1 yokken):** ikisi de dirty → ikisi de push → sunucuda **son push kazanır**; önce push eden cihazın satırı temizlendiği için bir sonraki pull'da diğerinin değerini alır → iki cihaz da son yazana yakınsar (kalem bazında). #1 gelince: push `client_updated_at` taşır, sunucu yalnız daha yeniyse uygular, pull `updated_at`'i `serverUpdatedAt`'e yazar ve `decideServerRow` damga karşılaştırmasına geçer (kolon v15'te hazır).
- **Aşı anahtarı dil bağımlılığı (O19) → delta push'a etkisi:** `itemKey` = katalog `key` (asset'te key == yerelleştirilmiş ad). Push `name` ile eşler; cihaz dili ≠ sunucunun takvimi ürettiği dil ise `filter(vaccine_name=…)` 0 satır → **2xx ama sessiz no-op**. Tehlike: naif tasarımda `dirty=false` yapılır, sonraki pull sunucunun (pending) değerini temiz satıra yazar → **kullanıcının tiki kaybolur** (bugünkü v14'ten kötü). **Güvence (yalnız aşı, backend #3 gelene dek):** push sonrası pull'da sunucu listesinde aynı `name` ve aynı `done` değeri **yankılanmadıysa** satır **dirty kalır**, `pushError` YAZILMAZ (kullanıcı hatası değil), bir kez `debugPrint`. Dirty kaldığı için R1 pull'dan korur → tik hiç kaybolmaz; eşleşmeyen dildeki aşı işaretleri #3'e kadar yerelde yaşar, sunucuya gitmez (v14'teki fiili durum). Gelişim/diş `key` dil-bağımsız → yankı kontrolü gerekmez.
- **Sunucu uçları/sözleşme:** `POST /health/sync` yanıtı `{"ok": true}` (#2 gelince yankı kontrolü ve post-push GET'ler yanıttan okunur).

### 6b. `pushError` + banner + "değişikliği geri al" (K-1) — 6. aşama

- **Tablolar:** `babies` (profil), `memories`, `mom_entries`, `cycle_entries`, `cycle_settings_table`, `health_statuses`. **Dışında:** `records` (tek `POST /sync` batch; kalıcı red = O9 batch sınırı işi), `medication_plans` (yanıt otoriter; kalem reddi dönmüyor). `pushError` değeri kısa kod: `'HTTP 400'`, `'HTTP 422'`, `'role'`.
- **Yazılma:** R3 kalıcı (4xx, 401/403/408/429 hariç). **Ek kural (caregiver/403):** push 403 aldıysa **ve** bebek satırının `myRole == 'caregiver'` ise (rol düşmüş, dirty satır sonsuza dek 403 alır) → `pushError='role'` (banner'a düşer, geri al sunucu kopyasını yükler). Bebek-düzeyi geçici 403 (sahip premium bitti) geçici kalır (self-heal). Bellek-içi `pushErrors` haritaları kaldırılır (testler kolona bakar).
- **Temizlenme:** başarılı push (`dirty=false` ile birlikte), "geri al", satırın **hard delete**'i. Tombstone (`isDeleted=true`) push'u kalıcı reddedildiyse `pushError` yazılır ve satır listede "silme gönderilemedi" olarak görünür.
- **Sayaç:** `pushErrorCountProvider` (StreamProvider) — tek custom SELECT: 6 tablonun `push_error IS NOT NULL` sayıları toplamı, aktif hesabın bebekleri/hesap kapsamıyla; `readsFrom` 6 tablo. `syncStatusProvider`'a eklenmez (o tur-durumu; bu kalıcı satır durumu).
- **Banner:** mevcut `SyncStatusBanner` (`backup_nag.dart`; `home_screen` + `expecting_home`) üçüncü duruma genişler: sayaç > 0 → "{n} değişiklik sunucuya gönderilemedi" (uyarı rengi, "Senkron sorunu"ndan ayrı), dokununca `PushErrorSheet`: satır başına tür etiketi + başlık/tarih + kod, "Geri al" ve altta "Tümünü geri al". Giriş/onboarding'de görünmez (bebek yokken banner zaten yok).
- **"Geri al" tablo başına** (hepsi: önce sunucu kopyasını GET, 200 → uygula `dirty=false, pushError=null`; **404/403 (sunucuda yok/erişim yok)** → satır yerel-oluşturulmuş ya da sunucuda silinmiş):
  - `babies`: `GET /babies/{id}` 200 → `pullFromServer` upsert kuralıyla profil (ayar değil) uygulanır; 404 → sahip bebek yerelde **kalır**, `dirty=false, pushError=null` ("yerelde kalır" etiketi; sahip bebeği pull asla silmez); tombstone + 404 → hard delete.
  - `memories`: tekil GET yok → `GET /babies/{id}/memories` listesinden id ile; var → uygula (silme tombstone'u ise geri alma = sunucu kopyasını canlandır: `isDeleted=false`); yok → hard delete (kullanıcı değişikliği bilinçli attı).
  - `mom_entries`: aynı (liste GET); yok → hard delete.
  - `cycle_entries`: `GET /cycle/entries/{uuid}`; yok → hard delete.
  - `cycle_settings_table`: `GET /cycle/settings` → uygula (O6 `getSettings` dirty kapısı atlanarak).
  - `health_statuses`: o bebeğin ilgili türü `pull` ile; sunucuda kalem yoksa `dirty=false, pushError=null`, `done` korunur.
  - Ağ hatası → işlem yapılmaz, toast "sunucuya ulaşılamadı".
- **Çeviri anahtarları (6 dil):** "{n} değişiklik sunucuya gönderilemedi", "Gönderilemeyen değişiklikler", "Değişikliği geri al", "Tümünü geri al", "Sunucudaki hâli yüklendi", "Yerel değişiklik silindi", "Silme gönderilemedi", "Bu kayıt yalnız bu cihazda kalacak". Tür etiketleri mevcut anahtarlardan (Bebek, Anı, Anne takibi, Adet, Aşı/Gelişim/Diş).

---

## 7. O20 — caregiver düzenlemesi

**UI kilidi + repo reddi + K2 birlikte.** Yalnız K2 uygulanırsa caregiver'ın yerel düzenlemesi sonsuza dek dirty kalır (`pushDirty` rol filtresi göndermez, pull artık ezmez) → kalıcı ayrışma. Karar K-7: `BabyRepository.update/updatePhoto/updateFamilySettings` caregiver satırında `StateError` fırlatır; `baby_edit_screen` bakıcıda salt-okunur (not + pasif form, Kaydet/"doğdu"/sil yok), `expecting_home` "Bebeğim doğdu" düğmesi toast verir; aile ayarı yardımcıları (`updateUnits/updateQuietHours`) `StateError`'ı yakalayıp üst banner gösterir.

**Mevcut cihaz temizliği (ŞEMASIZ, commit 3'te uygulandı):** `pullFromServer` caregiver satırında dirty bayrağını yok sayıp sunucu kopyasını uygular (`dirty=false`). Bu **bebek-repo'ya özel istisna**dır, `sync_merge` kuralı değil: rol kavramı yalnız bebek tablosunda var; saf yardımcı tablo/rol bilmez ve diğer tiplerde "dirty'yi yok say" diye bir durum yok. v15 migrasyon maddesi bu nedenle kaldırıldı.

---

## 8. Uygulama planı

### Bu sürüm (commit 1-6) — hash'ler tabloda; K1 `00cd3fb`, K3 `37f05f8`, K5 `e5f1a66`, docs `a5cdc94` (1. aşama)

| # | Commit | Kapsam | Risk | Testler |
|---|---|---|---|---|
| 1 (`eb7102f`) | `sync_merge.dart` saf yardımcı | §3 fonksiyonları; davranış değişikliği yok | yok | dirty/deleted/damga matrisi; R4: boş liste, >5 ∧ >%50 oranı, 200 dışı/parse hatası; R3 sınıflandırma |
| 2 (`7823480`, 3b `20ed1f5`) | fix(K2) bebek pull | `pullFromServer` R1/R2/R5; `pushDirty` R3 (kalıcı red → log + prefs `pushError`, kolon v15'te) | düşük | dirty bebek korunur; yüklenmemiş foto korunur; temiz bebek güncellenir; paylaşılan bebek listeden düşünce silinir |
| 3 (`ce7e04c`) | fix(O20) caregiver kilidi | UI kilidi + repo `StateError` + toast (migrasyon temizliği v15'te) | düşük | caregiver'da Kaydet yok; repo caregiver update → `StateError`, dirty üretmez |
| 4 (`c6a55dc`) | fix(O5) anı + anne | `_pull` R1/R2/R4 (+`serverUpdatedAt`), `memoriesProvider` Stream (K-6), `list()` ağ beklemez | orta | dirty korunur; tombstone geri gelmez; sunucuda olmayan temiz satır silinir; boş liste → silme yok; oran koruması |
| 5 (`4352738`, 5b `3426724`) | fix(O7) adet kayıtları | `_pullEntries` R1/R2/R4; çift dokunma `_saving` koruması (K-9) | orta | aynı desen + çift dokunma |
| 6 (`89cc58f`) | fix(O6) adet ayarı | `getSettings` dirty ise GET uygulanmaz; dirty ayar `syncAll`'da yeniden denenir; `toPatchJson` `baby: null` gönderir (K-8); R8 | düşük | çevrimdışı patch → online GET ezmez → PATCH gönderilir; null baby patch'e girer |

**Yayın öncesi kontrol listesi (bu sürüm):** `../api/apps/translations/data/*.json`'a eklenen yeni UI metinleri api repo'sunda commit'lenip prod'da `seed_translations --locale <en|es|fr|ar|hi|zh>` ile tohumlanmalı (commit 3'te 1 anahtar: "Bakıcı rolünde bebek bilgileri salt-okunurdur; …"); aksi hâlde yeni metin TR dışı dillerde Türkçe görünür.

Commit 3b (K2 ek): paylaşılan temiz bebek listeden düşünce silinmeden önce `GET /babies/{id}` ile doğrulanır (403/404 → sil + child purge; 200/ağ/5xx → dokunma). Gerekçe: child purge (`records/memories/mom/health`) dirty satırları da sildiğinden 200 ile gelen eksik liste üyenin gönderilmemiş verisini kaybettirirdi.

### Bu sürüm — 3. aşama (adet/misafir)

| # | Commit | Kapsam |
|---|---|---|
| K6 (`249aad1`) | çapa politikası + D33 + invalidate temizliği | bkz. commit mesajı |
| K7 (`eb25b3c`) | bebeksiz misafirin adet verisi göçü | |
| K8 (`91f7744`) | misafir göçünde adet ayarı | |

### Bu sürüm — 4. aşama (arka plan isolate)

| # | Commit | Kapsam |
|---|---|---|
| O35 (`91e8b14`) | LocalSession set/map bayrakları: yazımda `reload → diskle birleştir → yaz`, yüklemede birleştir | kalan teorik yarış: iki isolate aynı ms penceresinde → son yazan kazanır |
| K9 (`e6edcd5`) | `runningInBackgroundProvider`; bg'de `/auth/me` tazeleme + ilk import, RC identify, exitGuest başlamaz; bg girişlerinde zaman aşımlı `ensureLoaded` | |
| O36 (`00ebb90`) | `runBackgroundSyncWith` (bebekler yerel repo'dan, BabyController/subscription kurulmaz), dispose en sonda, zaman aşımı damgası; Android 4 dk / iOS 25 sn / FCM 20 sn | 403'te purge/salt-okunur yazımı yok |

### Bu sürüm — 5. aşama (auth)

| # | Commit | Kapsam |
|---|---|---|
| O2 (`e2bc85c`) | refresh Dio'suna 8/10 sn zaman aşımı; `RefreshResult {ok, rejected, transient}`; geçici hata → bekleyen istekler AĞ hatasıyla (`refresh_transient`) düşer, token korunur; tek-uçuş kilidi `finally` ile serbest | |
| O34 (`6c9581e`) | `AuthController._epoch`: `logout`/`deleteAccount`/`sessionExpired` kuşağı artırır; `_refreshInBackground`/`_postLogin`/`recordConsent`/`updateName` geç yanıtı yalnız kuşak aynıysa uygular | |
| O1 (`177018a`) | `SessionEndReason` yalnız gövde `code` ile (`session_superseded`/`token_not_valid`/diğer→unknown); `ApiClient.onSessionRejected` + prefs `auth_session_end_reason`; `sessionExpired` (token/abonelik/önbellek/kapsam temiz + FCM `deleteToken` + RC logOut; yerel veri/hatırlatıcı/SlotRegistry/cihaz kaydı dokunulmaz); `verifySession` öne gelişte; bg `'oturum yok'`; giriş banner'ı tek seferlik | backend #8 gelene dek superseded kodsuz → "Oturumun sonlandırıldı" genel metni; #9 gelene dek sunucu tarafında eski cihaz kaydı kalır (deleteToken ile push düşmez) |

### 6. aşama — şema v15 (aynı branch; sürüm kararı yayın öncesi, K-10) — kararlar kesinleşti, uygulama başladı

Sıra: **7a → 7b → 8 → 9 → docs.** 8b (O26 kalanı) bu aşamaya DAHİL DEĞİL.

| # | Commit | Kapsam / dosyalar | KALAN testler (mevcut koda karşı) | Risk |
|---|---|---|---|---|
| 7a | şema v15 + migration (davranış değişikliği yok) | `app_database.dart` (kolonlar, `schemaVersion=15`, `onUpgrade from<15` guard'lı, backfill UPDATE'leri), `.g.dart` (build_runner), `drift_schemas/v14,v15.json`, `test/drift/generated/`, `test/data/migration_v15_test.dart` | `schemaVersion == 15`; `SchemaVerifier` 14→15; veri dolu v14 DB: sağlık backfill (5B kararına göre), `settingsDirty` = dirty∧dolu∧¬caregiver, eski kolonlar korunur, `pushError` NULL; taze kurulum `createAll`. ("Önce" kanıtı: v14'te kolon yok → test derlenmez/`schemaVersion` 14 → doğal olarak düşer.) | orta (migration gerçek DB'lerde; bg isolate eşzamanlı açılış — ms süren işlem) |
| 7b | fix(K4/O21) sağlık delta | `health_repository.dart` (`_setStatus` dirty + callback, `pushDirty`, `pull` R1, aşı yankı güvencesi, `pushAll` yalnız göç), `record_controller.dart` (`_syncHealth`, polling'de yalnız dirty push), `initial_import.dart`/`migration_service.dart` (pull), ekranlar: `await` kalkar, invalidate | `_setStatus` yavaş ağda anında döner (gecikmeli adapter); yalnız dirty gönderilir (tam katalog değil); pull temiz satıra `done=false` yazar, dirty satırı korur; uçuş-içi düzenleme dirty kalır; 4xx → `pushError`; aşı adı yankılanmadı → dirty kalır, `pushError` yok; göç `pushAll` tam küme | yüksek (sağlık davranışı; O19 etkileşimi) |
| 8 | fix(O4) aile ayarları | `baby_repository.dart` (`updateFamilySettings` → `settingsDirty` + bebek `dirty` DEĞİL; `pushSettings` diff/base; `pullFromServer` içinde `GET /settings`; caregiver atlanır), `baby_controller.dart`, `family_settings.dart` (invalidate) | çevrimdışı ayar → pull ezmez, PATCH yalnız değişen anahtar; temiz ayar sunucudan dolar (yeni cihaz); dirty'yken değişmemiş anahtar sunucudan güncellenir; caregiver hiç PATCH atmaz; profil push'u ayar PATCH'i içermez | orta |
| 9 | K-1 banner + geri al | repo'lar: bellek-içi `pushErrors` → `pushError` kolonu (baby/memory/mom/cycle + health); `pushErrorCountProvider`; `SyncStatusBanner` 3. durum + `push_error_sheet.dart`; geri alma repo metotları; 8 çeviri anahtarı ×6 dil (api JSON, commit'lenmez) | pushError süreç ömrünü aşar (yeni repo örneği DB'den okur); başarılı push temizler; hard delete temizler; sayaç stream'i; geri al: sunucuda var → uygula, yok → sil / yerelde kalır (tablo başına); 403+caregiver → `'role'` | düşük-orta (UI) |
| docs | TASARIM §8 hash'leri, BULGULAR K4/O4/O21 DÜZELTİLDİ + 2b, DEVAM-NOTU (cihaz listesi: iki cihaz aşı işaretle/kaldır, dil farkı, ayar değişimi çevrimdışı→online, geri al) | | |

### Backend talepleriyle kesişim (#1, #2, #3) — v15 onlarsız ne kadar güvenli?

| Talep | v15 onsuz | Backend gelince değişen |
|---|---|---|
| #1 kalem damgası | Gerçek LWW yok: aynı kalemde çakışma "son push kazanır"; tek düzenleyici ailede fark yok; çakışma kalem bazında ve nadir. Veri kaybı yok (dirty korunur). | `pushDirty` gövdesine `client_updated_at`, pull `updated_at` → `serverUpdatedAt` (kolon hazır), `decideServerRow` damga dalı devreye girer. Migration gerekmez. |
| #2 `/health/sync` sözleşme + yanıtta güncel küme | Push sonrası yankı için **ek 3 GET** (yalnız dirty satır gönderildiğinde; polling'de gönderilmez). Sözleşmede uç yok ama kod/istemci uyumlu. | Post-push GET'ler kalkar; yankı ve `dirty=false` doğrudan yanıttan. |
| #3 aşı `key` | Aşı senkronu yalnız cihaz dili == sunucunun takvim dili iken çalışır; farklı dilde işaretler **yerelde dirty kalır** (kayıp yok, paylaşım yok) — v14'teki fiili durumdan kötü değil. | Push/pull `key` ile; yerel `itemKey` zaten katalog key'i; backend key'leri asset key'lerinden farklıysa bir kerelik yerel yeniden-anahtarlama (ad→key) gerekir → v16 adayı. |
| #5/#6/#4 | Bu aşamayı etkilemez. | — |

| 10 | (backend sonrası) | sağlık kalem damgası, `bulk` id eşlemesi, anı tombstone, anne `updated_at` | — | sözleşme güncellenince |
| 8b | (ayrı iş, bu aşama DIŞI) O26 kalanı: `patchSettings`/`saveEntry` bulut açıkken PATCH/push'u satır içinde bekliyor → `requestSyncSoon` | düşük | repo testi: patch sonrası ağ beklenmez |
