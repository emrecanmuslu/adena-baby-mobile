# YAYIN-KONTROL — fix/audit-bulgular (2026-10-11)

Branch `fix/audit-bulgular`, main'e merge EDİLMEDİ. Bu dosya yayın öncesi tek kontrol listesidir: cihaz testleri, bekleyen çeviri anahtarları, backend talepleri, v15 sürüm sorusu ve merge adımları.

## 1. Birleşik cihaz test listesi (adım → beklenen)

### A. Arka plan isolate (4. aşama — O35/K9/O36)
1. Android: `adb shell cmd jobscheduler run -f com.adenababy.adena_baby <jobId>` (jobId: `adb shell dumpsys jobscheduler | grep adenababy`) → logcat'te tur; DbWatchdog prefs `db_last_bg_sync_outcome` = `bitti` (ya da `zaman aşımı`). Sunucu logunda `/auth/me` ve `/babies` YOK, yalnız `POST /sync` (+ sağlık `POST /health/sync` yalnız dirty varsa).
2. iOS BGTask: Xcode durdurma noktasında `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.adenababy.bgSync"]` → aynı damga; 25 sn üstünde `zaman aşımı`.
3. FCM `sync_nudge` uygulama kapalıyken → yalnız o bebek için `POST /sync`; widget/hatırlatıcı güncellenir; damga yazılmaz.

### B. Auth (5. aşama — O1/O2/O34 + artıklar)
4. Aynı hesapla ikinci cihazda giriş → ilk cihaz öne gelince (ya da ilk 401'de) `/login` + banner (backend #8 yokken "Oturumun sonlandırıldı…", #8 sonrası "Hesabına başka bir cihazdan giriş yapıldı…"). Banner bir kez; kapat-aç → tekrar çıkmaz.
5. Zorunlu çıkış sonrası B cihazından paylaşımlı bebeğe kayıt → A cihazına push GELMEZ (Android + iOS; `deleteToken`). Sunucu logunda eski token'a gönderim hatası olabilir (#9'a kadar).
6. A'da çıkıştan önce çevrimdışı girilen kayıt → aynı hesapla yeniden giriş → `POST /sync` ile gider; yerel ilaç hatırlatıcısı saatinde çalar; yeniden girişte cihaz kaydı `POST /me/devices` ATILIR (O1 artığı `c7ba8ad`).
7. Bg turu token süresi dolmuşken → `db_last_bg_sync_outcome` = `oturum yok`; öne gelince `/login` + banner.
8. Uçak modunda token süresi dolmuş istek → "sunucuya ulaşılamadı", login'e düşme YOK (O2).

