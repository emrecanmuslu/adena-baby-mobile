# YAYIN 1.6.0 — kontrol listesi ve runbook

Branch `fix/adet-senkron` · sürüm **1.6.0+67** (`daadd31`) · tag'ler **`v1.6.0`** (Android) / **`ios-v1.6.0`** (iOS) · `flutter test` 1473/0, `flutter analyze` temiz. İçerik: adet modülü düzeltme turları 1–2 (`ADET-INCELEME.md`, `SAGLIK-METINLERI.md`) + senkron uyarısı telemetrisi. Sürüm notları: `SURUM-NOTLARI-1.6.0.md`.

## 0. Sürüm, build numarası ve şema

- **Build numarası:** CI pubspec'teki `+67`yi KULLANMAZ. `android.yml` ve `ios.yml` `--build-number = github.run_number + 100` verir. Bu, 1.5.0 hazırlığındaki notla aynı mekanizma (YAYIN-KONTROL §6.5). Workflow tag'i pubspec'in x.y.z kısmıyla doğrular (`v1.6.0` ↔ `1.6.0`); `+67` tag'e yazılmaz.
- **Son koşular (2026-10-11):** Android #52 → versionCode **152** (v1.5.0, Play alpha); iOS #103 → build **203** (ios-v1.5.0, TestFlight). Sonraki koşular **≥153 / ≥204** olur, mağazadaki son değerden büyüktür.
- **Kullanıcının kontrol etmesi gereken:** Play Console'da en yüksek versionCode'un 152'yi, App Store Connect'te en yüksek build'in 203'ü geçmediğini doğrula. CI dışında elle yüklenmiş daha yüksek bir build varsa tag'den önce bunu çöz.
- **Şema:** bu branch'te değişiklik yok. Drift `schemaVersion` = **15** (main ile aynı), `drift_schemas/` ve `lib/data/local/` değişmedi. Göç testleri (`migration_all_versions_test` vb.) değişmeden geçiyor.
- **Yeni kalıcı tercihler (SharedPreferences, sunucuya gitmez):**
  - `cycle_long_answers_<hesap>` — "Bu dönemde bir adet kaydını unutmuş olabilir misin?" sorusunun cevabı. Güncellemeden sonra anahtar yoktur: uç değer döngü hesaptan çıkar ve soru bir kez görünür (güvenli varsayılan). Bozuk JSON okunursa yakalanır ve soru yeniden sorulur. Başka cihazda soru bir kez daha görünebilir (bilinen sınır).
  - `sync_tel_last_fg_ms` — yalnız telemetri (arka planda kalınan süre). Yoksa `sync_bg_min = -1` yazılır; davranış etkilenmez.
  - Tek seferlik "doğum kontrol yöntemi değildir" bilgisi kurulum ekranında gösterilir, ayrı bayrak tutulmaz. Ayarlardaki kalıcı satırla birlikte her zaman erişilebilir.
  - Kaldırılan "LAM uyarıları" anahtarının kayıtlı `show_fertility_warning` değeri artık okunmaz ve zararsız kalır. Göç gerekmez.
- **v1.5.0 kullanıcısının güncellemesi:** mevcut çapa (`first_period_date`), mod ve kayıtlar olduğu gibi kalır. Kurulum sihirbazı yeniden açılmaz (emzirme değeri zaten dolu). Görünür davranış değişiklikleri bilinçlidir: medyan tahmin, uç değer dışlama, düzensizlik aralığı.

## 1. Bekleyen çeviri anahtarları (../api — kullanıcı commit + push + prod'da `seed_translations`)

### 1.1 Eklenen anahtarlar (75 anahtar × 6 dosya)

Dosyalar: `../api/apps/translations/data/{en,es,fr,ar,hi,zh}.json` — her dosyada aynı 75 anahtar eklendi (Türkçe kaynak metin = anahtar; `tr` dosyası yok).

