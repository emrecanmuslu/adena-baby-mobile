# DEVAM NOTU — fix/audit-bulgular

Güncelleme: 2026-10-11 · Branch: `fix/audit-bulgular` (main'e merge EDİLMEDİ) · Son test: **1203 geçti, 0 başarısız**, `flutter analyze` temiz.

## Tamamlananlar (commit sırasıyla)
1. aşama: K3 `37f05f8`, K1 `00cd3fb`, K5 `e5f1a66`
2. aşama (senkron): docs `a5cdc94`, sync_merge `eb7102f`, K2 `7823480` + 3b `20ed1f5`, O20 `ce7e04c`, O5 `c6a55dc`, O7 `4352738`, O8 `3426724`, O6 `89cc58f`
3. aşama (adet/misafir): K6 `249aad1`, K7 `eb25b3c`, K8 `91f7744`
4. aşama (arka plan): O35 `91e8b14`, K9 `e6edcd5`, O36 `00ebb90`, docs `e7ced27`
5. aşama (auth): O2 `e2bc85c`, O34 `6c9581e`, O1 `177018a`, docs `90df7b7`; O1 artıkları `9789951` (refresh token yokken neden ezilmez), `c7ba8ad` (FCM kaydı yalnız başarılı POST'ta)
6. aşama / GRUP 1 (şema v15): TASARIM docs `a5571f4` + kararlar `0fd6f5e`; 7a şema+migration `c5ffa58`; 7b K4/O21 `e328ee8`; 8 O4 `beda831` (+test `6c70672`); 9 K-1 banner/geri al `3c7d94c`
Tasarım: `TASARIM-SENKRON.md` (kararlar K-1..K-10, R1-R9, §8 plan + hash'ler). Backend talepleri: `BACKEND-TALEPLERI.md` (9 madde).

## Otonom koşu (2026-10-11) — durum
- **Tamamlanan grup:** GRUP 0, 1, 2, 3, 4 (D1–D45 triyajı: 27 DÜZELTİLDİ, 9 KABUL, 2 DOĞRULANAMAZ, 4 GEÇERSİZ, 1 KARAR-BEKLEYEN, D33 önceden kapalı), 5 (şüpheliler — BULGULAR §6 durum notu).
- **Sıradaki grup:** GRUP 6 — YAYIN-KONTROL.md + FINAL-RAPOR.md (yalnız doküman). GRUP 5 kontrol noktası: şüpheliler BULGULAR §6'da durumlandı; kod değişikliği gerektirenler GRUP 3/4'te yapıldı, kalanlar yalnız doğrulama adımı (YAYIN-KONTROL.md).
- **KARAR-BEKLEYEN sayısı:** 9 (`KARAR-BEKLEYEN.md`: KB-1..KB-3 geri al; KB-4 exact-alarm UI; KB-5 çapa; KB-6 DST kapsamı; KB-7 aşı anahtarı; KB-8 bakıcı ilaç planı; KB-9 hesap silmede yerel veri).
- Sonra: GRUP 3 (kalan ORTA), GRUP 4 (DÜŞÜK triyaj), GRUP 5 (şüpheliler), GRUP 6 (YAYIN-KONTROL.md), FINAL-RAPOR.md.

## Kalan iş sırası
c) ~~Şema v15~~ TAMAMLANDI (GRUP 1; v15'in ayrı sürüm olup olmayacağı yayın öncesi kullanıcı kararı, K-10).
d) ~~O26 kalanı~~ TAMAMLANDI (`f93c849`).
e) ~~Kalan ORTA~~ TAMAMLANDI (GRUP 3; O19 KABUL/backend, O29/O17 kısmi).
f) ~~DÜŞÜK~~ TAMAMLANDI (GRUP 4; durumlar BULGULAR §5 satır sonlarında).
g) ~~Şüpheliler~~ TAMAMLANDI (GRUP 5; BULGULAR §6 durum notu; cihaz adımları YAYIN-KONTROL.md).
h) **Yayın öncesi:** `../api/apps/translations/data/*.json`'da commit'lenmemiş 22 anahtar (D30 ilaç notu dahil; uyku bitiş uyarısı dahil; caregiver salt-okunur notu; misafir-adet teklif + silme metinleri; 3 oturum-sonu banner metni; 13 K-1 banner/geri al metni) → api'de commit + `seed_translations --locale <x>`; `BACKEND-TALEPLERI.md` 9 madde backend ekibine (#8 `code: session_superseded` gelene dek banner genel metni gösterir).

