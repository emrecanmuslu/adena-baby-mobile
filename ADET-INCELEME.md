# ADET MODÜLÜ — ALAN (DOMAIN) İNCELEMESİ

Tarih: 2026-10-11 · Branch: `fix/adet-senkron` · Kapsam: **yalnız rapor, kod değişikliği YOK**.
Referans: görevdeki "REFERANS BİLGİ" listesi (A–F). Kaynak doğrulaması web üzerinden yapıldı; birincil sayfaya ulaşılamayan maddeler **"kaynak doğrulanmalı"** diye işaretlendi. Tıbbi içerik kararları için **uzman onayı** sütunu ayrıca var.

> Senaryo tablosu (§3) motor gerçekten çalıştırılarak üretildi (geçici test dosyası `test/engines/zz_adet_inceleme_senaryo_tmp_test.dart`, commit'lenmedi, silindi). Bugün = 2026-10-11, tüm tarihler bu güne göre.

---

## 0. Düzeltme turu durumu (2026-10-11)

Tüm bulgular ele alındı: **23 DÜZELTİLDİ, 1 bilinçli tercih (B3)**. Kararlar §6 uzman sorularına verilen yanıtlara (S1–S12) göre uygulandı; uzman onayı bekleyen metinler kök dizindeki `SAGLIK-METINLERI.md`'de TR+EN yan yana. Ek: S12 (erken kayıp ifadesi) `bb58275`; kalıcı senaryo testi `b86b503`.

| ID | Durum |
|---|---|
| A1 | DÜZELTİLDİ `8116ba6` |
| A2 | DÜZELTİLDİ `9782d32` |
| A3 | DÜZELTİLDİ `8d6dcb8` |
| A4 | DÜZELTİLDİ `51c1ed3` |
| A5 | DÜZELTİLDİ `9782d32` (+ 12. hafta kartı `61231d6`) |
| B1 | DÜZELTİLDİ `7a703b3` |
| B2 | DÜZELTİLDİ `998d35d` |
| B3 | BİLİNÇLİ TERCİH — pencere 7 gün kalır (ov−5…ov+1): ovülasyon tahmini takvime dayalı ve belirsiz; geniş pencere gebe kalmak isteyen için kaçırma riskini, diğerleri için yanlış güvence riskini azaltır (S9) |
| B4 | DÜZELTİLDİ `0d0ae85` |
| B5 | DÜZELTİLDİ `8d6dcb8` |
| C1 | DÜZELTİLDİ `61231d6` |
| C2 | DÜZELTİLDİ `2d46cec` |
| C3 | DÜZELTİLDİ `8ee2dd9` |
| C4 | DÜZELTİLDİ `94fec3d` |
| C5 | DÜZELTİLDİ `8116ba6` (+ bildirim `8ee2dd9`) |
| C6 | DÜZELTİLDİ `51c1ed3` |
| C7 | DÜZELTİLDİ `9ab919f` |
| C8 | DÜZELTİLDİ `9782d32` |
| D1 | DÜZELTİLDİ `720c75f` |
| D2 | DÜZELTİLDİ (çeviri JSON, api — commit'lenmedi; regresyon testi `a63519c`) |
| D3 | DÜZELTİLDİ `9782d32` |
| D4 | DÜZELTİLDİ `e2e6fe1` |
| D5 | DÜZELTİLDİ `69f9287` |
| B6 | DÜZELTİLDİ `29fcc79` |
| S12 (K1 metni) | DÜZELTİLDİ `bb58275` |

Uygulama notları (karar yorumları):
- **S1/A3:** Doğum+0..56 gün içindeki kanama kaydı, kullanıcı açıkça "ilk adetim" demedikçe çapa kurmaz. 43–56. günde kayıt sayfası sorar; ilk 42 günde arayüz "ilk adetim" seçeneği sunmaz (loşia sayılır). Düzenleme takvimi açık adet işaretlemesidir ama ilk 42 günü hiçbir zaman ilk adet saymaz.
- **S7/B1:** Uç değer kuralı "diğer döngülerin medyanı"yla uygulanır (kendisi hariç) — yalnız iki döngü olduğunda da çalışsın diye. Medyan döngü uzunluğuna uygulanır; adet süresi ortalaması değişmedi. "Döngüm uzundu" cevabı cihazda (hesap başına) saklanır, buluta senkronlanmaz (sunucu şemasında alan yok).
- **S8/C1:** Düzenli döngüde ≥90 gün kuralına ek, temkinli olarak düzensiz döngüde ≥180 gün eşiği eklendi.
- **C8:** Sunucu `breastfeeding` alanı seçenekli olduğundan "Söylemek istemiyorum" yerine soru zorunlu yapıldı.

## 1. Özet

| Önem | Adet | ID'ler |
|---|---|---|
| **SAĞLIK RİSKİ** | 5 | A1, A2, A3, A4, A5 |
| **YANLIŞ BİLGİ** | 6 | B1, B2, B3, B4, B5, B6 (§4 sonu notu) |
| **YANILTICI / EKSİK UYARI** | 8 | C1–C8 |
| **UX / DİL** | 5 | D1–D5 |
| Toplam | **24** | |

En kritik 5:
1. **A1** — Takvim ve TTC kartı her gün için "Gebe kalma olasılığı: Düşük" gösteriyor; uygulamanın hiçbir yerinde "bu bir doğum kontrol yöntemi değildir" uyarısı yok → "güvenli gün" çağrışımı.
2. **A2 / A5** — LAM (emzirme ile korunma) metinleri üç koşulu (ilk 6 ay + tam emzirme + adet dönmemiş) belirtmeden "~%2 risk" / "LAM geçerli olabilir" diyor; emzirmeyen lohusaya bile LAM kartı gösteriliyor, oysa onun için ovülasyon 3–4. haftada dönebilir.
3. **A3** — Loşia penceresinde (doğum +0–42 gün) kullanıcı "Kanama kaydet"te akış seçip loşia rengi seçmezse kayıt **adet** sayılıyor → çapa kurulup döngü tahmini ve doğurgan pencere başlıyor (senaryo J6: doğum +25. günde "gün 6/28", ovülasyon 20.10).
4. **B1** — Unutulmuş kayıt (56 günlük sahte döngü) ortalamaya olduğu gibi giriyor; ayıklama/soru yok. Senaryo F3: gerçek döngü 28 gün ve kullanıcı 1 gün gecikmişken ekran "Yumurtlama · Doğurgan pencere" diyor, "adetin yaklaşıyor" bildirimi yanlış güne kuruluyor.
5. **A4 / C1** — Kırmızı bayrak diyaloğu (saatte 1+ ped, limondan büyük pıhtı, ateş) "bir sağlık profesyoneline danışmanı öneririz" diyor, aciliyet yok; 38°C eşiği, baş dönmesi/bayılma, azalan kanamanın yeniden parlak kırmızıya dönmesi listede yok. Gecikmede eşik yok: 1. günden "Gün gecikti", 12 gün gecikmede de aynı metin, 3 ay adet görmemede hekim önerisi yok.

---

## 2. Envanter (2.1)

### 2.1 Modlar ve geçişler
| Mod | Nerede | Giriş / çıkış |
|---|---|---|
| `tracking` (adet takibi) | `lib/models/cycle.dart:17-27` (`CycleLifecycleMode`), `lib/features/cycle/cycle_lifecycle.dart:65-85` (`setCycleLifecycleMode`) | Ayarlar/ana ekran "Hedefim" seçici (`cycle_lifecycle.dart:89-202`); postpartum/loss'tan **otomatik** dönüş: çapa null→dolu olunca (`lib/data/cycle_repository.dart:216-228`) |
| `ttc` | aynı; `ttcStartedAt` damgası `cycle_lifecycle.dart:76-81` | Seçici; `cycle_shell.dart:119` "Gebe kaldım" kısayolu |
| `pregnant` | `cycle_pregnancy_bridge.dart:53-76` (`ensureExpectingBabyForPregnancy`: LMP'den `Baby(status=expecting, dueDate=LMP+280)` oluşturur), `startCyclePregnancy :93-219` | Giriş: "Hamileyim"; çıkış TEK kapı `cycle_loss.dart:69-125` (`showCycleLossOrEnd`: doğum → `/born-flow`, kayıp → `_confirmLoss`, takibe dön → `returnToTrackingFromPregnancy :56-65`, çapa sıfırlanır) |
| `postpartum` | kurulum sihirbazı `cycle_setup_screen.dart:78-90` (adet dönmediyse `postpartum` + `predictionsHidden=true`; emzirme cevaplanmadıysa **`exclusive` varsayılır** :80) | Çıkış yalnız ilk adet kaydıyla otomatik (`cycle_repository.dart:341-357`, `:216-228`); seçici salt-okunur (`cycle_lifecycle.dart:102-114`) |
| `loss` | `cycle_loss.dart:27-40` (`recordCycleLoss`: `predictions_hidden=true`, `last_loss_date`, çapa null, bebek bağı null) | Çıkış: "Takibe hazırım" (`:43-48`) ya da ilk adet kaydı (otomatik) |
| Motor modu (`CycleMode.lochia/waiting/active`) | `cycle_engine.dart:4-8`, tayin `:147-163` | `periodReturned`/`predictionsHidden` → loşia penceresi (doğum 0–42 gün; loşia kaydı varsa 60 gün, O24) → `lochia`; aksi `waiting`; çapa dolu → `active` |

### 2.2 Hesaplamalar (tümü `lib/features/cycle/cycle_engine.dart`, saf `computeStatus`)
| Hesap | Satır | Formül |
|---|---|---|
| Döngü başlangıçları | `:124-134`, `:169-174` | adet günü olup önceki gün adet olmayan günler; çapadan (`firstPeriodDate`) önceki kayıtlar yok sayılır |
| `isPeriod` | `lib/models/cycle.dart:243-247` | `lochiaColor == null && flow ∉ {none, spotting}` |
| Döngü uzunluğu ortalaması | `:211-226` | akıllı tahmin AÇIK: son `learningWindow` (vars. 6) tamamlanmış döngünün **aritmetik ortalaması, yuvarlanır** — uç değer ayıklaması YOK; KAPALI/ölçüm yok: manuel 21–40 yoksa **28** |
| Adet süresi | `:230-241` | tamamlanmış döngülerin adet günü ortalaması; manuel 2–10 yoksa **5**; süren adet ortalamaya girmez |
| Luteal | `:244-247` | ayar 10–16, yoksa **14** |
| Sonraki adet | `:251` | `sonStart + avgLen` |
| Ovülasyon | `:255` | `sonrakiAdet − luteal` (28 gün döngüde **15. gün**, 24'te 11., 35'te 22.; bkz. B-notu) |
| Doğurgan pencere | `:256-257` | `ov−5 … ov+1` (**7 gün**); yaklaşan pencere `:261-265` |
| Gebe kalma olasılığı | `:105-120` | ov = çok yüksek; ov−2/−1 = yüksek; pencerenin kalanı (ov−5..−3 ve **ov+1**) = orta; dışı = düşük |
| Faz | `:268-277` | gün ≤ adet süresi → menstrual; = ov → ovulation; < ov → follicular; > → luteal |
| "Gecikti" | `cycle_today_screen.dart:244-250` | `daysToNextPeriod < 0` → 1. günden itibaren "Gün gecikti", eşik yok |
| Düşük güven | `:294` | yalnız **sayı**: tamamlanmış döngü < 3 → `lowConfidence`; varyans bakılmaz |
| Düzenlilik (istatistik) | `cycle_stats_screen.dart:162-175` | son 6 döngüde ortalamaya ±3 gün; "Düzenli seyir" ≤1 sapma |
| Gebelik haftası / TDT | `cycle_pregnancy_bridge.dart:32-45` | `(bugün−SAT)` gün; `>300` → null; TDT = SAT+280 (Naegele). Ana modül `lib/core/age.dart:31-35`, `lib/features/home/expecting_home.dart:38-41` TDT'den geri sayar (TDT−280). TTC "bugün gebe kalırsan" = bugün+266 (`cycle_today_screen.dart:475`) |
| Loşia günü | `cycle_engine.dart:148-160` | doğumdan bu yana gün; pencere 42 gün (60 loşia kaydıyla) |
| Kayıp sonrası | `cycle_engine.dart:147-163` | hesap yok (`waiting`); `afterLatestReset` (`cycle_anchor.dart:24-32`) kayıp/doğum günü ve öncesini adet saymaz |

### 2.3 Kullanıcıya gösterilen metinler (seçki; tam liste kod satırlarında)
| Metin (TR) | EN | Koşul | Dosya:satır |
|---|---|---|---|
| "Gün gecikti" / "{d} bekleniyordu" / mini kart "Test · Gerekirse" | "Days late" / "Expected {d}" / "Test · If needed" | d2n<0 | `cycle_today_screen.dart:247-248, 375-380` |
| Gecikme notu (emziren / TTC / genel) | "Delays are very common while breastfeeding…" / "A late period can be a sign of pregnancy — consider taking a test…" / "Delays can also happen with stress…" | state=late | `:405-415` |
| "Yumurtlama · Doğurgan pencere" halkası; kart "Yüksek doğurganlık — Bugün gebelik şansı en yüksek dönemde" (+ "~tahmini" pili) | "High fertility — Today is in the highest-chance window for pregnancy" | faz=ovulation, **herkes** (TTC şart değil) | `:258-265, 334-372` |
| "Emziriyorsan ovülasyon ilk adetten önce dönebilir — korunma gerekiyorsa doktoruna danış." | "If you're breastfeeding, ovulation can return before your first period — talk to your doctor if you need contraception." | yalnız `_bfActive` (doğum var + emzirme≠none) | `:367-368, 432-439` |
| "~ Tahmini · değişebilir" rozeti | "Estimated · may vary" | yalnız `lowConfidence` (<3 döngü) | `:312-313`, `cycle_widgets.dart:176-199` |
| TTC: "Bugün olasılık: Çok yüksek/Yüksek/Orta/Düşük", "Bugün gebe kalırsan tahmini doğum tarihi: {d}…" | "Chance of getting pregnant… / If you conceive today, the estimated due date is {d}…" | `_ttc` | `:458-507` |
| Gebelik: "Hafta {w}" + "Tahmini doğum {d}" + "Bu tarih son adetinden hesaplanır…" | "Due date: {d}" (**"tahmini" EN'de düşmüş**) | lifecycle=pregnant | `:511-563`, `cycle_pregnancy_bridge.dart:118-150` |
| Loşia: "Lohusalık · gün / İyileşme · 0–6 hafta", "Loşia rengi · tahmin yok", "Akış zamanla azalıp açılıyorsa loşia; durup koyulaşıp 4–7 gün sürerse muhtemelen ilk adettir.", "Emziriyorsan adet gekebilir (LAM)…" | "Postpartum · day / Recovery · 0–6 weeks"; "If the flow fades… it's lochia; if it stops, then turns darker and lasts 4–7 days, it's likely your first period." | mode=lochia, **emzirme durumu bakılmaz** | `:582-632` |
| Bekleme: "Emzirme döneminde adetin geç dönmesi tamamen normaldir…", LAM kartı "Düzenli emzirme adeti geciktirir; ancak ovülasyon adetten önce döner — ilk adeti görmeden gebe kalınabilir (~%2 risk)." | "…you can conceive before your first period (~2% risk)." | `_hadBirth` (**emzirmeyen de görür**) | `:651-680` |
| Kurulum: "Sadece anne sütü — LAM geçerli olabilir" / "Emzirmiyorum — Adet daha erken dönebilir"; "Doğumdan sonraki ilk ~6 hafta kanama loşiadır, adet değildir." | "Breast milk only — LAM may apply" | adım 2 / adım 1 | `cycle_setup_screen.dart:247-249, 233` |
| Bilgi rozetleri `CycleInfo.lam` ("~%2 başarısızlık riski… ovülasyon adetten ÖNCE döner"), `fertileWindow` ("~6 günlük dönem"), `estimate`, `regularity`, `lochiaVsPeriod` | var | info butonları | `cycle_widgets.dart:141-174` |
| Kırmızı bayrak chip'leri: "Saatte 1+ ped ıslatma", "Büyük pıhtı (limondan büyük)", "Kötü kokulu akıntı + ateş", "Şiddetli karın/kasık ağrısı"; diyalog "Dikkat… Bir sağlık profesyoneline danışmanı öneririz. Bu bir tanı değil — yalnızca yönlendirmedir." | "Soaking 1+ pad per hour… We recommend consulting a health professional." | her modda, kayıt sırasında bayrak seçilince | `cycle_widgets.dart:113-118, 203-322`; tetik `cycle_entry_sheet.dart:108-112, 373-378` |
| Kayıp: "Kendine zaman tanı", "Kayıptan sonra ovülasyon genelde ~2 hafta içinde dönebilir; ilk adet çoğunlukla 4–6 hafta sonra gelir.", "hCG düşene kadar ovülasyon testleri yanlış pozitif…", "İlk adetin gelmeden de gebe kalabilirsin…" | var | lifecycle=loss | `cycle_loss.dart:286-318` |
| Takvim gün paneli: "Gebe kalma olasılığı: Düşük/…", "Yumurtlama günü — en yüksek doğurganlık", "Doğurgan gün", "Tahmini adet günü" | "Chance of getting pregnant: Low…", "Ovulation day — peak fertility", "Fertile day" | mode=active, **herkes** | `cycle_calendar_screen.dart:696, 770-780, 830-838` |
| İstatistik: "Düzenli seyir / Değişken seyir" + pil "Postpartum normal / Değişkenlik normal" (**koşulsuz**) | "Regular pattern / Variable pattern / Normal postpartum / Variation is normal" | active | `cycle_stats_screen.dart:170-174` |
| Ayarlar: "LAM / doğurganlık uyarıları" anahtarı | — | kaydedilir, **hiçbir yerde okunmaz** | `cycle_settings_screen.dart:172-193`; tek okuyucu yok (grep) |
| İçerik yazıları (sunucu seed): "Emzirme ve doğurganlık (LAM nedir)" **3 koşulu doğru veriyor**; "Ne zaman doktora başvurmalı" baş dönmesi/çarpıntı dahil | var | "Daha fazla" linki `cycle_today_screen.dart:726` | `../api/apps/content/management/commands/seed_cycle_content.py:62-79, 99-115` |

### 2.4 Bildirimler (`lib/core/notification_service.dart:957-1006`, tetik `lib/features/cycle/cycle_notif_sync.dart`)
| Bildirim | Zaman | Metin | Koşul |
|---|---|---|---|
| Adet yaklaşıyor (id 600000) | `nextPeriod − 3 gün`, 09:00 | "Adetin yaklaşıyor 🌸" | reminders.period.on; nextPeriod ≠ null (postpartum/loss'ta null → kurulmaz) |
| Doğurgan pencere (600001) | `upcomingFertileStart`, 09:00 | "Doğurganlık pencereniz başlıyor" | reminders.fertile.on — TTC şart değil |
| PMS (600002) | `nextPeriod − 5 gün`, 09:00 | "PMS dönemi yaklaşıyor" | reminders.pms.on |
| Günlük kayıt (600003) | ayar saati (vars. 21:00) | "Bugünü kaydetmeyi unutma 🌙" | reminders.log.on |
Varsayılan: tüm hatırlatıcılar kapalı (`reminders = {}`). Bildirimler motor tahminine bağlı → B1'deki sahte döngü bildirimi yanlış güne kurar.

---

## 3. Senaryo tablosu (2.2) — motor çıktısı
Bugün = 11.10.2026. "Uygulama" sütunu `computeStatus` + Bugün ekranı durum seçimi (`cycle_today_screen.dart:244-293`) ile üretildi.

| # | Girdi | Uygulama çıktısı | Referansa göre beklenen | Uyumlu? | Yeni çıktı (düzeltme sonrası, `test/engines/adet_senaryo_test.dart`) |
|---|---|---|---|---|---|
| A1 | 28g düzenli (4 başlangıç), gün 21 | sonraki 19.10 · ov 05.10 · pencere 30.09–06.10 · "Luteal · Sonraki ~8 gün" · düşük güven **yok** | sonraki 19.10 · ov ≈ 05–06.10 · pencere 6 gün (30.09–05.10) | ✅ (pencere +1 gün, B3) | Değişmedi (luteal, sonraki 19.10, ov 05.10). Halka "Tahmini…" etiketli, TTC dışında olasılık yok |
| A2 | 28g, gün 15 | **"Yumurtlama · Doğurgan pencere"**, şans çok yüksek | ov ≈ 14–15. gün (NHS: sonraki adetten 10–16 gün önce) | ✅ | Değişmedi. Halka "TAHMİNİ YUMURTLAMA"; TTC dışında kart "Doğurgan pencere (tahmini)" + korunma notu |
| A3 | 28g, gün 10 | "Doğurganlık", pencere 11.10–17.10, şans orta | ov−5 → pencerenin ilk günü | ✅ | Değişmedi. TTC dışında "Doğurgan pencere (tahmini) içindesin." + korunma notu |
| A4 | 28g, 1 gün gecikme | **"1 Gün gecikti · 10.10 bekleniyordu"** + "Test · Gerekirse" | FIGO: ±4 gün normal oynama; 1. günde "gecikti" dili erken; test önerisi ilk gün makul (NHS) | ⚠️ C1 | "1 · Gün geçti · Beklenen tarih (tahmini): 10 Eki" + "Beklenen tarihten 1 gün geçti." + bağlam notu |
| A5 | 28g, 12 gün gecikme | aynı metin, "12 Gün gecikti", test "Gerekirse" | test önerisi güçlenmeli; gecikme uzadıkça hekim önerisi | ⚠️ C1 | "12 · Gün geçti" + "Gebelik testi yapmanı öneririz; negatifse birkaç gün sonra tekrarlayabilirsin." · Test: Önerilir |
| B1 | 24g, gün 21 | sonraki 15.10 (4 gün) · ov 01.10 (11. gün) · "4 Gün kaldı" | ov ≈ 10–11. gün | ✅ | Değişmedi (geri sayım "Sonraki adet (tahmini) · 15 Ekim") |
| B2 | 24g, gün 10 | "Doğurganlık", şans **yüksek** (ov 12.10) | ov−1 → yüksek | ✅ | Değişmedi (TTC dışında nötr pencere metni) |
| C1 | 35g, gün 21 | "Doğurganlık", ov 12.10 (22. gün), pencere 07–13.10 | ov ≈ 21–22. gün | ✅ | Değişmedi |
| C2 | 35g, gün 14 | "Folliküler · Sonraki ~22 gün", şans düşük | 14. gün 35g döngüde ovülasyon değil | ✅ (klasik "14. gün" hatası yapılmıyor) | Değişmedi |
| D1 | düzensiz 26/33/29/40, gün 21 | ort **32** · sonraki 23.10 · ov 09.10 · **tek tarih**, düşük güven rozeti **YOK**, şans düşük | FIGO: fark 14 gün → düzensiz; aralık + "tahmin" dili + düşük güven | ❌ B2, C3 | **medyan 31**, sonraki 22.10, **düşük güven + düzensiz**, "Sonraki adet tahmini: 17–31 Ekim" |
| D2 | düzensiz, gün 35 | "2 Gün gecikti" | 40 günlük döngüsü olan kullanıcıya gecikme dili erken | ❌ B2 | medyan 31, "3 · Gün geçti" (beklenen 08.10), düşük güven + aralık 03.10–17.10 |
| E1 | tek kayıt, gün 21 | 28 varsayımı · rozet "Tahmini · değişebilir" VAR | tek döngüden tahmin yapılmamalı ya da açıkça "varsayılan 28" denmeli | ⚠️ C3 | Değişmedi (28 varsayımı, "Tahmini · değişebilir") |
| E2 | tek kayıt + beklenen 30 ayarı | 30 kullanılır | ✅ | ✅ | Değişmedi |
| F1 | bir ay unutulmuş (28, **56**), gün 21 | ort **42** · sonraki 02.11 · "Folliküler · Sonraki ~22 gün" | 56 gün uç değer ayıklanmalı/sorulmalı → ort 28, sonraki 19.10 | ❌ B1 | **56 dışlandı → medyan 28**, sonraki 19.10, düşük güven, soru kartı "Bu dönemde bir adet kaydını unutmuş olabilir misin?"; bildirim 16.10 |
| F2 | 6 döngü (28×5 + 56), gün 21 | ort 33 · "Doğurganlık" (pencere 05–11.10) | ort 28; gün 21 = luteal | ❌ B1 | **medyan 28**, gün 21 luteal, soru kartı |
| F3 | unutulan ay, **gün 29** (gerçek: 1 gün gecikme) | **"Yumurtlama · Doğurgan pencere", şans çok yüksek**; sonraki 25.10 | "1 gün gecikti" | ❌ B1 (en kötü örnek) | **medyan 28**, d2n=0 ("0 gün kaldı"), artık "Yumurtlama" değil; soru kartı |
| G1 | son adet **11 gün**, gün 12 | adet ort 5 (süren adet ortalamaya girmez) · "Doğurganlık" · **hiç uyarı yok** | 8 günü aşan kanama → hekim önerisi (FIGO >8 gün "uzamış") | ❌ C2 | Aynı tahmin + **"Adetin 8 günden uzun sürüyor — hekimine danışmanı öneririz."** |
| G2 | her adet 10 gün | adet ort 10 · uyarı yok | aynı | ❌ C2 | Aynı + **uzun adet uyarısı** (ortalama 10 > 8) |
| H1 | TTC 28g, gün 13 (ov−2) | "Bugün olasılık: Yüksek", "Yumurtlama 2 gün sonra", TDT kartı (bugün+266) | Wilcox: ov−2 en yüksek grup | ✅ | Aynı + TTC notları: korunma notu, 1–2 günde bir ilişki, LH/mukus, folik asit |
| H2 | TTC 28g, gün 15 (ov) | "Çok yüksek", "Yumurtlama Bugün" | ✅ | ✅ | Aynı + TTC notları |
| H3 | TTC 32g, gün 17 (ov−2) | ov 13.10 (19. gün), "Yüksek" | ov ≈ 18–19. gün | ✅ | Aynı + TTC notları |
| H4 | TTC 32g, gün 21 | "Luteal", şans düşük, yaklaşan pencere sonraki döngü | ✅ | ✅ (12/6 ay hekim önerisi ve folik asit yok → C4) | Aynı + TTC notları (≥6/12 ay sonra hekim kartı) |
| I1 | SAT 70 gün önce | **10h 0g · TDT 09.05.2027** | 10h 0g · SAT+280 | ✅ | Değişmedi; ana modül TDT'si varsa hafta ondan (B6) |
| I2 | SAT 7 gün önce | 1h 0g · TDT 11.07.2027 | ✅ | ✅ | Değişmedi |
| I3 | SAT 280 gün önce | 40h 0g · TDT bugün | ✅ | ✅ | Değişmedi |
| I4 | SAT 300 gün önce | 42h 6g | ✅ (sınır) | ✅ | Değişmedi |
| I5 | SAT 301 gün önce | null → "Gebelik takibi" (veri yok) | makul | ✅ | Değişmedi |
| J1 | doğum +3 gün, tam emziren | **lochia**, "Lohusalık · gün 3", renk chip'leri, tahmin yok | loşia rubra; tahmin yok | ✅ | lochia; LAM kartı **üç koşul** (öneri değil) + "İlk adetini görmeden de gebe kalabilirsin…"; acil/aynı gün bilgi notu |
| J2 | doğum +21 gün | lochia gün 21, "Emziriyorsan adet gecikebilir (LAM)…" | loşia alba; LAM koşulları eksik | ⚠️ A2 | lochia; "Loşia genellikle 4–6 hafta sürer, 8 haftaya uzayabilir…"; LAM üç koşul |
| J3 | doğum +43 gün, loşia kaydı yok | **waiting** ("Henüz adet dönmedi"); loşia rengi artık **girilemez** (entry sheet `lochiaMode=false`) | loşia 8 haftaya uzayabilir; kayıt imkânı sürmeli | ❌ B5, A3 | waiting; karışık → "Emzirme artık tek başına korunma sağlamaz"; **loşia rengi 56. güne kadar girilebilir** |
| J4 | doğum +70 gün (10 hf), **emzirmiyor** | waiting; **"Emzirme döneminde adetin geç dönmesi tamamen normaldir"** + LAM kartı "~%2 risk" | emzirmeyende adet 5–8 hf'da döner (NHS: bottle feeding 5–6 hf), ovülasyon ≥3 hf'da; "adet dönmedi" → hekime danış; LAM alakasız | ❌ A5 | waiting; **"Emzirmiyorsan adetin genellikle 6–8 hafta içinde döner; ovülasyon 3–4. haftada olabilir…"**, LAM yok; 12. haftada (J4b +85) hekim kartı |
| J5 | doğum +150 gün (5 ay), tam emziren | waiting; aynı LAM kartı | LAM için 6. aya kadar + tam emzirme + adet yok → koşullar söylenmeli; 6. ay sonrası koşul bozulur uyarısı yok | ⚠️ A2 | waiting; LAM üç koşul (5. ay); 6. aydan sonra "artık korunma sağlamaz" |
| J6 | doğum +25, "Kanama kaydet"te akış seçildi, **loşia rengi seçilmedi** → çapa | **active**: "gün 6/28", sonraki 03.11, ov 20.10, pencere 15–21.10 | loşia bitmeden "ilk adet" kurulmamalı ya da sorulmalı | ❌ A3 | **Çapa kurulmaz** (doğum+0..42 loşia); 43–56. gün "loşia mı, ilk adet mi?" sorusu |
| J7 | doğum +70, emzirmiyor, ilk adet T−10 | active, gün 11 "Doğurganlık", rozet var | ilk döngüler düzensiz → düşük güven ✅; pencere gösterimi tartışmalı | ⚠️ | Değişmedi (ilk döngü, düşük güven) |
| K1 | kayıp +14 gün | waiting + kayıp metinleri ("ovülasyon ~2 hafta içinde dönebilir", hCG uyarısı, "ilk adetin gelmeden gebe kalabilirsin") | Tommy's/Miscarriage Assoc.: ilk 13 hf kayıplarda 2 hf içinde ovülasyon olabilir, adet 4–6(8) hf | ✅ (dil hassas, "gecikti" yok, "bebeğin" yok) | waiting; "Erken kayıplarda ovülasyon genellikle ~2 hafta içinde dönebilir…" |
| K2 | kayıp +42 gün | aynı | ✅ | ✅ (6 hf'da adet yoksa yönlendirme yok → C1) | waiting; 8. haftadan sonra (K2b +57) "Uzun süredir adet görmedin — hekimine danışmanı öneririz." |
| K3 | kayıp +42, "takibe dön" | waiting, "Son adetinin ilk gününü kaydettiğinde…" | ✅ | ✅ | Değişmedi (+8 hafta kuralı aynı) |
| K4 | kayıp +42, ilk adet T−3 | active gün 4, rozet var, sonraki 05.11 | ✅ düşük güven | ✅ | Değişmedi |
| L1 | 28g, luteal ayarı 12 | ov 13.10 (16. gün), pencere 08–14.10 | ✅ formül | ✅ | Değişmedi |
| L2 | akıllı tahmin KAPALI, beklenen 28, gerçek 35, gün 30 | "1 Gün gecikti" | kullanıcı tercihi; ama ölçüm 35 ise uyarı verilebilir | ⚠️ | "1 · Gün geçti" (gecikti dili yok) |

---

## 4. Bulgular

| ID | Önem | dosya:satır | Mevcut davranış | Doğrusu (kaynak) | Önerilen düzeltme | Uzman onayı | Durum |
|---|---|---|---|---|---|---|---|
| **A1** | SAĞLIK RİSKİ | `cycle_calendar_screen.dart:696, 830-838`; `cycle_today_screen.dart:459-482`; grep: "doğum kontrol/korunma yöntemi/kontrasep/güvenli gün" → **0 sonuç** | Takvimde her gün için "Gebe kalma olasılığı: Düşük" (TTC şart değil); TTC kartında "Bugün olasılık: Düşük". Hiçbir yerde "uygulama doğum kontrol yöntemi değildir" uyarısı yok. | Takvime dayalı tahmin korunma için güvenilir değildir (NHS "fertility in the menstrual cycle": ovülasyon sonraki adetten 10–16 gün önce, sperm 7 güne kadar yaşar). Wilcox 1995: gebelik pencerede yoğunlaşır ama pencere tahmini kesin değil. | "Düşük" etiketini yalnız TTC modunda göster; takvim gün panelinde olasılık satırının altına kalıcı not: "Bu olasılık bir tahmindir; gebelikten korunma için kullanılamaz." Ayarlar/kurulumda tek seferlik aynı uyarı. | Hayır (ürün kararı), metin için evet | DÜZELTİLDİ `8116ba6` |
| **A2** | SAĞLIK RİSKİ | `cycle_setup_screen.dart:247` ("LAM geçerli olabilir"); `cycle_today_screen.dart:627-628, 673-674` ("~%2 risk"); `cycle_widgets.dart:146-149` (`CycleInfo.lam`) | LAM üç koşuldan söz etmeden "~%2 risk / başarısızlık" diyor; 6. aydan sonra ya da karışık beslenmede uyarı değişmiyor (J5). İçerik yazısı (`seed_cycle_content.py:69-79`) koşulları doğru veriyor ama ekran metinleri vermiyor. | LAM yalnız ÜÇ koşul birlikte sağlanırsa ~%98: doğumdan sonraki ilk 6 ay + tam/tama yakın emzirme (4–6 saatten uzun ara yok) + adet dönmemiş; biri bozulursa geçersiz (CDC MEC Ek G; WHO/JHU Family Planning Handbook). | Kurulum alt metnini "LAM geçerli olabilir" yerine "Adet daha geç dönebilir"e çevir; LAM kartında üç koşulu listele; bebek 6 ayı geçince ya da breastfeeding=mixed olunca kartı "LAM artık geçerli değil; korunma için doktoruna danış"a çevir. | Evet (metin) | DÜZELTİLDİ `9782d32` |
| **A3** | SAĞLIK RİSKİ | `cycle_entry_sheet.dart:247-266` (loşia modunda akış ve renk ayrı, ikisi de isteğe bağlı); `lib/models/cycle.dart:243-247`; `cycle_repository.dart:341-345`; `cycle_engine.dart:147` (çapa kontrolü loşia penceresinden önce) | Loşia penceresinde "Kanama kaydet"te yalnız akış seçilirse kayıt adet sayılır → çapa kurulur, mod `tracking`e döner, doğurgan pencere/ovülasyon tahmini başlar (J6). "İlk adet" sorusu sorulmaz. | Loşia adet değildir, 4–6 hafta (bazen 8) sürer (NHS "your body after the birth"); loşia bitmeden ilk-adet çapası kurulmamalı ya da kullanıcıya ayrım sorulmalı (görev referansı D). | Loşia modunda akış seçildiğinde renk seçimi zorunlu olsun **ya da** kaydetmeden önce "Bu loşia mı, ilk adetin mi?" onayı; ilk 6 haftada otomatik çapa kurulmasın (`afterLatestReset`e "doğum+42 gün" eşiği). | Evet (eşik günü) | DÜZELTİLDİ `8d6dcb8` |
| **A4** | SAĞLIK RİSKİ | `cycle_widgets.dart:113-118` (bayrak listesi), `:297, :311` (diyalog metni); `:106` (baş dönmesi normal belirti listesinde) | Kırmızı bayrak diyaloğu: "Bir sağlık profesyoneline danışmanı öneririz" — aciliyet yok. Listede 38°C eşiği, baş dönmesi/bayılma, azalan kanamanın yeniden parlak kırmızı/yoğun olması yok. | Saatte bir pedi dolduran kanama, büyük pıhtı, ani/çok yoğun kanama + baygınlık/çarpıntı = postpartum kanama belirtisi, **hemen** bildir (NHS: "tell your midwife, health visitor or GP straight away"); ateş + hassas karın = enfeksiyon. İçerik yazısı baş dönmesi/çarpıntıyı zaten listeliyor (`seed_cycle_content.py:111`). | Bayrak listesine "38°C ve üzeri ateş", "baş dönmesi/bayılma hissi", "azalan kanamanın yeniden parlak kırmızı ve yoğun olması"nı ekle; diyalog metnini "Bu belirtilerde beklemeden sağlık kuruluşuna başvur / acil durumda 112" yap; saatte 1+ ped ve bayılma için ayrı "acil" vurgusu. | Evet (acil eşikleri) | DÜZELTİLDİ `51c1ed3` |
| **A5** | SAĞLIK RİSKİ | `cycle_today_screen.dart:151-153` (`_hadBirth`/`_bfActive`), `:651-680` (bekleme ekranı yalnız `_hadBirth`), `:367, 432-439` (uyarı yalnız `_bfActive`) | Emzirmeyen lohusa (J4) bekleme ekranında "Emzirme döneminde adetin geç dönmesi tamamen normaldir" + LAM kartı görüyor; "ovülasyon adetten önce döner, korunma gerekiyorsa doktoruna danış" uyarısı ise **yalnız emzirene** gösteriliyor — tam tersi olmalı. | Emzirmeyende ilk adet 5–8 hafta civarı, ovülasyon daha erken; "doğumdan 3 hafta sonra, emzirseniz bile gebe kalabilirsiniz; 21 gün içinde korunmaya başlayın" (NHS). | Bekleme ekranında `breastfeeding == none` için ayrı metin: "Emzirmiyorsan adetin genellikle 6–8 hafta içinde döner; ovülasyon 3–4. haftada olabilir — korunma gerekiyorsa doktoruna danış. 3 ayı geçtiyse hekimine başvur." LAM kartını yalnız exclusive/mixed'e göster. "Ovülasyon adetten önce dönebilir" uyarısını `_hadBirth` ile göster (emzirme şartı olmadan). | Evet (hafta aralıkları) | DÜZELTİLDİ `9782d32` (+ 12. hafta kartı `61231d6`) |
| **B1** | YANLIŞ BİLGİ | `cycle_engine.dart:211-226` | Son 6 döngünün ham ortalaması; 50+ günlük uç değer (unutulmuş kayıt) ayıklanmıyor, kullanıcıya sorulmuyor (F1–F3). Bildirimler aynı tahmine kurulur (`notification_service.dart:979-998`). | Tahmin son birkaç döngüden, uç değerler ayıklanarak ya da kullanıcıya sorularak yapılmalı (görev referansı A; FIGO normal 24–38 gün). | Ortalamaya girmeden önce 38 günü (ya da medyan+%50'yi) aşan span'ı dışla **ya da** o döngüye "Bu ayı kaydetmeyi unutmuş olabilir misin?" sor; ortalama yerine medyan kullan. `lowConfidence` uç değer varsa true. | Hayır (algoritma), eşik için evet | DÜZELTİLDİ `7a703b3` |
| **B2** | YANLIŞ BİLGİ | `cycle_engine.dart:294` (`lowConfidence = lengths.length < 3`); `cycle_stats_screen.dart:162-175` | Düzensiz döngüde (fark 14 gün) 3 döngü sonrası "güvenilir" sayılıp tek tarih veriliyor; rozet yok (D1). Stats pili "Değişkenlik normal/Postpartum normal" koşulsuz. | FIGO: en kısa–en uzun farkı 7–9 günü aşarsa düzensiz (Merck/StatPearls, FIGO 2018); düzensizde aralık ve "tahmin" dili. | `lowConfidence`'a varyans koşulu ekle (max−min > 9 gün → düşük güven); düşük güvende "Sonraki adet ~19–27 Eki arası" aralığı; stats pilini düzensizlikte "Düzensiz — hekimine sorabilirsin"e çevir. | Evet (eşik) | DÜZELTİLDİ `998d35d` |
| **B3** | YANLIŞ BİLGİ (küçük) | `cycle_engine.dart:256-257, 115-117` | Pencere ov−5…**ov+1** (7 gün); ov+1 "orta" olasılık. | Wilcox 1995 (NEJM 333:1517): gebelik yalnız ovülasyonda biten 6 günlük pencerede; ov sonrası gün 0. | ov+1'i pencereden çıkar ya da "düşük"e indir (My Calendar paritesi bilinçli tercihse kullanıcıya "ov sonrası olasılık hızla düşer" notu). | Evet | BİLİNÇLİ TERCİH — pencere 7 gün kalır (ov−5…ov+1): ovülasyon tahmini takvime dayalı ve belirsiz; geniş pencere gebe kalmak isteyen için kaçırma riskini, diğerleri için yanlış güvence riskini azaltır (S9) |
| **B4** | YANLIŞ BİLGİ? | `cycle_today_screen.dart:615-616`; `cycle_widgets.dart:142-145` | "Akış zamanla azalıp açılıyorsa loşia; durup koyulaşıp 4–7 gün sürerse muhtemelen ilk adettir." | Loşia seyri rubra (3–4 gün) → serosa (~10. gün) → alba; "durup yeniden başlayan koyu kanama" her zaman adet değildir (yeniden parlak kırmızı/yoğun kanama uyarı işaretidir). Bu ayrım cümlesinin kaynağı bulunamadı — **kaynak doğrulanmalı**. | Cümleyi "Kanama kesildikten sonra 4–7 gün süren düzenli bir kanama ilk adet olabilir; yeniden parlak kırmızı ve yoğunlaşan kanama için hekimine başvur" şeklinde dengele. | Evet | DÜZELTİLDİ `0d0ae85` |
| **B5** | YANLIŞ BİLGİ | `cycle_today_screen.dart:589` ("0–6 hafta"), `cycle_engine.dart:151-155` (42 gün; loşia kaydı varsa 60), `cycle_calendar_screen.dart:289/472/662` (`lochiaMode` yalnız motor loşia modunda) | 6 hafta sabit; 43. günde loşia kaydı yoksa bekleme moduna geçer ve loşia rengi artık girilemez (J3). | Loşia genellikle 4–6 hafta, 8 haftaya uzayabilir (NHS: "a few weeks"; görev referansı D). | Metni "4–6 hafta (8 haftaya uzayabilir)" yap; loşia rengi girişini doğum sonrası 8 haftaya kadar her modda aç; 6 haftayı geçen kanamada "hekimine söyle" notu. | Evet | DÜZELTİLDİ `8d6dcb8` |
| **C1** | EKSİK UYARI | `cycle_today_screen.dart:244-250, 375-380, 405-415`; grep "3 ay/hekime/acil" → 0 | "Gün gecikti" 1. günden, "Test · Gerekirse"; 12 gün gecikmede aynı; adet görmeme süresi için hekim önerisi yok (kayıp/postpartum bekleme modunda da yok: K2, J4). | Gecikince ev testi (NHS: "from the first day of a missed period"; negatifse daha az güvenilir, tekrar). 3 ay (önceden düzenli) / 6 ay adet görmeme → değerlendirme (NICE CKS amenorrhoea — **kaynak doğrulanmalı**, sayfa çekilemedi). | Gecikme kademesi: 1–4 gün "birkaç gün oynama normal"; ≥5 gün "test yapabilirsin"; ≥14 gün "test + hekim"; çapadan/son adetten ≥90 gün (ya da bekleme modunda doğum +12 hf emzirmeyen / kayıp +8 hf) → "hekimine başvur" kartı. | Evet (eşikler) | DÜZELTİLDİ `61231d6` |
| **C2** | EKSİK UYARI | `cycle_engine.dart:230-241`; `cycle_settings_screen.dart:282` (2–10 izinli) | 8 günü aşan adet için hiç uyarı yok (G1/G2); süren kanama 11. günde "Doğurganlık" gösteriyor. | Adet süresi 8 güne kadar normal, üstü "uzamış" (FIGO 2018; Merck tablosu); çok yoğun kanama hekime (NICE NG88). | Süren adet ≥9 gün ya da ortalama >8 → "Adetin 8 günden uzun sürüyor — hekimine danışmanı öneririz" notu; "Yoğun" akış ≥7 gün için aynı. | Evet | DÜZELTİLDİ `2d46cec` |
| **C3** | YANILTICI | `cycle_today_screen.dart:277, 312-313, 390-391`; `cycle_calendar_screen.dart:777, 780`; `cycle_stats_screen.dart:106-108` | "Tahmini" etiketi yalnız <3 döngüde; sonra "Sonraki adet · 19 Eki", "Yumurtlama günü — en yüksek doğurganlık", "Doğurgan gün" etiketsiz. | Tüm tahminler "tahmini" diye etiketlenmeli (görev referansı F). | Tarihlerin yanına kalıcı "~" / "tahmini"; takvim satırlarını "Tahmini yumurtlama günü", "Tahmini doğurgan gün" yap; B2 ile birlikte aralık göster. | Hayır | DÜZELTİLDİ `8ee2dd9` |
| **C4** | EKSİK | `cycle_today_screen.dart:458-507`; grep "folik/12 ay/6 ay/LH/bazal" → 0 | TTC modunda: hekime başvuru eşiği (12 ay / 35+ yaşta 6 ay) yok; folik asit yok; LH testi/mukus/BBT önerisi yok; "pencerede 1–2 günde bir ilişki" önerisi yok. | 35 altı 12 ay, 35+ 6 ay (ASRM 2023 tanımı; ACOG — **birincil sayfa çekilemedi, kaynak doğrulanmalı**). Folik asit 400 µg gebelikten önce ve ilk 12 hafta (NHS Wales). | TTC bölümüne `ttcStartedAt`'a göre süre kartı ("X aydır deniyorsun"; 12/6 ay eşiğinde hekim önerisi, yaş bilinmiyorsa 6 ayda "35+ isen" notu); folik asit bilgi kartı; "LH testi/mukus takvimi destekler" notu. | Evet (metin) | DÜZELTİLDİ `94fec3d` |
| **C5** | YANILTICI | `cycle_today_screen.dart:334-372`; `notification_service.dart:986-990` | TTC olmayan kullanıcıya da "Yüksek doğurganlık — Bugün gebelik şansı en yüksek dönemde" kartı ve (açarsa) "Doğurganlık pencereniz başlıyor" bildirimi; korunma uyarısı yalnız emziren lohusada. | Doğurgan pencere bilgisi tarafsız verilebilir ama "gebelikten korunma" çağrışımı olmamalı; kart A1 uyarısıyla birlikte olmalı. | Kartı TTC dışında "Doğurgan pencere (tahmini)" diye nötr adlandır; A1 notunu ekle. | Hayır | DÜZELTİLDİ `8116ba6` (+ bildirim `8ee2dd9`) |
| **C6** | EKSİK | `cycle_entry_sheet.dart:373-378` | "Dikkat belirtileri" grubu her modda var (iyi) ama bilgi butonu `CycleInfo.lochiaVsPeriod` açıyor; aciliyet bilgisi yok. | — | Bilgi butonunu kırmızı bayrak açıklamasına (A4 metni) bağla. | Hayır | DÜZELTİLDİ `51c1ed3` |
| **C7** | EKSİK | `cycle_settings_screen.dart:172-193`; `showFertilityWarning` okuyucu yok | "LAM / doğurganlık uyarıları" anahtarı kaydediliyor ama hiçbir uyarıyı kapatmıyor/açmıyor (işlevsiz). | — | Anahtarı kaldır ya da A2/A5 kartlarını ona bağla (önerim: **kaldır** — sağlık uyarısı kapatılabilir olmamalı). | Hayır | DÜZELTİLDİ `9ab919f` |
| **C8** | YANILTICI | `cycle_setup_screen.dart:80` | Emzirme sorusu atlanırsa `exclusive` varsayılıyor → LAM metinleri yanlış bağlamda. | — | Cevapsızsa `null` bırak ve LAM kartlarını gösterme; "Emziriyor musun?"u zorunlu yap. | Hayır | DÜZELTİLDİ `9782d32` |
| **D1** | UX | `cycle_dial.dart:148-149, 188, 200` | İyileşme halkasında yay `gün/42`, bugün boncuğu 28 günlük formülle → 28. günden sonra boncuk ve yay uyuşmuyor; gebelik halkasında `day` = hafta. | — | Mod başına açı fonksiyonu (heal: /42, pregnant: /40). | Hayır | DÜZELTİLDİ `720c75f` |
| **D2** | DİL | `../api/apps/translations/data/en.json`: "Tahmini doğum: {d}" → "Due date: {d}" | EN'de "estimated" düşmüş. | "tahmini" etiketi korunmalı (F). | "Estimated due date: {d}". (Diğer kritik metinlerin EN karşılıkları kontrol edildi, TR ile uyumlu.) | Hayır | DÜZELTİLDİ (çeviri JSON, api — commit'lenmedi; regresyon testi `a63519c`) |
| **D3** | DİL | `cycle_today_screen.dart:654-655` | "Emzirme döneminde adetin geç dönmesi tamamen normaldir" — "tamamen normal" kesinlik dili; emzirmeyene de gösteriliyor (A5). | Tahmin/olasılık dili. | "…sık görülür" + A5 ayrımı. | Hayır | DÜZELTİLDİ `9782d32` |
| **D4** | UX (ölü kod) | `cycle_widgets.dart:42-89` (`phaseLabel`, `phaseSelfCare` — kullanılmıyor) | "bebeğin uyuduğunda sen de uzan" gibi bebek varsayan metinler ölü kodda. | — | Sil ya da bebeksiz kullanıcı için düzelt. | Hayır | DÜZELTİLDİ `e2e6fe1` |
| **D5** | DİL | `cycle_today_screen.dart:384-385` | Geri sayımda mini kart "PMS olası · 2–3 gün" koşulsuz. | PMS herkeste olmaz; "olabilir" dili. | "PMS belirtileri olabilir". | Hayır | DÜZELTİLDİ `69f9287` |

**Not (bulgu değil):** ovülasyon = `sonrakiAdet − luteal(14)` → 28 günlük döngüde **15. gün** (klasik "14. gün" anlatımından 1 gün fark; NHS "sonraki adetten 10–16 gün önce" aralığında, kabul edilebilir). Gebelik haftası SAT'tan +280 (ACOG CO 700 ile uyumlu); ultrason düzeltmesi ana modülde TDT düzenlenerek yapılıyor (`baby_edit_screen.dart:157`), ancak cycle "pregnant" ekranı haftayı **hâlâ SAT'tan** hesaplıyor (`cycle_today_screen.dart:512-537`, `pregnancyFromLmp(settings.firstPeriodDate)`) → TDT düzeltilince iki ekran farklı hafta gösterir; `Baby.dueDate`'ten okumalı (**ek bulgu B6, YANLIŞ BİLGİ, uzman onayı gerekmez**) — **DÜZELTİLDİ `29fcc79`**.

---

## 5. Eksik özellikler (öneri, kısa)
- Ultrason tarihi / TDT düzeltmesi girişi cycle tarafında (B6 ile birlikte tek kaynak).
- LH (ovülasyon testi), servikal mukus, bazal vücut ısısı kaydı; BBT ile ovülasyonun geriye dönük teyidi.
- Kullanıcı yaşı (TTC eşiği 12/6 ay için) ve "kaç aydır deniyorsun" kartı.
- Unutulmuş ay için "bu döngüyü yok say" / "kayıt ekle" akışı (B1).
- Düzensiz döngüde aralık tahmini (B2) ve "3 aydır adet yok" kartı (C1).
- Loşia takibinin 8 haftaya uzatılması ve "kanama durdu" işareti (B5/A3).
- Folik asit hatırlatıcısı (TTC/gebelik).

## 6. Uzmana sorulacak sorular
1. Loşia penceresinde ilk adet çapası için güvenli eşik: doğum +42 gün mü, "loşia bitti" işareti mi, yoksa kullanıcı onayı yeterli mi? (A3)
2. "Durup koyulaşıp 4–7 gün süren kanama ilk adettir" ayrımı klinik olarak savunulabilir mi; yeniden parlak kırmızı kanama uyarısıyla nasıl dengelenmeli? (B4)
3. Kırmızı bayrak diyaloğunda "acil (112)" ile "hekime başvur" ayrımı hangi belirtilerde yapılmalı; saatte 1+ ped için süre eşiği (ör. 2 saat) konulmalı mı? (A4)
4. Emzirmeyen lohusa için gösterilecek aralıklar: ovülasyon 3–4 hf, ilk adet 5–8 hf; "3 ayı geçtiyse hekime" eşiği uygun mu? (A5, C1)
5. LAM: 6. ay sonrası / karışık beslenmede metin "LAM artık geçerli değil" olarak otomatik değişsin mi? (A2)
6. Düzensiz döngü eşiği olarak FIGO 7–9 gün (yaşa göre) mi, sabit 9 gün mü kullanılsın; aralık tahmini nasıl sunulsun? (B2)
7. Uç değer ayıklama eşiği: 38 gün (FIGO üst sınır) mı, kullanıcı ortalamasının +%50'si mi? (B1)
8. Gecikme kademeleri (test önerisi 5. gün? hekim 14. gün?) ve amenore eşiği (3 ay önceden düzenli / 6 ay düzensiz) onaylanır mı? (C1)
9. Doğurgan pencere ov+1'i içermeli mi (My Calendar paritesi) yoksa Wilcox 6 güne mi inilmeli? (B3) — **Karar S9: 7 gün kalır (bilinçli tercih, temkinli taraf).**
10. Adet süresi >8 gün ve "yoğun ≥7 gün" uyarı eşikleri uygun mu? (C2)
11. TTC'de "pencerede 1–2 günde bir ilişki" önerisi eklensin mi; folik asit dozu metni (400 µg; risk grubunda 5 mg hekimle) nasıl verilsin? (C4)
12. Kayıp sonrası "ovülasyon ~2 hafta içinde dönebilir" ifadesi 13. haftadan sonraki kayıplar için de uygun mu? (K1)

## 7. Kaynaklar (web'den doğrulananlar)
- FIGO 2018 normal adet parametreleri (24–38 gün; ≤8 gün; düzenlilik 7–9 gün): [Merck Manuals — Normal Menstrual Parameters](https://www.merckmanuals.com/professional/multimedia/table/normal-menstrual-parameters), [StatPearls — Physiology, Menstrual Cycle](https://www.statpearls.com/articlelibrary/viewarticle/24987/)
- Wilcox, Weinberg, Baird 1995, NEJM 333:1517 (6 günlük pencere, ovülasyonda biter): [NEJM 1995 (Ovid)](https://www.ovid.com/journals/nejm/pdf/10.1056/nejm199512073332301~timing-of-sexual-intercourse-in-relation-to-ovulation---)
- Ovülasyon zamanı (sonraki adetten 10–16 gün önce), normal döngü 21–35: [NHS — Fertility in the menstrual cycle](https://www.nhs.uk/conditions/periods/fertility-in-the-menstrual-cycle/)
- LAM üç koşul: [CDC MEC Appendix G — Lactational Amenorrhea Method](https://www.cdc.gov/reproductivehealth/contraception/mmwr/mec/appendixg.html), [WHO/JHU Family Planning Handbook — LAM](https://fphandbook.org/node/2116) (%98 rakamı WHO birincil sayfasında doğrulanamadı — **kaynak doğrulanmalı**)
- Loşia, doğum sonrası uyarı işaretleri, 3 haftada gebelik/21 günde korunma, emzirmeyende adet 5–6 hf: [NHS — Your body after the birth](https://www.nhs.uk/pregnancy/labour-and-birth/after-the-birth/your-body/)
- Gebelik testi zamanı: [NHS — Doing a pregnancy test](https://www.nhs.uk/pregnancy/trying-for-a-baby/doing-a-pregnancy-test/)
- TDT yöntemi (SAT + ultrason, CO 700): [ACOG Committee Opinion 700 (SMFM)](https://publications.smfm.org/publications/239-acog-committee-opinion-700-methods-for-estimating-the/) (280 gün ifadesi tam metinde — **kaynak doğrulanmalı**)
- Kayıp sonrası adet 4–6 hf, 2 hf içinde ovülasyon: [Gloucestershire NHS — Early miscarriage](https://gloshospitals.nhs.uk/your-visit/patient-information-leaflets/early-miscarriage-ghpi0870_01_17), [Tommy's](https://www.tommys.org/baby-loss-support/miscarriage-information-and-support/your-options-and-decisions/what-happens-my-body-during-miscarriage), [Miscarriage Association](https://www.miscarriageassociation.org.uk/?p=37800)
- Folik asit 400 µg: [NHS Wales — Planning a pregnancy](https://111.wales.nhs.uk/livewell/pregnancy/SecretstosuccessPlanning/)
- Yoğun adet (NG88): [NICE NG88 — Heavy menstrual bleeding](https://www.nice.org.uk/guidance/ng88/informationforpublic)
- İnfertilite değerlendirme 12/6 ay (ASRM 2023 tanımı, ikincil kaynak; ACOG sayfası çekilemedi — **kaynak doğrulanmalı**): [OBG Project — Infertility evaluation](https://www.obgproject.com/2023/02/21/infertility-evaluation-who-when-and-how/)
- Emzirmeyende ovülasyon dönüşü (ort. 45 gün, 3. haftadan itibaren korunma; ikincil): [GLOWM — Postnatal family planning](https://www.glowm.com/article/heading/vol-15--the-puerperium--postnatal-family-planning/id/416533)
- Doğrulanamayan: NICE CKS amenore tanımı (sayfa 403), ACOG postpartum birth control FAQ (402), ACOG evaluating infertility FAQ (402) → ilgili satırlar "kaynak doğrulanmalı".