| # | TR metin (anahtar) |
|---|---|
| 1 | Bu bir tahmindir; gebelikten korunma için kullanılamaz. |
| 2 | Adet takvimi tahmine dayalıdır ve bir doğum kontrol yöntemi değildir. |
| 3 | Doğurgan pencere (tahmini) |
| 4 | Bugün tahmini yumurtlama günün. |
| 5 | Doğurgan pencere (tahmini) içindesin. |
| 6 | Önemli |
| 7 | Emzirme, ancak şu üç koşulun hepsi birlikte sağlanıyorsa gebeliğe karşı geçici koruma sağlayabilir: doğumdan sonraki ilk 6 ay içindesin; bebeğin yalnız ya da neredeyse yalnız anne sütüyle besleniyor (gece dahil uzun aralar yok); adetin henüz dönmedi. Koşullardan biri bozulursa bu koruma kalkar. Korunma yöntemi için doktoruna danış. |
| 8 | Emzirme artık tek başına korunma sağlamaz; korunma gerekiyorsa doktoruna danış. |
| 9 | Emzirmiyorsan adetin genellikle doğumdan sonraki 6–8 hafta içinde döner; ovülasyon daha erken, 3–4. haftada olabilir. İlk adetini görmeden gebe kalabilirsin — korunma gerekiyorsa doktoruna danış. |
| 10 | İlk adetini görmeden de gebe kalabilirsin — ovülasyon adetten önce olabilir. Korunma gerekiyorsa doktoruna danış. |
| 11 | Emzirme yumurtlamayı baskılayıp adeti geciktirebilir. LAM (Laktasyonel Amenore Yöntemi) ancak şu üç koşul BİRLİKTE varsa gebeliğe karşı geçici koruma sağlayabilir: doğumdan sonraki ilk 6 ay; yalnız ya da neredeyse yalnız anne sütü (gece dahil uzun aralar yok); adetin dönmemiş olması. Biri bozulursa koruma kalkar. Ovülasyon ilk adetten önce olabilir. Korunma için doktoruna danış. |
| 12 | Emzirme döneminde gecikme sık görülür. Endişe varsa test yapabilir ya da doktoruna danışabilirsin. |
| 13 | Emzirme döneminde adetin geç dönmesi sık görülür. |
| 14 | Adet daha geç dönebilir |
| 15 | Devam etmek için bir seçenek seç |
| 16 | Genellikle 4–6 hafta |
| 17 | Loşia genellikle 4–6 hafta sürer, 8 haftaya uzayabilir. Doğumdan sonraki ilk 6 haftada girdiğin kanama loşia sayılır, ilk adet olarak kabul edilmez. |
| 18 | Doğumdan 6 haftadan uzun süre sonra kanaman devam ediyorsa hekimine söyle. |
| 19 | Bu loşia (lohusa kanaması) mı, ilk adetin mi? |
| 20 | Doğumdan sonraki ilk 8 haftada kanama çoğunlukla loşiadır. İlk adetin olduğunu düşünüyorsan döngü takibi bu günden başlar. |
| 21 | İlk adetim |
| 22 | Doğumdan sonraki kanama (loşia) adet değildir; genellikle 4–6 hafta sürer, 8 haftaya uzayabilir. |
| 23 | Doğumdan sonraki kanama loşiadır — iyileşme sürecinin parçası, adet değildir. Genellikle 4–6 hafta sürer, 8 haftaya uzayabilir. Akış zamanla azalırsa loşia; başlayıp koyulaşıp 4–7 gün sürerse muhtemelen ilk adettir. |
| 24 | Saatte bir ya da daha sık pedi dolduran kanama |
| 25 | Büyük pıhtılar |
| 26 | Yoğun kanamayla birlikte baş dönmesi, bayılma hissi ya da çarpıntı |
| 27 | 38°C ve üzeri ateş |
| 28 | Kötü kokulu akıntı |
| 29 | Azalmış kanamanın yeniden parlak kırmızı ve yoğun hale gelmesi |
| 30 | Beklemeden acil servise başvur ya da 112'yi ara: saatte bir ya da daha sık pedi dolduran kanama; büyük pıhtılar; yoğun kanamayla birlikte baş dönmesi, bayılma hissi ya da çarpıntı.<br>Aynı gün bir hekime başvur: 38°C ve üzeri ateş; kötü kokulu akıntı; şiddetli karın/kasık ağrısı; azalmış kanamanın yeniden parlak kırmızı ve yoğun hale gelmesi.<br>Bu bir tanı değildir. |
| 31 | Beklemeden acil servise başvur ya da 112'yi ara. |
| 32 | Bugün bir hekime başvurmanı öneririz. |
| 33 | Acil belirti |
| 34 | Hangi belirtilerde beklemeden yardım alman gerektiğini öğren. |
| 35 | Bu dönemde bir adet kaydını unutmuş olabilir misin? |
| 36 | {d} tarihinde başlayan {n} günlük döngü alışılmadık uzun görünüyor; tahminlerde şimdilik hesaba katılmadı. |
| 37 | Hayır, döngüm uzundu |
| 38 | Sonraki adet tahmini |
| 39 | Sonraki adet tahmini: {d} |
| 40 | Değişken seyir — hekimine sorabilirsin |
| 41 | Kanama kesildikten sonra başlayan ve 4–7 gün süren düzenli bir kanama ilk adetin olabilir. Yeniden parlak kırmızı ve yoğunlaşan kanamada hekimine başvur. |
| 42 | Doğumdan sonraki kanama loşiadır — iyileşme sürecinin parçası, adet değildir. Genellikle 4–6 hafta sürer, 8 haftaya uzayabilir. Kanama kesildikten sonra başlayan ve 4–7 gün süren düzenli bir kanama ilk adetin olabilir. Yeniden parlak kırmızı ve yoğunlaşan kanamada hekimine başvur. |
| 43 | Gebeliğini hafta hafta, bebeğinin gelişimiyle takip etmek için ana gebelik ekranını kullan. Hafta ve tahmini doğum tarihi ana gebelik ekranındaki bilgiyle aynıdır. |
| 44 | Gün geçti |
| 45 | Beklenen tarih (tahmini): {d} |
| 46 | Beklenen tarihten |
| 47 | {n} gün geçti |
| 48 | Önerilir |
| 49 | Beklenen tarihten {n} gün geçti. |
| 50 | Gebelik testi yapmanı öneririz; negatifse birkaç gün sonra tekrarlayabilirsin. |
| 51 | Uzun süredir adet görmedin — hekimine danışmanı öneririz. |
| 52 | Adetin 8 günden uzun sürüyor — hekimine danışmanı öneririz. |
| 53 | Tahmini yumurtlama |
| 54 | Sonraki adet (tahmini) · {d} |
| 55 | Sonraki adet (tahmini) |
| 56 | Doğurganlık (tahmini) |
| 57 | Yumurtlama (tahmini) |
| 58 | Tahmini yumurtlama günü |
| 59 | Tahmini doğurgan gün |
| 60 | Adetin yaklaşıyor (tahmini) 🌸 |
| 61 | Tahmini doğurgan pencere başlıyor |
| 62 | Bir yıldır (35 yaş üstünde 6 aydır) deniyorsan hekimine danışmanı öneririz. |
| 63 | 35 yaş ve üzerindeysen ve 6 aydır deniyorsan hekimine danışmanı öneririz. |
| 64 | Doğurgan pencerede 1–2 günde bir ilişki önerilir. |
| 65 | Ovülasyon testleri (LH) ve servikal mukus takibi tahmini güçlendirebilir. |
| 66 | Gebelik planlıyorsan genellikle günde 400 mikrogram folik asit önerilir; risk grubundaysan doktorun farklı doz önerebilir. |
| 67 | PMS belirtileri olabilir |
| 68 | Erken kayıplarda ovülasyon genellikle ~2 hafta içinde dönebilir; ilk adet çoğunlukla 4–6 hafta sonra gelir. |
| 69 | Bu ilk adetim |
| 70 | Doğumdan sonraki ilk haftalardaki kanama çoğunlukla loşiadır. Bunun ilk adetin olduğundan eminsen kaydedebilirsin; adet takvimin bu günden başlar. |
| 71 | Loşia olarak kaydet |
| 72 | İlk adetim olarak kaydet |
| 73 | Loşia genellikle 4–6 hafta sürer, 8 haftaya uzayabilir. Doğumdan sonraki ilk 6 haftada girdiğin kanama loşia sayılır; ilk adetin olduğundan eminsen kayıt ekranında "Bu ilk adetim"i seçebilirsin. |
| 74 | Tipik döngü |
| 75 | Son döngülerin ortanca değeri; tek seferlik uzun döngüler hesabı bozmaz. |

