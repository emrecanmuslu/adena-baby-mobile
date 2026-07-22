# Adet Takvimi — Davranış Matrisi (Sözleşme)

> Bu doküman adet modülünün **beklenen** davranışını tanımlar; `test/journeys/cycle_lifecycle_journey_test.dart`
> ve `test/engines/cycle_engine_test.dart` bu sözleşmeyi kodda doğrular. Davranış değişecekse
> ÖNCE burası güncellenir, sonra testler.
>
> Kaynak dosyalar: `lib/features/cycle/cycle_engine.dart` (motor), `lib/data/cycle_repository.dart`
> (durum makinesi), `cycle_lifecycle.dart` / `cycle_pregnancy_bridge.dart` / `cycle_loss.dart` (geçişler),
> `lib/features/babies/born_flow_screen.dart` (doğum senkronu).

## 1. Kullanıcı tipleri (personalar)

| # | Persona | Kurulum dalı | Başlangıç ayarları |
|---|---------|--------------|--------------------|
| P1 | **Bebeksiz, yalnız adet takibi** | cycle-first sihirbaz (2 adım) | `breastfeeding=none`, `birthDate=null`, `lifecycleMode=tracking`, LMP girildiyse `firstPeriodDate` dolu |
| P2 | **Bebeksiz, gebe kalmaya çalışan (TTC)** | cycle-first sihirbaz | P1 + `lifecycleMode=ttc`, `ttcStartedAt` damgalı |
| P3 | **Gebe** | "Hamileyim" köprüsü | `lifecycleMode=pregnant`, gerçek kaynak = `Baby(status=expecting)`; cycle yalnız yansıma |
| P4 | **Doğum sonrası (lohusa)** | doğum sonrası sihirbaz (3 adım) veya born-flow senkronu | `birthDate` dolu, `breastfeeding` seçili, `firstPeriodDate=null`, `lifecycleMode=postpartum`, `predictionsHidden=true` |
| P5 | **Kayıp yaşamış (iyileşme)** | kayıp akışı | `lifecycleMode=loss`, `predictionsHidden=true`, `lastLossDate` dolu, `firstPeriodDate=null`, `babyId=null` |

## 2. Motor modu tayini (`computeStatus`) — tek karar tablosu

Motor **yalnız** `firstPeriodDate` (çapa/LMP), `predictionsHidden`, `birthDate` ve kayıtlara bakar;
`lifecycleMode` motoru DEĞİL, kabuk/ekran seçimini yönlendirir.

| Koşul | Mod | Kullanıcı ne görür |
|-------|-----|--------------------|
| çapa yok **veya** `predictionsHidden=true`, doğumdan 0–42 gün | **lochia** | Loşia günü sayacı, iyileşme bilgisi. **Tahmin YOK** |
| çapa yok/gizli, doğumdan 43–60 gün **ve** loşia kaydı girilmiş | **lochia** | (pencere uzatması — loşia sürüyor) |
| çapa yok/gizli, diğer tüm durumlar (doğum >60g, doğum yok, kayıp) | **waiting** | "İlk adetin dönüşünü bekliyoruz" bilgilendirme. **Tahmin YOK** |
| çapa dolu **ve** `predictionsHidden=false` | **active** | Döngü günü, faz, sonraki adet, ovülasyon, doğurgan pencere |

Kritik değişmezler:
- `predictionsHidden=true` iken çapa dolu olsa bile **asla** tahmin üretilmez.
- Çapadan **önceki** adet kayıtları yok sayılır (doğum/kayıp sonrası "yeni Gün 1" sıfırlaması eski
  döngülerle kirlenmez; `cycleNumber` çapadan itibaren sayılır).
- Loşia günleri (`lochiaColor != null`) akış girilmiş olsa bile **adet sayılmaz** (`isPeriod=false`)
  → yanlış döngü başlatmaz, çapayı otomatik SET ETMEZ.
- `spotting`/`none` akış adet sayılmaz.

## 3. Ayarlar ve etkileri (active moddaki hesap)

| Ayar | Geçerli aralık | Geçersiz/boşsa | Etkisi |
|------|---------------|----------------|--------|
| `expectedCycleLength` | 21–40 | 28 | Ölçülmüş döngü yokken (veya smart kapalıyken) döngü uzunluğu |
| `periodLength` | 2–10 | 5 | Ölçülmüş adet günü yokken (veya smart kapalıyken) adet süresi |
| `lutealPhaseLength` | 10–16 | 14 | Ovülasyon = sonraki adet − luteal (her zaman bu değer; ölçülmez) |
| `smartPrediction` | bool (vars. açık) | — | AÇIK: son N döngünün ortalaması; KAPALI: hep manuel değerler |
| `learningWindow` | 2–12 | 6 | Smart açıkken ortalanan son döngü sayısı |
| `weekStartsSunday` | bool (vars. Pzt) | — | Yalnız takvim görünümü; hesabı etkilemez |
| `showFertilityWarning` | bool (vars. açık) | — | Yalnız UI uyarısı; hesabı etkilemez |
| `breastfeeding` | exclusive/mixed/none | null = kurulmamış | **Kurulum bayrağı**: null ise sihirbaz açılır. Ayrıca bilgi metinleri |

