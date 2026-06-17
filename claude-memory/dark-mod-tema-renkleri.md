---
name: dark-mod-tema-renkleri
description: "Dark mod renkleri tasarımın Gece Modu'na getirildi — AppColors semantik nötrleri tema-duyarlı getter"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

Dark mod renkleri tasarımın **Gece Modu** (`.force-dark` / `[data-theme=dark]`) paletine getirildi (kullanıcı 2026-06-11). `analyze` temiz, build+install OK, dark render doğrulandı.

**Sorun:** `AppColors` semantik nötrleri `static const` (açık-only) idi; widget'lar bunları sabit kullandığı için dark'ta uymuyordu.

**Çözüm (`core/theme.dart`):** ink, ink2, muted, muted2, line, line2, peach, peachLight, cream, cream2 → **tema-duyarlı getter** (`static Brightness brightness` + `_d ? darkLit : lightLit`). Tasarım dark değerleri: bg/cream #191320, cream2 #221A2A, card/surface #251D2E, ink #F2E8E3, ink2 #D8C9C2, muted #9F92A2, muted2 #766C7C, line #352B40, line2 #403349, peach #3E2C3C, peach-l #33283A. Marka/kategori renkleri (coral, feed, sleep, feedBg/sleepBg vb.) ve softShadow **sabit** (her iki temada aynı; tasarım force-dark'ta kategori bg'leri değiştirmiyor).

**Wiring:** `main.dart` AdenaApp.build'de etkin temaya göre `AppColors.brightness` set edilir (themeMode dark || (system && platformBrightness dark)). `AppTheme.light/dark` getter'lara BAĞLI DEĞİL — sabit literallerle (`_base(bg, fg, line, chipSel)`) kurulur ki her tema kendi içinde tutarlı olsun.

**Mekanik temizlik:** Getter'a çevirince ~264 `const` ifadesi kırıldı; workflow (24 ajan) ile bu renklere bağlı **130 const kaldırıldı**. `AdStepper.accent` nullable yapıldı (`?? AppColors.ink`).

**Bilinen küçük pürüz:** Splash, tema provider yüklenmeden render olduğu için bir an açık görünüp dark'a geçebilir (geçici, kabul). bkz [[gorunum-birimler-birlesti]]