### 1.2 Değeri güncellenen mevcut anahtarlar (5 anahtar)

| TR metin (anahtar) | Güncellendiği dosyalar |
|---|---|
| Dikkat belirtileri | en.json, es.json, fr.json, ar.json, hi.json |
| Loşia | ar.json |
| Tahmini doğum | en.json, fr.json, ar.json, zh.json |
| Tahmini doğum: {d} | en.json, fr.json, ar.json, zh.json |
| Şiddetli karın/kasık ağrısı | hi.json, zh.json |

Toplam: **75 yeni anahtar** (6 dosyada 450 satır) + **5 anahtarın değeri** güncellendi (dosya bazında 16 satır).

Not: bazı eski anahtarlar ("Gün gecikti", "PMS olası", "LAM geçerli olabilir" vb.) kodda artık kullanılmıyor ama JSON'da duruyor; zararsız, silinmedi.

## 2. Zorunlu cihaz testleri (12 adım)

| # | Adım | Beklenen |
|---|---|---|
| 1 | Doğum tarihi bugün−35, emzirmiyor. Kayıt ekranı → "Bu ilk adetim" → **İlk adetim olarak kaydet**. Aynısını bir kez de **Loşia olarak kaydet** ile dene. | Onayda adet takvimi o günden başlar ve mod "Adet takibi" olur. Loşia seçiminde çapa kurulmaz, loşia ekranı sürer. |
| 2 | Doğum tarihi bugün−50. Kayıt ekranında "Orta" akış seç, loşia rengi seçme → Kaydet. | "Bu loşia (lohusa kanaması) mı, ilk adetin mi?" diyaloğu çıkar. "İlk adetim" takvimi başlatır, "Loşia" başlatmaz. |
| 3 | 28 + 56 günlük döngüler (bir ay boş), bugün yeni döngünün 21. günü. | Bugün ekranında "Bu dönemde bir adet kaydını unutmuş olabilir misin?" kartı çıkar. "Hayır, döngüm uzundu" kartı kapatır ve tahmine 56 günü katar; uygulama yeniden açılınca kart dönmez. "Kayıt ekle" düzenleme takvimini açar. |
| 4 | Döngüler 26/33/29/40 gün. | "Sonraki adet tahmini: 17–31 Ekim" gibi bir aralık ve "Tahmini · değişebilir" görünür. İstatistikte "Değişken seyir — hekimine sorabilirsin" yazar. |
| 5 | Takvimde bir güne dokun: önce Hedef = Adet takibi, sonra Hedef = Gebe kalmaya çalışıyorum. | Takipte "Gebe kalma olasılığı" satırı YOK. TTC'de satır VAR ve altında "Bu bir tahmindir; gebelikten korunma için kullanılamaz." yazar. |
| 6 | Belirtiler › Dikkat belirtileri: önce "Saatte bir ya da daha sık pedi dolduran kanama" → Kaydet; sonra yalnız "38°C ve üzeri ateş" → Kaydet. | İlkinde "Acil belirti" ve "Beklemeden acil servise başvur ya da 112'yi ara." çıkar. İkincisinde "Bugün bir hekime başvurmanı öneririz." çıkar ve 112 yazmaz. |
| 7 | Doğum bugün−70 ve sonra bugün−90, "Emzirmiyorum", adet yok. | "Emzirmiyorsan adetin genellikle doğumdan sonraki 6–8 hafta içinde döner…" metni görünür, LAM kartı görünmez. 90. günde ek olarak "Uzun süredir adet görmedin — hekimine danışmanı öneririz." kartı çıkar. |
| 8 | Doğum bugün−90 "Sadece anne sütü" → ayarlardan "Karışık"; sonra doğum bugün−200 "Sadece anne sütü". | 90. günde LAM kartı üç koşulu listeler. Karışık beslenmede ve 200. günde kart "Emzirme artık tek başına korunma sağlamaz; korunma gerekiyorsa doktoruna danış." olur. |
| 9 | Beklenen adetten 1 gün ve 7 gün sonrası (28 günlük düzenli döngü). | 1. gün "Gün geçti" ve "Beklenen tarihten 1 gün geçti." görünür; "gecikti" kelimesi geçmez. 7. gün "Gebelik testi yapmanı öneririz; negatifse birkaç gün sonra tekrarlayabilirsin." ve "Test · Önerilir" görünür. |
| 10 | TTC modu; TTC başlangıcı 2, 7 ve 13 ay önce. | Folik asit, "1–2 günde bir", LH/mukus notları her zaman görünür. 7. ayda "35 yaş ve üzerindeysen…" notu, 13. ayda "Bir yıldır (35 yaş üstünde 6 aydır)…" notu çıkar. |
| 11 | v1.5.0 kurulu ve adet verisi olan cihazı 1.6.0'a güncelle. | Açılış sorunsuz, sihirbaz açılmaz. Kayıtlar, çapa ve mod aynı kalır. Tahmin yalnız medyan veya uç değer kuralı yüzünden değişebilir. Takvim ve istatistik açılır. |
| 12 | Senkron telemetrisi: premium hesap, uçak modu AÇIK ama Wi-Fi bağlıyken sunucuya ulaşılamayan ağ, ya da sunucu kapalıyken kayıt ekle. "Senkron sorunu" şeridi → "Şimdi yeniden dene". Uygulamayı kapat-aç (internet açık). | Şerit görünür ve Tekrarla da başarısız olur. Bir sonraki açılıştan sonra (birkaç dakika içinde) Crashlytics › Non-fatals'ta `SyncAlertError` / reason `sync-alert` olayı görünür. Keys sekmesinde en az `sync_stage`, `sync_endpoint`, `sync_err_type`, `sync_launch`, `sync_online`, `sync_retry_tapped`, `sync_retry_result`, `app_version` = 1.6.0+… bulunur. Logs'ta `sync_alert_shown` ve `sync_retry_tapped` breadcrumb'ları vardır. |