Türetme kuralları:
- Ortalamalara yalnız **tamamlanmış** döngüler girer (devam eden döngü ortalamayı bozmaz).
- `lowConfidence` = tamamlanmış döngü sayısı < 3 → UI "tahmini/değişebilir" der.
- Doğurgan pencere = ovülasyon −5 … +1. Olasılık kademeleri: ovülasyon=çok yüksek,
  ov−1/−2=yüksek, pencere kenarları ve ov+1=orta, dışı=düşük.
- Mevcut döngünün penceresi geçtiyse pano/hatırlatıcı **sonraki** döngünün penceresini gösterir
  (takvim işaretlemesi mevcut döngüde kalır).

## 4. Yaşam-döngüsü geçişleri (olay → yazılan alanlar → sonuç)

Kullanıcının doğrudan seçebildiği modlar: tracking, ttc, pregnant. postpartum ve loss **olay-tetikli**.

| Olay | Nereden | Yazılan alanlar | Sonuç mod |
|------|---------|-----------------|-----------|
| Hedef değişimi (ayarlar) | tracking↔ttc | `lifecycle_mode`, `predictions_hidden=false`; ttc'ye geçişte `ttc_started_at` | tracking/ttc |
| "Hamileyim" onayı | tracking/ttc | Expecting `Baby` oluşturulur/bağlanır (`dueDate=LMP+280`), `lifecycle_mode=pregnant`, `baby=<id>`, `predictions_hidden=false` | pregnant |
| Doğum (born-flow) | pregnant (veya köprü dışı gebelik) | `lifecycle_mode=postpartum`, `predictions_hidden=true`, `birth_date`, **`first_period_date=null`** (eski LMP geçersiz) | postpartum |
| Kayıp onayı | pregnant | Expecting bebek silinir; `lifecycle_mode=loss`, `predictions_hidden=true`, `last_loss_date`, **`first_period_date=null`**, **`baby=null`** | loss |
| "Adet takibine dön" (gebelik sonlandırma sayfası / iyileşme CTA) | pregnant/loss | `lifecycle_mode=tracking`, `predictions_hidden=false` (çapa DOKUNULMAZ — kayıptan dönüşte zaten null) | tracking |
| **İlk adet loglanır** (çapa null→dolu) | postpartum/loss | `first_period_date=<log tarihi>` + **otomatik** `lifecycle_mode=tracking`, `predictions_hidden=false` | tracking (active) |
| Adet loglanır, çapa dolu ama `predictionsHidden` takılı kalmış (onarım) | postpartum/loss | `predictions_hidden=false` + mod postpartum/loss ise `lifecycle_mode=tracking` | tracking |

Kritik değişmezler:
- Gebelikten çıkış **tek kapıdan**: mod seçici pregnant'tan doğrudan tracking/ttc'ye yazmaz,
  önce doğum/kayıp/dön sayfası açılır (yetim expecting bebek kalmasın).
- Otomatik ilk-adet geçişi **merkezde** (`patchSettings`) yaşar: hangi ekrandan girilirse girilsin
  (hızlı giriş, takvim, adet düzeltme) aynı geçiş çalışır.
- Çapa **zaten doluyken** yeni adet logu mod değiştirmez (yalnız null→dolu tetikler).
- **Backfill koruması:** çapa adayı yalnız son sıfırlama olayından (doğum/kayıp gününün
  **sonrasından**) tarihli adet loglarıdır. Lohusa/kayıp kullanıcı geçmiş (olay öncesi veya olay
  günü) bir adetini sonradan işlerse çapa SET EDİLMEZ, otomatik geçiş/onarım tetiklenmez —
  aksi halde yanlış Gün 1 kurulup istenmeden aktif takibe geçilirdi.
- Patch açıkça `lifecycle_mode` içeriyorsa otomatik geçiş devreye girmez (çağıranın kararı önceliklidir).
- Kayıpta son bebek de silindiyse `cycleFirst=true` yapılır (router onboarding'e atmaz,
  kullanıcı iyileşme modunda Adet Takvimi'nde kalır).

## 5. Uçtan uca yolculuklar (testlerin senaryoları)

1. **P4 tam yolculuk:** doğum → gün 10 loşia → gün 50 bekleme → gün 70 ilk adet →
   otomatik tracking/active, `cycleNumber=1`, doğum öncesi kayıtlar yok sayılır.
2. **P3→P5 kayıp:** aktif takip → gebelik → kayıp (`recordCycleLoss`) → tahminler gizli, çapa/bebek
   temiz → iyileşmeden dönüş → bekleme → ilk adet → yeni Gün 1, eski döngüler sayılmaz.
3. **Loss modundan doğrudan adet logu:** "takibe dön"e basmadan adet girilirse de otomatik geçiş çalışır.
4. **Onarım kancası:** çapa dolu + gizli takılı kalmış → adet logu → gizlilik kalkar, mod düzelir.
5. **P1/P2 bebeksiz:** kurulum → çapasızsa bekleme (loşia DEĞİL — doğum yok) → ilk adet → active;
   tracking↔ttc geçişi damga/bayrakları doğru yazar.
