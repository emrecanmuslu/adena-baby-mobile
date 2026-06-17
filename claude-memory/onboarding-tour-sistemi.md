---
name: onboarding-tour-sistemi
description: Ekran başına bir-kez gösterilen kart-kart tanıtım turu sistemi (mimari + yeni tur ekleme)
metadata: 
  node_type: memory
  type: project
  originSessionId: 5d4e3e8a-6a15-4b8e-bacf-bfae777e4fd1
---

2026-06-14 eklendi: ilk-giriş kullanıcısı için **ekran başına kart-kart tanıtım turu** (yaygın "product tour" kalıbı; nokta-spotlight DEĞİL, ortada kart carousel'i). Bir kez gösterilir, "Geç" ile atlanır.

**Mimari:**
- `core/tour.dart` — motor: `TourStep(emoji,title,body)`, `tourFor(key)` (içerik switch'i, tr() ile), `TourController` (AsyncNotifier<Set<String>>, görüldü kümesi), `tourControllerProvider`, `TourMount` widget'ı, `_TourDialog` (PageView + nokta + "Devam/Anladım/Geç").
- `data/tour_cache.dart` — `flutter_secure_storage` tek anahtar `tour_seen_v1` (CSV). (Not: projede shared_preferences YOK, secure storage kullanılır.)
- Görüldü durumu kümede; `AsyncValue.asData?.value` ile okunur (bu Riverpod sürümünde `valueOrNull` YOK).

**Yeni ekran turu eklemek:** `tourFor()` switch'ine `'key' => [TourStep(...), ...]` ekle, sonra ekranı `TourMount(tourKey:'key', child: <ekran>)` ile sar. İtilen rotalar **router.dart**'ta sarılı (const TourMount); ana sekmeler (home/timeline/charts/expecting) **home_screen.dart** `body: switch(_tab)` içinde sarılı (IndexedStack değil, yalnız aktif sekme kurulur).

**⚠️ KEY TUZAĞI (yaşandı):** Aynı ağaç pozisyonunda render edilen TourMount'lara (switch(_tab) sekmeleri) **ayrı `ValueKey` şart** — yoksa Flutter tek State'i yeniden kullanır, ilk sekme guard'ı kapatınca diğer sekmelerin turu HİÇ açılmaz. Ayrıca TourMount'ta kalıcı "gösterildi" latch'i YOK; sadece `_showing` (dialog açık) guard'ı var → ayarlardan sıfırlama sonrası turlar tekrar açılabiliyor (`seen` markSeen ile true olunca tekrar tetiklenmez).

**Mevcut turlar (19):** home, timeline, charts, expecting, discover, health, milestones, teeth, memories, community, content, mom, vaccines, reminders, members, caregiver, premium, babyedit, settings. **charts** turu özellikle WHO persentilini sade dille anlatır (kullanıcı talebi). Kasıtlı turlanmayanlar: splash/auth/setup/born-flow/appearance/privacy/article list+detail/dev (geçici ya da kendiliğinden anlaşılır).

Ayarlar → Uygulama → "Tanıtım turları" = `resetAll()` ile hepsini tekrar gösterir. İlgili: [[bilgi-rozeti-ilkesi]] (AdInfoDot ile tamamlayıcı), [[i18n-ceviri-sistemi]].
