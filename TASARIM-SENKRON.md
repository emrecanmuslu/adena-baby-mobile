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
| K-4 | **v15 backfill:** yalnız `done=true` sağlık satırları `dirty=true` yapılır. |
| K-5 | **Aile ayarları:** son yazan kazanır yeterli; ancak PATCH yalnız **değişen alanları** gönderir. |
| K-6 | `memoriesProvider` drift **Stream**'e geçer (`list()` içindeki ağ beklemesi kalkar, pull arka planda). |
| K-7 | **Caregiver reddi:** repo `StateError` fırlatır, UI toast gösterir. |
| K-8 | **cycle `baby=null`:** backend kontrol edildi — `CycleSettings.baby` `null=True, blank=True` (`apps/cycle/models.py:27-30`), `ModelSerializer` alanı `allow_null=True` üretir → `PATCH {"baby": null}` **kabul edilir**. Backend talebi yok; istemci `toPatchJson`'ın null'ı atması **6. commit'te** düzeltilir. |
| K-9 | **O8 (`bulk` id eşlemesi):** backend talebi (`BACKEND-TALEPLERI.md` #4). İstemcide yalnız çift dokunma koruması. |
| K-10 | **Sürümleme:** commit 1-6 bir sürüm; commit 7-8 (şema v15) ayrı, sonraki sürüm. |

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
| R4 | **Sunucuda olmayan, yerelde `dirty=false` ve `isDeleted=false` olan satır kaldırılır** — yalnız pull'un TAM liste döndürdüğü tiplerde (anı, anne, adet kaydı, paylaşılan bebek). Korumalar (K-2): yalnız HTTP 200 + tam parse; sunucu listesi boşsa hiç silme; silinecek > 5 VE temiz satırların > %50'si ise silme atlanır ve loglanır. | O5(a), O7 |
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

## 5. Şema değişiklikleri (drift v14 → v15) — **sonraki sürüm**

| Tablo | Değişiklik | Mevcut kullanıcı etkisi |
|---|---|---|
| `health_statuses` | `dirty` (bool, default false), `clientUpdatedAt`, `serverUpdatedAt` (nullable) | Backfill (K-4): yalnız `done=true` satırlar `dirty=true` → bir kez push. |
| `babies` | `settingsDirty` (bool, default false) | Yerel ayar JSON ≠ `{}` ise `settingsDirty=true` → bir kez (değişen alan) PATCH. |
| `babies`, `memories`, `mom_entries`, `cycle_entries`, `health_statuses` | `pushError` (text, nullable) — R3 kalıcı red notu (K-1) | yok |
| `babies` (migrasyon UPDATE) | `myRole='caregiver' AND dirty=1 → dirty=0` (O20 artığı temizliği) | caregiver cihazında yetim dirty satırlar sunucuya döner |
| `memories`, `mom_entries`, `cycle_entries` | kolon yok; `serverUpdatedAt` pull'da yazılmaya başlar (v15 öncesi de yapılabilir, kolon zaten var) | yok |

Migration `from < 15`: `addColumn` + yukarıdaki `UPDATE`'ler. Veri kaybı riski yok; kolonlar ek.

---

## 6. Sağlık durumu (K4)

- **Delta push, backend değişikliği gerektirmiyor:** `HealthSyncView` gönderilen kalemleri tek tek `update` eder, listede olmayana dokunmaz → yalnız `dirty=true` kalemler gönderilince "A'nın işaretini B'nin push'u siler" biter. Katalog satırı üretimi GET'lerde de lazy → kayıp yok.
- **Çakışma:** hedef kalem başına LWW (`client_updated_at`, backend #1 ile). O zamana dek: dirty yerel kazanır (push edilir), temiz yerel sunucuyu alır (pull); iki cihaz aynı kalemi ters yöne çekerse son push kazanır (yalnız o kalem için).
- **Pull (K-3):** açılış, öne geliş (`main._onForeground`) ve işaretleme sonrası (`_setStatus` → push + pull); 1 dk polling'e eklenmez. `importFromCloud` "yalnız done ekler" yerine R1 ile tam uygulanır (işaret kaldırma da yayılır).
- **Aşı anahtarı** dil-bağımlı (O19): bu tasarım çözmez (backend #3); `dirty` sayesinde yanlış dildeki push başkasının işaretini silmez (eşleşmeyen `update` no-op).
- **O21:** `_setStatus` yerel yazım + dirty; push `requestSyncSoon`'a bırakılır, ekran anında döner.

---

## 7. O20 — caregiver düzenlemesi

**UI kilidi + repo reddi + K2 birlikte.** Yalnız K2 uygulanırsa caregiver'ın yerel düzenlemesi sonsuza dek dirty kalır (`pushDirty` rol filtresi göndermez, pull artık ezmez) → kalıcı ayrışma. Karar K-7: `BabyRepository.update/updatePhoto/updateFamilySettings` caregiver satırında `StateError` fırlatır; `baby_edit_screen._save` ve born-flow `canFullWrite` ile kilitlenir, hata toast'la gösterilir. Mevcut yetim dirty satırlar v15 migrasyonunda temizlenir (§5).

---

## 8. Uygulama planı

### Bu sürüm (commit 1-6)

| # | Commit | Kapsam | Risk | Testler |
|---|---|---|---|---|
| 1 | `sync_merge.dart` saf yardımcı | §3 fonksiyonları; davranış değişikliği yok | yok | dirty/deleted/damga matrisi; R4: boş liste, >5 ∧ >%50 oranı, 200 dışı/parse hatası; R3 sınıflandırma |
| 2 | fix(K2) bebek pull | `pullFromServer` R1/R2/R5; `pushDirty` R3 (kalıcı red → log + prefs `pushError`, kolon v15'te) | düşük | dirty bebek korunur; yüklenmemiş foto korunur; temiz bebek güncellenir; paylaşılan bebek listeden düşünce silinir |
| 3 | fix(O20) caregiver kilidi | UI kilidi + repo `StateError` + toast (migrasyon temizliği v15'te) | düşük | caregiver'da Kaydet yok; repo caregiver update → `StateError`, dirty üretmez |
| 4 | fix(O5) anı + anne | `_pull` R1/R2/R4 (+`serverUpdatedAt`), `memoriesProvider` Stream (K-6), `list()` ağ beklemez | orta | dirty korunur; tombstone geri gelmez; sunucuda olmayan temiz satır silinir; boş liste → silme yok; oran koruması |
| 5 | fix(O7) adet kayıtları | `_pullEntries` R1/R2/R4; çift dokunma `_saving` koruması (K-9) | orta | aynı desen + çift dokunma |
| 6 | fix(O6) adet ayarı | `getSettings` dirty ise GET uygulanmaz; dirty ayar `syncAll`'da yeniden denenir; `toPatchJson` `baby: null` gönderir (K-8); R8 | düşük | çevrimdışı patch → online GET ezmez → PATCH gönderilir; null baby patch'e girer |

### Sonraki sürüm (şema v15; commit 7-8)

| # | Commit | Kapsam | Risk | Testler |
|---|---|---|---|---|
| 7 | şema v15 + fix(K4/O21) sağlık | migration (`dirty`, damgalar, `pushError`, caregiver temizliği, K-4 backfill); `_setStatus` dirty; delta push; pull K-3 tetikleriyle; `importFromCloud` R1 | yüksek | migration v14→v15 backfill; yalnız dirty gönderilir; temiz satır sunucudan güncellenir; dirty korunur |
| 8 | fix(O4) aile ayarları | `settingsDirty`, `GET /settings` pull, değişen-alan PATCH (K-5) | orta | yerel dirty ayar ezilmez; temiz ayar sunucudan dolar; yalnız değişen alan gönderilir |
| 9 | "Gönderilemeyen değişiklik" banner'ı + "değişikliği geri al" (K-1) | `pushError` kolonu + `syncStatusProvider` sayacı + UI | düşük | — |
| 10 | (backend sonrası) | sağlık kalem damgası, `bulk` id eşlemesi, anı tombstone, anne `updated_at` | — | sözleşme güncellenince |
