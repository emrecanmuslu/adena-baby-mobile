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
15. O15 (+I5): bebek sil → o bebeğin aşı/ilaç/beslenme bildirimleri VE özel/randevu hatırlatıcıları (Hatırlatıcılar ekranından eklenmiş) bekleyenlerden düşer; ikinci bebeğin hatırlatıcıları kalır (Ayarlar → Geliştirici → bekleyen bildirimler).
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

### H. Düzeltme turu 3 (INCELEME)
41. **I1 (KRİTİK senaryo):** v14 kurulu, FREE hesapla 3 aşı işaretle → v15'e güncelle → premium satın al (mağaza sayfasından dönüş = öne geliş) → aşı ekranı: 3 işaret DURUYOR; sunucu logunda `GET /babies/{id}/vaccines` göç `POST /health/sync` (tam küme) tamamlanmadan ÖNCE GELMEMELİ; göç bitince `GET` gelir, işaretler sunucuda da `done`. Crashlytics'te `health_pull_cleared_done` olayı 0 olmalı.
42. **I1 (lapse) + J2:** premium bitir (isPremium false) → birkaç aşı daha işaretle → yeniden abone ol → işaretler durur; sunucu logunda önce tek `POST /health/sync` (**birleşim**: yalnız done=true + damgalı kalemler; damgasız `done:false` gövdede YOK), sonra `GET`'ler.
43. **I4:** v14 kurulu cihazda v15'e güncelleme sırasında `adb shell am force-stop com.adenababy.adena_baby` ile ilk açılışı kes (zamanlama şansa bağlı; birkaç deneme) → sonraki açılış sorunsuz, Crashlytics'te `duplicate column` YOK.
44. **I8/I16:** hesabı sil → doğrudan giriş ekranı (onboarding'e uğramaz); silme sırasında senkron turu çalışıyorsa bile cihazda bebek/kayıt kalmaz.
45. **I6:** aile üyesi 3 kaydı 1-2 sn arayla girsin → bu cihazda 3 ayrı aile bildirimi (üst üste yazılmaz).
46. **I13:** bakıcı cihazında sunucuda olan bir plan KB-8 öncesi düzenlenmiş gibi dirty bırakılamaz (artık StateError); yalnız gerçekten yerel-only plan "yalnız bu cihazda" etiketi alır.

### I. Düzeltme turu 4 (INCELEME-2)
47. **J1 (göçte ağ kesintisi) — K1(a) ile güncellendi:** v14 free, 3 aşı işaretli → v15 → premium satın al → göç sırasında (foto yüklenirken) uçak modu → ağ gelince aşı ekranı: 3 tik DURUYOR; prefs'te `premium_synced_accounts_v1` hesabı **İÇERİR** (bebek sunucuya gitmişse) ve `health_reseed_accounts_v1` içerir; sonraki açılışta overlay YOK, `POST /babies` YOK, önce `POST /health/sync` (birleşim), sonra `GET`'ler; Crashlytics `health_pull_cleared_done` 0. Bebek sunucuya hiç gitmediyse (foto POST'u düştü) `health_reseed` KURULMAZ, `premium_synced` yine yazılır → bkz. 59.
48. **J1(b) (lazy sunucu kümesi):** sunucuda aşı kaydı hiç olmayan (yeni oluşturulmuş) bebek + yerelde temiz done=true tik → tam turda `GET /vaccines` hepsi pending gelir → tikler DURUR, Crashlytics `health_pull_lazy_server_skipped` 1 olay, sonraki açılışta `POST /health/sync` (tikler sunucuya gider), ardından pull normal.
49. **J1 (v14'te sağlık yüklemesi düşmüş premium, mümkünse):** v14'te premium iken çevrimdışı 2 aşı işaretle, hiç online olmadan v15'e güncelle → online ol → tikler durur (48 ile aynı yol); yeniden işaretleme gerekmez.
50. **J2 iki cihaz:** sahip A + ebeveyn B; A çevrimdışıyken B 2 aşı işaretler (sunucuda done); A premium'u biter → A online → yeniden abone olur → B'nin cihazında 2 tik DURUR (A'nın `POST /health/sync` gövdesinde damgasız `done:false` yok).
51. **J3 (misafir→hesap):** misafir "bebeğim yok — adet takibi" → sihirbazı doldur, 2 adet kaydı → kayıt ol → "Aktar" → adet sekmesi: ayar/kayıtlar görünür, sihirbaz AÇILMAZ; sunucu logunda `PATCH /cycle/settings` yalnız değişen alanlarla (sihirbaz yeniden doldurulmadığı için eski ayar ezilmez).
52. **J3 (çıkış→giriş):** adet sekmesi açıkken çıkış yap → aynı hesapla giriş → adet sekmesi hesabın ayarını gösterir (restart gerekmez).
53. **J4 (Android 14+):** uygulama arka plandayken beslenme bildirimi → "Ertele 10 dk" → 10 dk (±dakika) sonra "Beslenme zamanı (ertelendi)" GELİR; Android 12/13'te tam dakikasında. Crashlytics'te `bg_snooze_schedule` non-fatal YOK (kesin alarm izni yokken `ExactAlarmPermissionException` araması).
54. **J5:** bebek değiştiriciden geçiş / misafir göçü hemen ardından bebek sil → Geliştirici → bekleyen bildirimler: silinen bebeğin feed/sağlık/ilaç/özel hatırlatıcı id'leri YOK.
55. **J6/J12:** Android 14+ ilaç planı oluştur (ilk plan → M4 diyaloğu) → "İzin ver" → sistem sayfasında izin ver → geri dön → bekleyen ilaç dozu bildirimleri exact (adb `dumpsys alarm` içinde `*walarm*` / exact); beslenme hatırlatıcısı da yeniden kurulmuş (bekleyenlerde aynı id, exact). Diyalog bir daha çıkmaz; Bildirimler → "Tam zamanında bildirim" "İzin verildi".
56. **J7 (uygulama KAPALI):** aile üyesi 1 sn arayla 3 kayıt girsin → bu cihazda 3 AYRI aile bildirimi (FCM açılış kuyruğu; 45 "uygulama açık" varyantıydı).
57. **J13:** özel periyodik hatırlatıcı oluştur → sil → prefs'te `notif_interval_<id>` anahtarı YOK; bg bildirim metni (uygulama kapalı, EN dilinde) İngilizce.
58. **J15:** tek bebekli hesapta özel hatırlatıcı varken bebeği sil → bekleyenlerde hatırlatıcı YOK (yeniden kurulmadı).

### J. Düzeltme turu 5 (INCELEME-3)
59. **K1 uçtan uca kurtarma zinciri:** v14 free, 2 aşı işaretli, bebek fotoğraflı → v15 → premium satın al → göç sırasında bebek POST'u düşsün (foto yüklenirken uçak modu; göç "Bebekler" adımında) → ağ gelmeden overlay biter, prefs `premium_synced_accounts_v1` hesabı İÇERİR, `health_reseed_accounts_v1` İÇERMEZ, sunucu logunda `POST /babies/{id}/health/sync` YOK → ağ gelince öne getir: `POST /babies` 2xx → aynı turda `GET /vaccines` (hepsi pending) → 2 tik DURUR, Crashlytics `health_pull_lazy_server_skipped` 1 → uygulamayı kapat/aç: overlay YOK, `POST /babies` YOK, `POST /health/sync` gövdesinde 2 aşı `done:true` → sonraki turda `GET /vaccines` 2 done → ikinci cihazda (ebeveyn) tikler görünür; ebeveyn birini kaldırır → sahipte öne gelince kalkar (K-4).
60. **K1(a) hafif yol:** sunucuya gitmiş bebekte göçün "Sağlık" adımında ağ kes → overlay biter; prefs iki bayrak da hesabı içerir → ağ gelince kapat/aç: overlay YOK, `POST /babies`/`POST /sync` yeniden-yükleme YOK, yalnız `POST /health/sync`; ardından `GET`'ler ve tikler durur. Üçüncü açılışta `POST /health/sync` YOK.
61. **K2 (iki cihaz, son tik kaldırma):** sahip A + ebeveyn B, tek aşı işaretli (sunucuda done; her iki cihaz pull'la görmüş) → B tiki kaldırır → A öne gelince tik KALKAR (sunucu tamamen pending olsa da), Crashlytics `health_pull_lazy_server_skipped` 0; A'yı kapat/aç → `POST /health/sync` YOK (reseed kurulmadı); B'de tik geri GELMEZ.
62. **K3 (dil uyuşmazlığı):** v14'te TR'de 2 aşı işaretli, uygulama dili EN'e alınmış → v15 premium → göç → açılış-pull turlarında `POST /health/sync` yalnız bir kez (göç), sonraki açılışlarda tekrar YOK; Crashlytics `health_pull_lazy_server_skipped` 0; TR tikleri yerelde durur (EN katalogta görünmez — bilinen I10/KB-7).

## 2. Bekleyen çeviri anahtarları (api repo, commit'lenmedi)
Dosyalar: `../api/apps/translations/data/{en,es,fr,ar,hi,zh}.json` (6 dosya, 32 anahtar — `test/i18n/translation_keys_test.dart` listeyle birebir doğrular). Yayın öncesi api'de commit + prod'da `seed_translations --locale <en|es|fr|ar|hi|zh>`. **I11:** test, `CI=true` ya da `REQUIRE_API_TRANSLATIONS=1` ortamında api dizini yoksa FAIL eder (yerelde uyarıyla atlar); CI'da `flutter test` koşulacaksa api repo'su yan yana checkout edilmeli. Bu turda yeni çeviri anahtarı EKLENMEDİ (kullanıcıya görünen yeni metin yok).

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

## 3. Backend talepleri özeti (`BACKEND-TALEPLERI.md`, 11 madde) — istemci hangi maddede bekliyor
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
| 11 | `/health/sync` kalem bazında `client_updated_at` + LWW | J2/K2: istemci birleşim semantiği + `serverUpdatedAt` onay damgasıyla güvenli düşüyor; iki cihaz aynı kalemi ters yöne çekerse "son istek kazanır" |

## 4. v15 ayrı sürüm mü? (K-10)
Kod aynı branch'te; `schemaVersion` 14→15 tek sıçrama, migration testli (`migration_v15_test.dart`, SchemaVerifier + veri dolu geçiş). Karar yayın öncesi kullanıcıda: (a) tek sürüm (tüm bulgular + v15) — tek mağaza turu, migration riski aynı sürümde; (b) önce v15'siz sürüm, sonra v15 — iki tur, risk ayrışır. Öneri: (a) **tek sürüm**, çünkü K4/O4/K-1 davranışları v15 kolonlarına bağlı ve ayrıştırmak branch'i bölmeyi gerektirir. Yayın kademeli: **Google Play kademeli yayın %10 → %50 → %100** (her kademede Crashlytics'te migration/startup hatası ve `db_last_bg_sync_outcome` dağılımı izlenir; v2..v14'ten gelen cihazlar M1 ile testli) ve **App Store phased release** (7 gün, aynı izleme). Geri alma planı: şema geri alınamaz (v15 ek kolon; eski sürüm v15 DB'yi açamaz) → kademe durdurma + hotfix, downgrade değil.

## 5. main'e merge öncesi adımlar
1. `flutter analyze` temiz, `flutter test` 1243 (inceleme) → 1289/0 (düzeltme turu 3) → **1334/0 (düzeltme turu 5 sonu)**; CI `test.yml` üç TZ'de aynı suite. `flutter build apk --debug` ile Android hattı.
2. Cihaz listesi §1'den en az: 4, 5, 9, 10, 12, 13, 15, 17 (iOS), 22.
3. `KARAR-BEKLEYEN.md` KB-1..KB-9 kararları (özellikle KB-4 exact-alarm UI, KB-9 hesap silmede yerel veri).
4. api repo: §2 çeviri anahtarları commit + `seed_translations`; backend #8 (küçük) tercihen aynı yayında.
5. `BULGULAR.md` §2b ve `DEVAM-NOTU.md` güncel; `TASARIM-SENKRON.md` §8 hash'leri.
6. Mağaza metadata güncelleme borcu: yeni görünür özellikler (geri al banner'ı, zorunlu çıkış banner'ı) için Play/App Store metin/SS kontrolü (bkz. hafıza "mağaza metadata güncelleme borcu").
7. **Sürüm numarası artırımı:** YAPILDI (`9c8b636`): `pubspec.yaml` **1.5.0+66** (şema v15 + geniş davranış değişikliği). Tag'ler `v1.5.0` (Android) / `ios-v1.5.0` (iOS) — workflow'lar tag'i pubspec'in x.y.z kısmıyla karşılaştırır, `+66` tag'e YAZILMAZ; CI build numarası `run_number+100`. Eski sürüm v15 DB'yi açamaz, geri alma yok (kademeli yayın).
8. **Sürüm notları 7 dilde:** YAPILDI (`d79a4f2`): `SURUM-NOTLARI.md` (tr/en/zh/hi/es/fr/ar; Play kısa ≤500, App Store uzun ≤4000, karakter sayılarıyla). Mağaza metadata borcu notu (hafıza) ile birlikte: yeni görünür özellikler için SS kontrolü.
9. Merge: `git merge --no-ff fix/audit-bulgular` (kullanıcı yapacak; bu koşuda merge/push YOK).

## 6. Yayın sırası (runbook) — 1.5.0+66

Önkoşul: kod tamam (`fix/audit-bulgular` @ düzeltme turu 5 + yayın hazırlığı commit'leri), `flutter test` 1334/0, `flutter analyze` temiz. Kod davranışı bu bölümle DEĞİŞMEZ.

### 6.1 api: çeviri anahtarları
- `../api/apps/translations/data/{ar,en,es,fr,hi,zh}.json` değişiklikleri (32 anahtar, §2) **commit + push** (api repo `main`).
- Prod'da (Hetzner, `/opt/adena/api`): `manage.py seed_translations --locale <x>` tüm diller (tr dahil; tr kaynak metin) → `GET /content/translations?locale=…` ile 3-4 anahtar örneklemesi.
- **Sıra bağımlılığı:** bu push yapılmadan CI'daki `translation_keys_test` (I11, `CI=true`) KIRMIZIDIR — api checkout'u `main`'i çeker.

### 6.2 CI secret'ı → CI yeşil
- GitHub → mobil repo → Settings → Secrets and variables → Actions → **`API_REPO_TOKEN`**: `emrecanmuslu/adena-baby-api` için fine-grained PAT, izin **Contents: Read-only** (classic PAT ise `repo`). Workflow `permissions: contents: read` ile koşar; api repo'su `api/` dizinine sparse checkout (`apps/translations/data`).
- Push sonrası `Test (analyze + flutter test)` iş akışı 3 job (UTC / Europe/Berlin / America/New_York) yeşil olmalı. Mevcut `android.yml`/`ios.yml` test koşmaz (yalnız build+yükleme); release tag'leri onları tetikler.
- Yerelde doğrulanamayan tek şey workflow'un kendisi (actionlint yok; YAML parse + yapısal kontrol yapıldı). İlk koşuda kırmızı olursa en olası neden secret/izin ya da 6.1'in henüz yapılmamış olması.

### 6.3 Zorunlu cihaz testleri (15 adım; §1 numaralarıyla)
Öncelik: veri kaybı riski > sessiz bozulma > görünür UX. En az bir Android 14+ ve bir iOS cihaz; iki hesap (sahip + ebeveyn) ve bir bakıcı; v14 (1.4.26) kurulu bir cihaz.

| # | §1 | Senaryo | Neden zorunlu |
|---|---|---|---|
| 1 | 9 | v14 → v15 migration (güncelle, aç; gelişim/diş done satırları bir kez push, aşıya istek yok, ayar bir kez PATCH) | şema geri alınamaz |
| 2 | 29 | Daha eski sürümden (v2/v3 arşiv APK, mümkünse) güncelleme → açılış sorunsuz (M1 duplicate-column) | prod'da görülmüş çökme sınıfı |
| 3 | 43 | Migration'ı `force-stop` ile kes → sonraki açılış sorunsuz (I4) | kesinti penceresi |
| 4 | 41 | I1 KRİTİK: free'de 3 aşı işaretli → v15 → premium → tikler durur, göç `POST /health/sync` pull'dan önce | veri kaybı kapısı |
| 5 | 42 | I1 lapse + J2: premium biter → işaretle → yeniden abone → tek birleşim `POST`, tikler durur | reseed semantiği |
| 6 | 47 | J1 + K1(a): göçte ağ kesintisi → iki bayrak, sonraki açılış overlay'siz hafif yol | döngü yok |
| 7 | 59 | K1 uçtan uca kurtarma zinciri (bebek POST'u düşer → bebek oluşur → lazy pull → reseed → K-4) | yeni kod yolu |
| 8 | 61 | K2 iki cihaz: ebeveyn son tiki kaldırır → sahipte kalkar, reseed geri yazmaz | regresyon düzeltmesi |
| 9 | 10 | İki cihaz aşı/gelişim/diş: işaretle/kaldır karşı cihazda görünür (sürüm notu vaadi) | ana vaat |
| 10 | 53 | J4 Android 14+: arka planda "Ertele 10 dk" → bildirim gelir, Crashlytics `bg_snooze_schedule` yok | O16 regresyonu |
| 11 | 32 (+55) | M4 kesin alarm diyaloğu: ilk ilaç planında bir kez; "İzin ver" sonrası planlar exact ve yeniden kurulur (J12) | izin akışı |
| 12 | 4 | Zorunlu çıkış + banner: ikinci cihazdan giriş → ilk cihaz `/login` + banner bir kez | sürüm notu vaadi |
| 13 | 12 | K-1 geri al: kalıcı 4xx → banner → sheet → "Geri al" → onay → sayaç 0 | sürüm notu vaadi |
| 14 | 51 | J3 misafir→hesap "Aktar": adet ayar/kayıt görünür, sihirbaz açılmaz, PATCH yalnız değişen alan | veri ezme riski |
| 15 | 15 | O15/I5: bebek sil → tüm bildirimleri (aşı/ilaç/beslenme/özel/randevu) bekleyenlerden düşer; ikinci bebeğinkiler kalır | yetim bildirim |

Ek olarak 36 (KB-9 hesap silme → cihaz verisi silinir) sürüm notunda vaat edildiğinden 15'e **sığmadıysa 16. adım olarak** koşulması önerilir.

**Yayın sonrası gözlem (zorunlu değil):** 1–3, 5–8, 11, 13–14, 16–28, 30–31, 33–35, 37–40, 44–46, 48–50, 52, 54, 56–58, 60, 62. Bunlar ya testle örtülü (I6/J7 serileştirme, O25, K3) ya düşük olasılıklı (D16/D19) ya da telemetriyle izlenebilir (6.7).

### 6.4 TZ testleri
CI (6.2) üç TZ'de yeşilse M6/KB-6 TZ doğrulaması TAMAM sayılır (§1-37 kapanır). CI koşulamıyorsa Mac/Linux'ta elle: `TZ=Europe/Berlin flutter test` ve `TZ=America/New_York flutter test` (tam suite; ~1 dk).

### 6.5 Merge + tag
```
git checkout main && git pull
git merge --no-ff fix/audit-bulgular        # kullanıcı yapar
git tag v1.5.0 && git push origin main v1.5.0          # android.yml → Play (alpha track)
git tag ios-v1.5.0 && git push origin ios-v1.5.0       # ios.yml → TestFlight
```
Not: workflow tag doğrulaması `v1.5.0` ↔ pubspec `1.5.0` (build numarası `+66` tag'e girmez; CI `run_number+100` kullanır). Play'de incelemeye gönderme ELLE (`changesNotSentForReview`), üretim track'ine terfi Play Console'dan.

### 6.6 Kademeli yayın
- **Google Play:** production'a **%10** staged rollout → **48 saat** izleme (6.7) → %50 → 48 saat → %100.
- **App Store:** Phased Release (7 gün otomatik: %1→2→5→10→20→50→100); eşik aşılırsa "Pause".
- Geri alma yok (v15 şema): durdur + hotfix (1.5.1) — downgrade değil.

### 6.7 İlk 7 gün izleme ve DURDURMA eşikleri
Kaynak: Crashlytics (fatal + non-fatal `SyncTelemetry` olayları), sunucu logu (`/opt/adena/api`, 15 gün), Play/ASC vitals. "Durdur" = rollout'u o kademede duraklat, kök neden + hotfix.

| Sinyal | Nerede | Beklenen | İncele | DURDUR |
|---|---|---|---|---|
| Migration çökmesi (`duplicate column name`, `no such column`, `SqliteException` onUpgrade/`_addColumnIfMissing`, açılış watchdog) | Crashlytics fatal, sürüm 1.5.0 filtreli | 0 | ≥1 kullanıcı | **> %0,1** güncellenen kullanıcı ya da **≥3 kullanıcı** 24 saatte |
| Crash-free kullanıcı oranı | Crashlytics / Play vitals | ≥ 1.4.26 oranı (−0,2 pt tolerans) | −0,2…−0,5 pt | **< %99,0** ya da 1.4.26'ya göre **−0,5 pt** |
| `health_pull_cleared_done` (temiz done=true → sunucu pending) | Crashlytics non-fatal | sahip cihazlarda ~0; ebeveyn cihazında meşru kaldırmalarda tekil | kullanıcı başına **≥3 aşı** tek olayda | **≥10 farklı kullanıcı** 48 saatte (kapı/J1(b) delinmiş demektir) |
| `health_pull_lazy_server_skipped` | Crashlytics non-fatal | sahip bebek başına **en çok 1** (göç sonrası ilk pull) | aynı bebekte ≥3 / gün (döngü) | premium kullanıcıların **> %5**'inde tekrar |
| R4 `stale_delete_skipped` (sunucu listesi şüpheli küçük → silme atlandı) | Crashlytics non-fatal | 0 | ≥1 | **> 20 olay / gün** (sunucu sayfalama/liste kesilmesi) |
| `ExactAlarmPermissionException` / `bg_snooze_schedule` | Crashlytics non-fatal + fatal | 0 | ≥1 | **≥5 kullanıcı** (J4 düzeltmesi delinmiş) — Android 14+ |
| Push-error banner yükü (kalıcı 4xx) | Sunucu logu: `POST /sync`, `/babies`, `/memories`, `/health/sync`, `/cycle/*` 4xx oranı (401/403 hariç) | < %0,5 istek | %0,5–1 | **> %1** 24 saatte ya da tek uçta ani sıçrama (istemci bu durumda sessiz değil, banner gösterir) |
| `db_last_bg_sync_outcome` = `zaman aşımı` payı | Crashlytics non-fatal (DbWatchdog) | < %5 | %5–10 | **> %10** |
| Zorunlu çıkış banner'ı / `session_superseded` yokken 401 fırtınası | Sunucu logu 401 oranı, `/auth/refresh` 403 | 1.4.26 ile aynı | +%50 | **2×** (O34 epoch hatası) |

### 6.8 Backend talepleri #1–#11 — bu yayın için gerekli olan var mı?
**Yok.** Her madde istemcide güvenli düşüşle karşılanıyor (§3 tablosu): #1/#11 (damga) → birleşim semantiği + `serverUpdatedAt` onay damgası, çakışmada "son istek kazanır"; #2 → post-push GET yankısı; #3 → farklı dilde aşı işareti yerelde dirty kalır; #4 → id farklıysa dirty kalır; #5 → R4 koruması + telemetri; #6 → damgasız LWW; #7 → istemci 500'lük sayfalar; #8 → genel banner metni; #9 → eski token'a push `deleteToken` ile düşer; #10 → ileri-tarih eşiği. Önerilen öncelik: **#11** (sağlık LWW — KB-12 kalıntısını ve K2 kabulünü kapatır) > **#8** (küçük; banner metni doğru olur) > #3 (dil-bağımsız aşı anahtarı; KB-7) > #1/#2 (sağlık damga/yanıt kümesi; #11 ile birlikte) > #9 > #10 > #5 > #4 > #6 > #7.

### 6.9 Yayın sonrası iş listesi
- **KB-6 ek:** DST'de 1 gün kayabilen görünür hesaplar (`cycleAddDays`/UTC-gün yardımcısına taşıma; liste KARAR-BEKLEYEN'de).
- **KB-11:** `pullSettings` yükü (`GET /settings` tur başına N istek) → `updated_at` koşullu ya da `GET /babies` gömülü.
- **KB-13:** ilaç bildirimi id şeması (`planId % 1000`) → aralık genişletme + geçiş mutabakatı.
- **J-düşükler:** J13(1) (= KB-13); INCELEME-3 K4 (adet eylem-anı okumalarına `accountId` — tutarlılık, iş zorunlu değil).
- **Bilinen kalıntılar:** KB-12 ek (v14'ten kalan onaysız tik + sunucuda sıfır done → tik korunur ve reseed ile gider; backend #11 ile kapanır); O19/KB-7 (farklı dilde aşı işaretleri paylaşılmaz; backend #3); KB-4 (exact-alarm için ayrı UI girişi yok).
- Mağaza metadata borcu (SS'ler: geri al banner'ı, oturum banner'ı, "tam zamanında bildirim" satırı).

