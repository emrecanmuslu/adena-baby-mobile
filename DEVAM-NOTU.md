# DEVAM NOTU — fix/audit-bulgular

Güncelleme: 2026-10-11 · Branch: `fix/audit-bulgular` (main'e merge EDİLMEDİ) · Son test: **1096 geçti, 0 başarısız**, `flutter analyze` temiz.

## Tamamlananlar (commit sırasıyla)
1. aşama: K3 `37f05f8`, K1 `00cd3fb`, K5 `e5f1a66`
2. aşama (senkron): docs `a5cdc94`, sync_merge `eb7102f`, K2 `7823480` + 3b `20ed1f5`, O20 `ce7e04c`, O5 `c6a55dc`, O7 `4352738`, O8 `3426724`, O6 `89cc58f`
3. aşama (adet/misafir): K6 `249aad1`, K7 `eb25b3c`, K8 `91f7744`
4. aşama (arka plan): O35 `91e8b14`, K9 `e6edcd5`, O36 `00ebb90`
Tasarım: `TASARIM-SENKRON.md` (kararlar K-1..K-10, R1-R9, §8 plan + hash'ler). Backend talepleri: `BACKEND-TALEPLERI.md`.

## Kalan iş sırası
b) **Auth:** O1 (refresh reddi → oturum düşmüyor, zombi), O2 (`/auth/refresh` zaman aşımsız, tek-uçuş kilidi askıda), O34 (`_refreshInBackground` ↔ logout yarışı).
c) **Şema v15** (sonraki sürüm): K4/O21 sağlık delta push + pull, O4 aile ayarları (`settingsDirty`), `pushError` kolonu + banner (K-1), caregiver temizliği artık gereksiz (K9/O20 ile).
d) **O26 kalanı** + `_maintainAnchorAfterRemoval`'ın bulut açıkken anlık PATCH'i → `requestSyncSoon`'a bırak (TASARIM §8 satır 8b).
e) **Kalan ORTA:** O3, O9, O10, O11, O12, O13, O14, O15, O16, O17, O18, O19, O22, O23, O24, O25, O27, O28, O29, O30, O31, O32, O33, O37.
f) **DÜŞÜK:** D1–D45 (D33 kapandı; O33/D33 notlarına bakın).
g) **Şüpheliler:** BULGULAR §6 listesi (cihaz/backend doğrulaması gerekenler).
h) **Yayın öncesi:** `../api/apps/translations/data/*.json`'da commit'lenmemiş 3 anahtar (caregiver salt-okunur notu; misafir-adet teklif + silme metinleri) → api'de commit + `seed_translations --locale <x>`; `BACKEND-TALEPLERI.md` 7 madde backend ekibine.

## Çalışma kuralları (devam ederken)
Her bulgu: önce mevcut koda karşı KALAN test (yeni API'ye dayanan kısım geçici kopyayla ayrılır) → en küçük düzeltme → `flutter analyze` + tam `flutter test` → `fix(Kx): …` ayrı commit → TASARIM §8 hash + BULGULAR "DÜZELTİLDİ" notu. Yan sorun düzeltilmez, raporlanır.

## Cihazda doğrulanacaklar (4. aşama)
- Android workmanager turu: `adb shell cmd jobscheduler run -f com.adenababy.adena_baby <jobId>` (jobId: `adb shell dumpsys jobscheduler | grep adenababy`) → logcat'te tur; DbWatchdog prefs `db_last_bg_sync_outcome` = `bitti` (ya da `zaman aşımı`), `/auth/me` ve `/babies` isteği YOK (sunucu logu), yalnız `POST /sync`.
- iOS BGTask: Xcode durdurma noktasında `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.adenababy.bgSync"]` → aynı damga; 25 sn üstünde `zaman aşımı`.
- FCM `sync_nudge` uygulama kapalıyken: yalnız o bebek için `POST /sync`; widget/hatırlatıcı güncellenir; damga yazılmaz (push yolu).