Not (adım 12): yalnız uçak modu "Çevrimdışı" şeridini gösterir (bu bilinçli; senkron hatası sayılmaz). "Senkron sorunu" için cihazın çevrimiçi görünüp sunucuya ulaşamaması gerekir: Wi-Fi açık + yönlendiricinin interneti kapalı, ya da test sunucusu kapalı.

## 3. Telemetri okuma rehberi (Crashlytics `sync-alert`)

**Filtreleme:** Crashlytics › Issues › **Non-fatals** › arama "SyncAlertError" (ya da olay başlığında `stage=`). Her olayın **Keys** sekmesinde `sync_*` custom key'leri, **Logs** sekmesinde `[sync] sync_error …`, `sync_alert_shown`, `sync_retry_tapped`, `sync_retry_result` breadcrumb'ları bulunur. Aynı (aşama + hata türü + HTTP kodu + istisna) imzası oturum başına bir kez non-fatal olur; tekrarlar `sync_err_repeats` sayacındadır. Toplu sayım için BigQuery dışa aktarımı açıksa `custom_keys` üzerinden gruplanabilir; konsolda sürüm filtresi (1.6.0) kullanılmalıdır.

| Key kombinasyonu | İşaret ettiği neden |
|---|---|
| `sync_err_type = exception` + `sync_exc` = `SqliteException` (ya da Drift istisnası), `sync_endpoint = -` | **H5** — yerel DB kilidi/WAL (arka plan turu ile çakışma). `sync_last_bg` yakın zamanda "başladı/zaman aşımı" ise güçlenir. |
| `sync_err_type = connectionError/unknown`, `sync_exc` = `SocketException` / `HttpException` ("Connection closed…"), `sync_launch = warm`, `sync_bg_min` büyük, `sync_fg_ms` küçük (< ~5000), `sync_online = yes` | **H2** — askıdan dönüşte bayat keep-alive bağlantı. `sync_retry_result = success` ise geçici; `same_error` ise havuz da bozuk. |
| `sync_stage = refresh` ya da `sync_exc = refresh_transient`, ya da `sync_refresh_inflight = yes` ve `sync_refresh_age_ms` büyük | **H1** — token yenileme turu (zaman aşımı/askı). |
| `sync_online = yes`, `sync_retry_result = same_error` tekrar tekrar, `sync_attempts` yüksek, `sync_http` 4xx/5xx | **Kalıcı neden** — sunucu tarafı hata ya da istemci–sunucu sözleşme sorunu; `sync_endpoint` hangi uç olduğunu söyler. |
| `sync_online = no` ya da `sync_conn = none` | Gerçek bağlantı yok — hata değil, eşik dışı tutulur. |