## Çalışma kuralları (devam ederken)
Her bulgu: önce mevcut koda karşı KALAN test (yeni API'ye dayanan kısım geçici kopyayla ayrılır) → en küçük düzeltme → `flutter analyze` + tam `flutter test` → `fix(Kx): …` ayrı commit → TASARIM §8 hash + BULGULAR "DÜZELTİLDİ" notu. Yan sorun düzeltilmez, raporlanır.

## Cihazda doğrulanacaklar (4. aşama)
- Android workmanager turu: `adb shell cmd jobscheduler run -f com.adenababy.adena_baby <jobId>` (jobId: `adb shell dumpsys jobscheduler | grep adenababy`) → logcat'te tur; DbWatchdog prefs `db_last_bg_sync_outcome` = `bitti` (ya da `zaman aşımı`), `/auth/me` ve `/babies` isteği YOK (sunucu logu), yalnız `POST /sync`.
- iOS BGTask: Xcode durdurma noktasında `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.adenababy.bgSync"]` → aynı damga; 25 sn üstünde `zaman aşımı`.
- FCM `sync_nudge` uygulama kapalıyken: yalnız o bebek için `POST /sync`; widget/hatırlatıcı güncellenir; damga yazılmaz (push yolu).

## Cihazda doğrulanacaklar (5. aşama — auth)
- **İkinci cihazdan giriş:** aynı hesapla B cihazında giriş → A cihazı arka plana alınıp öne getirilince (ya da ilk 401'de) `/login`'e düşer ve banner çıkar (backend #8 yokken "Oturumun sonlandırıldı…" genel metni; #8 sonrası "Hesabına başka bir cihazdan giriş yapıldı…"). Banner bir kez görünür; uygulamayı kapatıp açınca tekrar çıkmaz.
- **Zorunlu çıkış sonrası aile push'u YOK (Android + iOS):** B cihazında paylaşımlı bebeğe kayıt gir → A cihazına bildirim gelmemeli (`deleteToken`). Sunucu logunda A'nın eski FCM token'ına gönderim hatası görülebilir (backend #9'a kadar kayıt sunucuda kalır).
- **Yeniden giriş dirty kayıtları gönderir:** A'da zorunlu çıkıştan ÖNCE çevrimdışı girilmiş kayıt, aynı hesapla yeniden giriş sonrası `POST /sync` ile gider (yerel veri silinmedi).
- **Yerel ilaç hatırlatıcısı sürer:** zorunlu çıkıştan sonra planlı ilaç bildirimi saatinde yine çalar (cancelAll çağrılmaz, SlotRegistry korunur).
- **Bg turu:** token süresi dolmuş/refresh reddedilmişken workmanager turu → DbWatchdog prefs `db_last_bg_sync_outcome` = `oturum yok`; uygulama öne gelince `/login` + banner (prefs `auth_session_end_reason`).
- **Geçici ağ hatası oturumu düşürmez:** uçak modunda token süresi dolmuş istek → "sunucuya ulaşılamadı", login'e düşme yok (O2).

## Cihazda doğrulanacaklar (6. aşama — şema v15)
- **Migration:** v14 kurulu cihazda güncelle → açılış sorunsuz; `health_statuses` gelişim/diş done satırları ilk turda push (sunucu logu `POST /health/sync` yalnız dirty kalemler); aşı için istek YOK; sahip bebeğin dolu ayarı bir kez tam sözlük `PATCH /settings`.
- **İki cihaz aşı:** A işaretler → B öne gelince görür; B kaldırır → A öne gelince kalkar. Dil farklı iki üye: işaret yerelde kalır, kaybolmaz (dirty), sunucuya gitmez (beklenen, backend #3'e kadar).
- **Ayar:** A çevrimdışı birim değiştirir → online olunca yalnız `units` PATCH; B (yeni cihaz/üye) öne gelince aynı birimi görür. Caregiver cihazı PATCH atmaz.
- **Geri al banner'ı:** kalıcı 4xx üretip (ör. sunucuda silinmiş anıyı düzenle → 404) banner "{n} değişiklik sunucuya gönderilemedi" → sheet → "Geri al" → sunucuda yoksa onay diyaloğu → yerel silinir; sayaç 0'a iner.

## Cihazda doğrulanacaklar (GRUP 3)
- **O16 (Android 14+):** yeni kurulumda açılışta Ayarlar'a zıplama OLMAMALI; kesin alarm izni yokken beslenme hatırlatıcısı ±dakika gecikmeyle gelir.
- **O14:** uygulamayı birkaç kez aç/kapa → `adb shell dumpsys alarm` / bekleyen bildirimlerde gelişim/diş dürtmesinin tetik zamanı DEĞİŞMEMELİ.
- **O15:** bebek sil → o bebeğin aşı/ilaç/beslenme bildirimleri bekleyenlerden düşer.
- **O12:** satın alma sırasında bağlantıyı kes → "Premium etkinleştirildi" + kilitler açık; sonraki açılışta sunucu senkron.
- **O17 iOS NSE:** eşin ileri tarihli (yarın) beslenme girişi → bu cihazda widget/hatırlatıcı günler sonrasına KURULMAMALI (Swift değişikliği Dart testiyle doğrulanamaz).
- **O18:** dil değiştir → push gönder → tek banner/tek senkron; Crashlytics'te sahte fatal yok.
- **O25:** yeni adet logla → "adetin yaklaşıyor" bildirimi yeni tarihe (bekleyenlerde 600000 id).
