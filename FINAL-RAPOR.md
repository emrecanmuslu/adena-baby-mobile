# FINAL RAPOR — fix/audit-bulgular otonom koşu (2026-10-11)

Branch `fix/audit-bulgular` (main'e merge YOK, push YOK, `../api` commit YOK). Kaynak: `BULGULAR.md` (9 kritik / 37 orta / 45 düşük), `TASARIM-SENKRON.md`, `DEVAM-NOTU.md`, `BACKEND-TALEPLERI.md`, `KARAR-BEKLEYEN.md`, `YAYIN-KONTROL.md`.

## 1. Özet

| Kategori | Sayı |
|---|---|
| DÜZELTİLDİ (bu koşu) | ORTA 23 (O17, O29 kısmi) + K4/O21/O4/O26 + K-1 banner + O1 artıkları 2 + DÜŞÜK 27 = 58 madde |
| KARAR-BEKLEYEN | 9 başlık (KB-1..KB-9; D43 bunlardan biri) — 8'inde güvenli varsayılan uygulandı, KB-9 atlandı |
| KABUL / DÜZELTİLMEYECEK | O19 (backend #3), D2 D8 D11 D15 D17 D20 D21 D27 D35 D44 = 11 |
| DOĞRULANAMAZ | D16, D19 (yalnız doğrulama adımı) |
| GEÇERSİZ | D7, D12, D25, D45 |
| Toplam branch commit | 90 (bu koşuda 62: GRUP 0 2, GRUP 1 10, GRUP 2 1, GRUP 3 19, GRUP 4 29, docs kontrol noktaları ve GRUP 6 raporu dahil) |
| Test | denetim başı 1100 → koşu başı 1126 → son **1203 geçti, 0 başarısız** |
| `flutter analyze` | temiz |

Kurallara uyum: her mantık değişikliğinde mevcut koda karşı KALAN test (yeni API gerektirenler ayrı grup, "önce" kanıtı geçici kopya ya da `git stash` ile); metin/null-guard/UI-yaşam-döngüsü değişikliklerinde "test: gerekmedi" gerekçesi commit mesajında. Mevcut testlerden yeni kontratla çelişenler güncellendi ve commit mesajında açıklandı (O26 → O6 testleri, K-1 → pushErrors testleri, D29 → kısa LMS fixture'ları, O4 → ayar PATCH testleri).

## 2. Madde tablosu

| ID | Durum | Commit | Test | Not |
|---|---|---|---|---|
| O1 (artık a) | DÜZELTİLDİ | `9789951` | evet | refresh token yokken prefs nedeni ezilmez |
| O1 (artık b) | DÜZELTİLDİ | `c7ba8ad` | evet (yeni API) | FCM kaydı yalnız başarılı POST'ta; oturum yokken istek yok |
| v15 şema (7a) | DÜZELTİLDİ | `c5ffa58` | evet (SchemaVerifier + veri dolu) | davranış değişikliği yok |
| K4 + O21 | DÜZELTİLDİ | `e328ee8` | evet | delta push, pull R1, aşı yankı güvencesi, ağ beklenmez |
| O4 | DÜZELTİLDİ | `beda831`, `6c70672` | evet | settingsDirty, değişen-alan PATCH, GET pull |
| K-1 banner | DÜZELTİLDİ | `3c7d94c` | evet | pushError kolonu, sayaç, geri al |
| O26 | DÜZELTİLDİ | `f93c849` | evet | satır içi ağ beklenmez |
| O14 | DÜZELTİLDİ | `82d3db2` | evet | periyodik dürtme sıfırlanmaz |
| O15 | DÜZELTİLDİ | `82d3db2` | evet | cancelBabyScheduled |
| O16 | DÜZELTİLDİ | `82d3db2` | hayır (platform) | otomatik exact-alarm isteği yok; KB-4 |
| O3 | DÜZELTİLDİ | `71bb441` | evet | son bilinen premium |
| O12 | DÜZELTİLDİ | `63302f2` | hayır (RC) | refresh hatası premium'u engellemez |
| O24 | DÜZELTİLDİ | `91a24d9` | evet | loşia doğum tarihi gerektirir |
| O23 | DÜZELTİLDİ | `ce4e912` | evet | expecting bebek kaldırılır; KB-5 |
| O25 | DÜZELTİLDİ | `f4274af` | evet (yeni API, widget) | CycleNotifSync |
| O22 | DÜZELTİLDİ | `0ef3a1b` | evet (widget) | doz çift-dokunma |
| O27 | DÜZELTİLDİ | `8afd140`, `0944af7` | evet (controller) | form doğrulaması + clamp |
| O37 | DÜZELTİLDİ | `8afd140` | hayır (tek alan) | createdBy korunur |
| O11 | DÜZELTİLDİ | `0944af7` | evet | syncAll kuyruk bekleme; bilinmeyen bağlantıda beklemez |
| O13 | DÜZELTİLDİ | `0944af7` | evet (yeni API) | currentDayProvider |
| O28 | DÜZELTİLDİ | `0944af7` | evet | hayalet dakika yok |
| O30 | DÜZELTİLDİ | `a641c37` | hayır (görsel) | rozet koşullu |
| O31 | DÜZELTİLDİ | `0a41509` | evet | EN belge |
| O32 | DÜZELTİLDİ | `c5a480c` | hayır (veri kopyalama) | export tam |
| O33 | DÜZELTİLDİ | `af00ad9` | evet (foto) | wipe + foto temizliği |
| O9 | DÜZELTİLDİ | `85abf47` | evet | 500'lük parçalar |
| O10 | DÜZELTİLDİ | `0b499bd` | evet | ağ önce |
| O17 | DÜZELTİLDİ (kısmi) | `c581b9e` | evet (saf) | ileri-tarih eşiği; NSE Swift testsiz; backend #10 |
| O18 | DÜZELTİLDİ | `6ced4b8` | hayır (widget ömrü) | dinleyici dispose |
| O29 | DÜZELTİLDİ (kısmi) | `1b2696d` | hayır (DST simüle edilemez) | adet motoru + TDT; KB-6 |
| O19 | KABUL | — | — | backend #3; K4 ile tik kaybolmuyor |
| D1 | DÜZELTİLDİ | `74fb3a4` | evet | retry gerçek hatası |
| D3 | DÜZELTİLDİ | `9329bc2` | evet | applied damga+içerik |
| D4 | DÜZELTİLDİ | `5e64089` | hayır | inactive = ön plan |
| D5 | DÜZELTİLDİ | `45ebe32` | hayır (Firebase) | tek uçuş |
| D6 | DÜZELTİLDİ | `c89a9f1` | hayır (RC) | dinleyici kuyruğu |
| D9 | DÜZELTİLDİ | `6544088` | hayır | userId bellekte |
| D10 | DÜZELTİLDİ | `ddba6ba` | hayır | _starting guard |
| D13 | DÜZELTİLDİ | `3d33843` | evet | tema korunur |
| D14 | DÜZELTİLDİ | `af26e1b` | hayır (mevcut test yeşil) | dil senkronu arka planda |
| D18 | DÜZELTİLDİ | `1b15d4e` | hayır | zaman tabanlı id |
| D22 | DÜZELTİLDİ | `159cae0` | hayır (görsel) | isPremiumProvider |
| D23 | DÜZELTİLDİ | `249bad3` | evet | süren kayıt guard |
| D24 | DÜZELTİLDİ | `474fd66` | hayır (null-guard) | mounted |
| D26 | DÜZELTİLDİ | `9654faf` | hayır | parse → cache |
| D28 | DÜZELTİLDİ | `1bc0884` | hayır (UI) | hata gösterimi |
| D29 | DÜZELTİLDİ | `9c29462` | evet | LMS 61 nokta |
| D30 | DÜZELTİLDİ (metin) | `0c6b985` | hayır | KB-8 |
| D31 | DÜZELTİLDİ | `ee559f9` | hayır (UI) | build-fazı setState yok; ≥22 hafta |
| D32 | DÜZELTİLDİ | `4f09bb2` | hayır (UI formu) | postpartum modu |
| D34 | DÜZELTİLDİ | `40a236c` | hayır | loşia rengi taşınmaz |
| D35 | KABUL | `ee202df` | — | damga tarihçe (J4 testi) |
| D36 | DÜZELTİLDİ | `edc03a0` | hayır (ekran state) | fetch epoch |
| D37 | DÜZELTİLDİ | `f4ad6c9` | hayır | oy guard |
| D38 | DÜZELTİLDİ | `01eb0a8` | hayır | null-guard |
| D39 | DÜZELTİLDİ | `3bc5ef0` | hayır | Consumer |
| D40 | DÜZELTİLDİ | `1e04ad0` | hayır | slug başına bir kez |
| D41 | DÜZELTİLDİ | `27dadef` | hayır | davet guard |
| D42 | DÜZELTİLDİ (kısmi) | `bae94fb` | hayır (UI) | errorBuilder; retrieveLostData KABUL |
| D2 D8 D11 D15 D17 D20 D21 D27 D44 | KABUL | — | — | gerekçeler BULGULAR §5 satır sonlarında |
| D16 D19 | DOĞRULANAMAZ | — | — | YAYIN-KONTROL §1 E |
| D7 D12 D25 D45 | GEÇERSİZ | — | — | backend my_role / O15 / O27 / metin zaten var |
| D43 | KARAR-BEKLEYEN | — | — | KB-9 (atlandı) |

Önceki koşularda kapananlar (hash'ler BULGULAR §2b): K1 K2 K3 K5 K6 K7 K8 K9 O1 O2 O5 O6 O7 O8 O20 O34 O35 O36, D33.

## 3. İNCELEME ÖNERİLİR — en riskli 10 değişiklik

1. **v15 migration + backfill (`c5ffa58`)** — gerçek cihazlarda `onUpgrade from<15` guard'ları (`from>=4`, `from>=7`) ve `UPDATE` backfill'leri; bakılacak: v13/v12'den gelen cihazlarda tablo yeniden kurulurken `addColumn` atlanıyor mu, `settings_dirty` yalnız sahip satırlarında mı. Migration testi var ama yalnız v14 anlık görüntüsünden.
2. **Sağlık delta push + pull R1 (`e328ee8`)** — pull artık işaret KALDIRMAYI da uygular; aşı yankı güvencesi dil uyuşmazlığında satırı sonsuza dek dirty bırakır (banner'a düşmez). Bakılacak: ilk v15 turunda aşıda "sunucu kazanır" (backfill yok) kararının saha etkisi; `_syncHealth` 403'ü readonly kapısına düşürüyor.
3. **K-1 geri al (`3c7d94c`)** — kullanıcı onayıyla yerel satır HARD DELETE (anı/anne/adet); bebekte silme yok (KB-1). Bakılacak: `discard` yolları, tombstone bebek + çocuk purge sırası, sayaç SQL'inin 6 tabloyu doğru kapsadığı.
4. **O4 ayar diff (`beda831`)** — `settingsBase` ile üst-düzey anahtar diff'i; sahip-only backfill sahibin bayat cihazının üyenin ayarını bir kez ezebilmesi (KARAR). Bakılacak: `pullSettings` yalnız bulut-uygun bebekte çağrılıyor mu (free sahibin ayarı sunucu varsayılanıyla ezilmesin).
5. **O26 adet yazımları (`f93c849`)** — satır içi PATCH kalktı; `baby` null'ı artık dirty-retry gövdesi her zaman taşır (eski "değişmeyen null baby'yi atlama" kuralı kalktı). Bakılacak: iki cihazda biri bebek bağlarken diğerinin bayat null'ı sunucuyu çözmesin (whole-row LWW).
6. **O9 sayfalı /sync (`85abf47`)** — her parça kendi cursor'ını ilerletiyor; parça arasında başarısızlık olursa kısmi gönderim (idempotent). Bakılacak: sunucu `since_cursor` ile her parçada delta döndürüyor; duplicate server_changes zararsız mı.
7. **O11 syncAll kuyruk (`0944af7`)** — `_pendingDone` Completer; `?? false` ile bağlantı durumu bilinmiyorken beslenme kaydı beklenmez. Bakılacak: ilk açılışta onlineProvider henüz çözülmeden kaydedip kapatan kullanıcı (local-first, sonraki tur gönderir).
8. **O14/O15/O16 bildirim (`82d3db2`)** — periyodik plan "bekleyen varsa kurma" (soğuk açılışta aralık değişikliği kaçabilir), `cancelBabyScheduled`, exact-alarm artık istenmiyor (inexact gecikme). Bakılacak: Android 12-13'te daha önce izin vermiş kullanıcılar etkilenmez; yeni kurulumda hatırlatıcı dakika hassasiyeti düşer (KB-4).
9. **Auth artıkları (`9789951`, `c7ba8ad`) + O10 (`0b499bd`)** — refresh token yokken callback yok; FCM kaydı mark-on-success; hesap silmede ağ önce. Bakılacak: hesap silme sırasında `unregister` 401 (yutulur) sonrası `deleteAccount` gerçekten çağrılıyor.
10. **O23/O24/O32/O33 veri etkili UI (`ce4e912`, `91a24d9`, `c5a480c`, `af00ad9`)** — expecting bebek silme, loşia kuralı, export yapısı, wipe'ta dizin silme. Bakılacak: wipe'ta `ApplicationSupport/babies` silinirken başka hesap kapsamı yok (tüm cihaz), export JSON tüketicileri yeni alanlara tahammül ediyor.

## 4. Kullanıcıya görünen davranış değişiklikleri
- Giriş ekranında zorunlu çıkış banner'ı (süre doldu / başka cihaz / genel).
- Ana sayfada "{n} değişiklik sunucuya gönderilemedi" banner'ı + geri al sayfası (onay diyaloğuyla yerel silme).
- Aşı/gelişim/diş işaretleme anında döner; başka üyenin kaldırdığı işaret bu cihazda da kalkar; farklı dildeki üyeler arası aşı işareti paylaşılmaz (dirty kalır).
- Aile ayarı (birim/sessiz saat) yeni cihaz/üyede sunucudan dolar.
- Adet kayıt/ayar yazımı anında döner (spinner yok); "Adet takibine dön" bekleyen bebeği kaldırır; loşia rengi yalnız loşia modunda; doğum sonrası sihirbaz postpartum modunu yazar; ilk adet loşia rengini taşımaz.
- Android 14+: açılışta Ayarlar'a zıplama yok; kesin alarm izni olmadan hatırlatıcılar ±dakika gecikebilir.
- Gelişim/diş 14 günlük dürtmeleri artık gerçekten çalar; bebek silinince bildirimleri gider.
- Satın alma sonrası sunucu hatası premium'u engellemez; çevrimdışı premium "Premium ol" görmez.
- Uyku formunda bitiş < başlangıç uyarısı; "Bugün" kartı gece yarısında sıfırlanır; duraklatılmış emzirme hayalet dakika eklemez.
- Anılar ekranındaki bulut rozeti yalnız bulut senkronlu bebekte; 5 ek dilde yasal belgeler İngilizce; "Verilerimi indir" tam; "Yerel verileri sil" fotoğrafları/bildirimleri de siler.
- İlaç planı ekranı notu "ailenle paylaşılır"; dil değişimi anında; topluluk oy/ davet çift dokunuş korumaları.

## 5. Çeviri anahtarları, backend talepleri, yan bulgular
- **Çeviri:** 22 anahtar, 6 dosya (`YAYIN-KONTROL.md §2`), api'de commit'lenmedi.
- **Yeni backend talepleri:** #8 `code: session_superseded`, #9 supersede'de cihaz kaydı, #10 family_activity `last_feed_ts` en yeni kayıt (`BACKEND-TALEPLERI.md`).
- **Yeni yan bulgular (düzeltilmedi):**
  - `O14` periyodik özel hatırlatıcının aralığı değiştirilip uygulama aynı süreçte sync etmeden kapatılırsa soğuk açılışta eski aralık korunur (bellek-içi `_intervalMin`); kalıcı aralık notu gerekir.
  - `_pushDirtySettings` (adet) dirty satırda `baby: null`'ı her zaman gönderir — whole-row LWW; bebek bağının başka cihazda kurulduğu anda bayat cihazın PATCH'i bağı çözebilir (KB adayı, TASARIM'a not düşülmedi).
  - Bg isolate'te I18n sözlüğü yüklü değil (D17): "Ertele" ve bg bildirim metinleri Türkçe; ayrı iş.
  - `FeedReminderCache`/`NotificationPrefs` wipe'ta korunuyor (tercih sayıldı); tam sıfırlama isteniyorsa `clearAll` eklenmeli.
  - Backend `/invitations/accept` `my_role` döndürüyor (D7 geçersiz) — sözleşmeye alan listesi yazılmalı.
  - `tasarim-promptlari/` izlenmeyen dizin çalışma ağacında duruyor (bu koşuya ait değil).

## 6. Testle doğrulanamayan, cihaz gerektiren değişiklikler
O16 (exact alarm), O12 (RC satın alma), O17 iOS NSE Swift, O18 (FCM dinleyici), D4/D5/D6 (yaşam döngüsü/Firebase/RC), D14 (dil senkronu UX), O29 DST (TR'de simüle edilemez), v15 migration gerçek cihaz. Adımlar `YAYIN-KONTROL.md §1`.

## 7. KARARLAR'la çelişen bulgu
Tasarım analizinde KARARLAR'ın güvensiz olduğunu gösteren bir bulgu çıkmadı; hepsi uygulandı. İki noktada güvenli varsayılan seçildi ve KARAR-BEKLEYEN'e yazıldı: sunucuda olmayan sahip bebekte "geri al" silmez (KB-1); gebelikten takibe dönüşte çapa korunur (KB-5). D35 (ttc damgası) mevcut yolculuk testinin belgelediği bilinçli tasarımla çeliştiği için uygulanmadı (KABUL).