**Karar eşiği (öneri):** ilk karar için **en az 30 olay ve en az 10 farklı kullanıcı**, ya da yayından sonra **7 gün** (hangisi önce gelirse). Bir kombinasyon olayların ≥%60'ını açıklıyorsa o hipotez için düzeltme planlanır. Dağınıksa 14 güne uzatılır. Tek kullanıcıdan gelen çok sayıda olay ayrı değerlendirilir.

## 4. Yayın sırası

1. **Çeviriler:** `../api`'de §1'deki JSON değişikliklerini commit + push. Prod'da 6 dil için `seed_translations --locale <x>`; ardından uygulamada EN/AR'de yeni metinlerin göründüğünü kontrol et.
2. **Çalışma ağacı (kullanıcı kararı, merge'den ÖNCE):** mobile-app'te commit'lenmemiş `CLAUDE.md` ve `.github/workflows/test.yml` değişiklikleri ile staged silmeler (`claude-memory/`, BULGULAR/INCELEME*/YAYIN-KONTROL/SURUM-NOTLARI/… belgeleri) kullanıcı tarafından netleştirilecek: commit, ayrı commit ya da geri alma. Bu branch'teki commit'ler bunlara dokunmadı. `SURUM-NOTLARI.md` silinmiş durumda olduğu için 1.6.0 notları `SURUM-NOTLARI-1.6.0.md`'de.
3. **Branch push → CI:** `git push -u origin fix/adet-senkron`. `test.yml` yalnız elle tetiklenir (Actions → Run workflow); 3 TZ job'u yeşil olmalı.
4. **Cihaz testleri:** §2'deki 12 adım Android + iOS'ta.
5. **Merge + tag:**
   ```
   git checkout main && git merge --no-ff fix/adet-senkron
   git tag v1.6.0 && git push origin main v1.6.0        # android.yml → Play (alpha)
   git tag ios-v1.6.0 && git push origin ios-v1.6.0     # ios.yml → TestFlight
   ```
   Not: v1.5.0 Android'de alpha'da kaldı (önceki karar: kullanıcı istemedikçe üretime terfi yok). 1.6.0 için üretim yayını bu runbook'ta isteniyor; Play'de incelemeye gönderme ve üretime terfi Play Console'dan ELLE yapılır.
6. **Kademeli yayın:** Google Play üretim **%10 → 48 saat izleme → %50 → %100**. App Store **Phased Release** (7 gün).
7. **İlk 7 gün izleme ve durdurma eşikleri:**

| Gösterge | Durdur (rollout'u dondur / phased release'i duraklat) |
|---|---|
| Crash-free users (1.6.0) | **< %99,5** ya da 1.5.0 referansından **0,3 puandan fazla** düşük |
| Adet ekranlarında yeni fatal (`cycle_*` / `CycleTodayScreen`, `CycleCalendarScreen`, `CycleStatsScreen`, kayıt sayfası) | **≥3 kullanıcıda** aynı yeni fatal |
| Adet ekranlarında non-fatal (Flutter hata) | Yeni bir hata imzası **≥10 kullanıcıda** |
| `sync-alert` hacmi | Etkilenen kullanıcı oranı 1.6.0'da **günlük aktif kullanıcının > %5'i** ya da gün gün artış, ve `sync_online = yes` ağırlıklı → incele; **> %10** → durdur |
| Kullanıcı geri bildirimi | Doğum sonrası/loşia akışında yanlış çapa ya da "takvim kendiliğinden başladı" şikâyeti **≥2** → incele |

Durdurma sonrası: düzeltme 1.6.1 olarak çıkar (şema değişmediği için geri alma DB açısından güvenli; yine de mağazada eski sürüme dönüş yok).