### C. Şema v15 (GRUP 1 — 7a/7b/8/9)
9. v14 kurulu cihazda güncelle → açılış sorunsuz; gelişim/diş done satırları ilk turda push (sunucu logu yalnız dirty kalemler), aşı için istek YOK; sahip bebeğin dolu ayarı bir kez tam sözlük `PATCH /settings`.
10. İki cihaz aşı: A işaretler → B öne gelince görür; B kaldırır → A öne gelince kalkar. Farklı dilde iki üye: işaret yerelde kalır (dirty), sunucuya gitmez (backend #3'e kadar beklenen).
11. Ayar: A çevrimdışı birim değiştirir → online olunca yalnız `units` PATCH; B öne gelince aynı birimi görür; caregiver cihazı PATCH atmaz.
12. Kalıcı 4xx üret (sunucuda silinmiş anıyı düzenle → 404) → banner "{n} değişiklik sunucuya gönderilemedi" → sheet → "Geri al" → sunucuda yoksa onay diyaloğu → yerel silinir; sayaç 0.

### D. GRUP 3 (ORTA)
13. O16 (Android 14+): yeni kurulumda açılışta Ayarlar'a zıplama OLMAMALI; kesin alarm izni yokken beslenme hatırlatıcısı ±dakika gecikmeyle gelir. (KB-4: UI girişi yok.)
14. O14: uygulamayı birkaç kez aç/kapa → bekleyen bildirimlerde gelişim/diş dürtmesinin tetik zamanı DEĞİŞMEMELİ.
15. O15: bebek sil → o bebeğin aşı/ilaç/beslenme bildirimleri bekleyenlerden düşer.
16. O12: satın alma sırasında bağlantıyı kes → "Premium etkinleştirildi" + kilitler açık; sonraki açılışta sunucu senkron.
17. O17 iOS NSE: eşin ileri tarihli (yarın) beslenme girişi → bu cihazda widget/hatırlatıcı günler sonrasına KURULMAMALI (Swift değişikliği Dart testiyle doğrulanamaz).
18. O18: dil değiştir → push gönder → tek banner/tek senkron; Crashlytics'te sahte fatal yok.
19. O25: yeni adet logla → "adetin yaklaşıyor" yeni tarihe (bekleyenlerde 600000 id); kayıp/postpartum'a geç → doğurganlık bildirimi kalkar.
20. O13: uygulama açıkken gece yarısını geç → "Bugün" kartı sıfırlanır.
21. O33: "Yerel verileri sil" → `ApplicationSupport/memories`, `/babies` boş; bekleyen bildirim yok.
22. O9: 1000+ kayıtla free→premium göçü zayıf ağda tamamlanır (sunucu logunda 500'lük `POST /sync` parçaları).

### E. GRUP 4 (DÜŞÜK, cihaz gerektirenler)
23. D4: bildirim panelini aşağı çekmişken (inactive) push → yalnız in-app banner, OS bildirimi yok.
24. D5/D6: iOS soğuk açılış → tek `POST /me/devices`; RevenueCat satın alma dinleyicisi çalışıyor (satın alma sonrası premium anında).
25. D14: dil değiştir → anında uygulanır, spinner yok; taze çeviri arka planda gelir.
26. D16 (doğrulanamaz): tz alınamayan cihazda günlük ilaç hatırlatıcısı saatinin doğru olup olmadığı — nadir; yalnız gözlem.
27. D19 (doğrulanamaz): iOS'ta 3+ bebek × çok dozlu planlar + randevular → 64 bekleyen bildirim sınırı aşılıyor mu (Ayarlar → Geliştirici → bekleyen bildirimler).
28. D31: prematüre bölümünde tahmini doğum tarihinden türetme → debug'da kırmızı ekran yok.

### F. Düzeltme turu 1
29. M1: v2/v3 kadar eski bir kurulumdan (mümkünse arşiv APK) güncelle → açılış sorunsuz, veri yerinde (duplicate-column düzeltmesi).
30. M2: A cihazı adet modülünü bebeğe bağlar; B (önceden senkronlanmış, bağsız) döngü uzunluğunu değiştirir → sunucuda bebek bağı KALIR (PATCH yalnız `expected_cycle_length`).
31. M3: "her 15 dk" özel hatırlatıcı → uygulamayı kapat-aç → tetik zamanı korunur; aralığı 30 dk yap → yeniden kurulur.
32. M4 (Android 12+): ilk ilaç planı kaydında izin yoksa "Tam zamanında bildirim" diyaloğu bir kez; "Daha sonra" → bir daha çıkmaz; Bildirimler ekranında satır + "İzin ver" sistem sayfasını açar; izin verince satır "İzin verildi". iOS'ta satır/diyalog YOK.
33. M7: dil EN iken uygulama kapalıyken aile push'u / "Ertele 10 dk" / bg turunun kurduğu "Kaydı unuttun mu?" İngilizce gelir.
34. KB-5: gebelik modunda "Adet takibine dön" → bekleyen bebek kalkar, adet ekranı bekleme modunda ("ilk adetini gir").
35. KB-8: bakıcı cihazında İlaç & Vitamin: ekle düğmesi yok, plan kartı açılmaz, not "Bakıcı rolünde…"; doz işaretleme çalışır ve ebeveynde görünür.
36. KB-9: hesabı sil → bu cihazda bebek/kayıt/anı/fotoğraf kalmaz; başka hesapla girince o hesabın verisi yerinde. Çevrimdışı silme denemesi → hata, yerel veri yerinde.

### G. Düzeltme turu 2
37. **M6 (Mac/Linux'ta koşulacak, bu makinede TZ yok sayılıyor):** `TZ=Europe/Berlin flutter test test/engines test/journeys test/data/cycle_repository_k6_test.dart` ve `TZ=America/New_York flutter test test/engines test/journeys test/data/cycle_repository_k6_test.dart` → hepsi yeşil; ek olarak DST geçiş günlerinde (Mart son Pazar / Ekim-Kasım) adet "gün N" ve TDT hesabı 1 gün kaymıyor.
38. **M1 notu:** v2/v3'ten (çok eski kurulum) güncelleme mevcut prod'da da `duplicate column name: account_id` ile çöküyordu (v15 öncesi hata). Crashlytics'te "duplicate column name" araması yapılmalı; varsa etkilenen kullanıcı sayısı rapora; v15 ile güncellenince düzelir (migration testli).
39. N1: iki bebekli hesap (biri bakıcı, biri sahip) — bakıcı bebeğin ilaç ekranında Düzenle/ekle yok, sahip bebeğin ekranında var; aşı/gelişim/diş işaretleme bakıcı bebekte toast, sahip bebekte çalışır.
40. N2: bakıcı cihazında KB-8 öncesi oluşmuş plan → kartta "Bu plan yalnız bu cihazda; ailenle paylaşılmadı" + Sil; hatırlatıcısı çalmaya devam eder; Sil → yerelden kalkar, sunucuya istek yok; ebeveynde görünmez (zaten görünmüyordu).

## 2. Bekleyen çeviri anahtarları (api repo, commit'lenmedi)
Dosyalar: `../api/apps/translations/data/{en,es,fr,ar,hi,zh}.json` (6 dosya, 32 anahtar — `test/i18n/translation_keys_test.dart` listeyle birebir doğrular). Yayın öncesi api'de commit + prod'da `seed_translations --locale <en|es|fr|ar|hi|zh>`.

| Anahtar (TR) | Kaynak |
|---|---|
| Toplulukta engellediğin kullanıcıları yönet | önceki oturumdan bekliyor |
| Bakıcı rolünde bebek bilgileri salt-okunurdur; düzenlemeyi ebeveyn/sahip yapabilir. | O20 |
| Kayıt olmadan tuttuğun adet takvimi kayıtların bu cihazda duruyor. Hesabına aktaralım mı? … | K7 |
| Aktarmadığın adet kayıtların bu cihazdan KALICI olarak silinecek. Bu işlem geri alınamaz. | K7 |
| Hesabına başka bir cihazdan giriş yapıldı; bu cihazdaki oturum kapatıldı. | O1 |
| Oturumun sona erdi. Lütfen tekrar giriş yap. | O1 |
| Oturumun sonlandırıldı. Lütfen tekrar giriş yap. | O1 |
| {n} değişiklik sunucuya gönderilemedi | K-1 |
| Gönderilemeyen değişiklikler | K-1 |
| Değişikliği geri al | K-1 |
| Tümünü geri al | K-1 |
| Sunucudaki hâli yüklendi | K-1 |
| Yerel değişiklik silindi | K-1 |
| Silme gönderilemedi | K-1 |
| Bu kayıt yalnız bu cihazda kalacak | K-1 |
| Bu kayıt sunucuda yok. Yerel değişiklik silinsin mi? | K-1 |
| Sunucuya ulaşılamadı | K-1 |
| Adet ayarları | K-1 |
| Aşı | K-1 |
| Diş | K-1 |
| Bitiş zamanı başlangıçtan önce olamaz | O27 |
| Verilen dozlar ve plan listesi ailenle paylaşılır. | D30 |
| Bakıcı rolünde planları ebeveyn/sahip düzenler; sen dozları işaretleyebilirsin. | KB-8 |
| Hesabın devre dışı bırakılacak ve oturumun her cihazda kapanacak. 30 gün … (yeni uzun metin) | KB-9 |
| Tam zamanında bildirim | M4 |
| İlaç ve beslenme hatırlatıcılarının tam saatinde gelmesi için "Alarmlar ve hatırlatıcılar" izni gerekli. … | M4 |
| Daha sonra | M4 |
| İzin ver | M4 |
| İzin verildi | M4 |
| İzin yok — hatırlatıcılar birkaç dakika gecikebilir | M4 |
| Bu plan yalnız bu cihazda; ailenle paylaşılmadı | N2 |

## 3. Backend talepleri özeti (`BACKEND-TALEPLERI.md`, 10 madde) — istemci hangi maddede bekliyor
| # | Başlık | İstemci bağımlılığı |
|---|---|---|
| 1 | Sağlık kalemlerine damga | K4: `serverUpdatedAt` kolonu hazır; gelince gerçek LWW (migration gerekmez) |
| 2 | `/health/sync` sözleşme + yanıtta küme | K4: post-push 3 GET (yankı) yanıttan okunacak |
| 3 | Aşı dil-bağımsız `key` | O19: farklı dilde aşı işaretleri paylaşılmıyor (yerelde dirty kalıyor) |
| 4 | `bulk` yanıtında id eşlemesi | O8: sunucu id'si farklıysa satır dirty kalır |
| 5 | Anı tombstone / `include_deleted` | O5: R4 "listede yok → sil" koruması riskli kalıyor |
| 6 | Anne kaydına `updated_at` | O5: damgasız LWW |
| 7 | Records `/sync` batch sınırı | O9: istemci 500'lük sayfalıyor; sunucu üst sınırı |
| 8 | 401 gövdesine `code: session_superseded` | O1: banner genel metni gösteriyor |
| 9 | Supersede'de eski cihaz kaydını kapat | O1: eski token'a push denenir (deleteToken ile düşer) |
| 10 | family_activity `last_feed_ts` = en yeni kayıt | O17: istemci yalnız ileri-tarih eşiği uyguluyor |

## 4. v15 ayrı sürüm mü? (K-10)
Kod aynı branch'te; `schemaVersion` 14→15 tek sıçrama, migration testli (`migration_v15_test.dart`, SchemaVerifier + veri dolu geçiş). Karar yayın öncesi kullanıcıda: (a) tek sürüm (tüm bulgular + v15) — tek mağaza turu, migration riski aynı sürümde; (b) önce v15'siz sürüm, sonra v15 — iki tur, risk ayrışır. Öneri: (a) **tek sürüm**, çünkü K4/O4/K-1 davranışları v15 kolonlarına bağlı ve ayrıştırmak branch'i bölmeyi gerektirir. Yayın kademeli: **Google Play kademeli yayın %10 → %50 → %100** (her kademede Crashlytics'te migration/startup hatası ve `db_last_bg_sync_outcome` dağılımı izlenir; v2..v14'ten gelen cihazlar M1 ile testli) ve **App Store phased release** (7 gün, aynı izleme). Geri alma planı: şema geri alınamaz (v15 ek kolon; eski sürüm v15 DB'yi açamaz) → kademe durdurma + hotfix, downgrade değil.

## 5. main'e merge öncesi adımlar
1. `flutter analyze` temiz, `flutter test` 1203/0 (bu koşu sonu). `flutter build apk --debug` ile Android hattı.
2. Cihaz listesi §1'den en az: 4, 5, 9, 10, 12, 13, 15, 17 (iOS), 22.
3. `KARAR-BEKLEYEN.md` KB-1..KB-9 kararları (özellikle KB-4 exact-alarm UI, KB-9 hesap silmede yerel veri).
4. api repo: §2 çeviri anahtarları commit + `seed_translations`; backend #8 (küçük) tercihen aynı yayında.
5. `BULGULAR.md` §2b ve `DEVAM-NOTU.md` güncel; `TASARIM-SENKRON.md` §8 hash'leri.
6. Mağaza metadata güncelleme borcu: yeni görünür özellikler (geri al banner'ı, zorunlu çıkış banner'ı) için Play/App Store metin/SS kontrolü (bkz. hafıza "mağaza metadata güncelleme borcu").
7. **Sürüm numarası artırımı:** şema v15 (ek kolon) → `pubspec.yaml` version (ör. 1.4.27+66) ve `ios-v…`/Android tag'leri; eski sürüm v15 DB'yi açamaz, geri alma yok (kademeli yayın).
8. **Sürüm notları 6 dilde:** Play "Yenilikler" ve App Store "What's New" (tr/en/es/fr/ar/hi/zh): oturum banner'ı, gönderilemeyen değişiklik/geri al, aile ayarı ve sağlık işaretlerinin aile arasında eşitlenmesi, ilaç hatırlatıcı izni (Android), düzeltmeler. Mağaza metadata borcu notu (hafıza) ile birlikte.
9. Merge: `git merge --no-ff fix/audit-bulgular` (kullanıcı yapacak; bu koşuda merge/push YOK).
