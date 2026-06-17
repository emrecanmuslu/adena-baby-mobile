---
name: gorunum-birimler-birlesti
description: "Ayarlardaki Görünüm + Birimler tek alt sayfada birleşti (/appearance, tasarım 28)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

Ayarlar menüsündeki ayrı "Görünüm" (tema dialog'u) ve "Birimler" (/units) satırları **tek sayfada birleştirildi** (kullanıcı 2026-06-11): `features/settings/appearance_screen.dart` (`/appearance`), tasarım **28 · ScrAppearance** = Tema + Dil + Birimler tek sayfa.

- Settings'te tek "Görünüm" satırı → `/appearance`. Eski `_pickTheme` dialog'u ve ayrı "Birimler" satırı kaldırıldı.
- `units_screen.dart` SİLİNDİ, `/units` route kaldırıldı; birim içeriği (+_UnitRow) appearance'a taşındı.
- Tema: 3 kart (Açık/Gece/Otomatik) gradient önizlemeli. Dil: Türkçe/English (bkz [[i18n-ceviri-sistemi]]). Birimler: Hacim/Ağırlık/Uzunluk/Ateş (aile geneli, activeUnitsProvider).
