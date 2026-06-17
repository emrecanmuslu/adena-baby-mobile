---
name: tasarim-kaynagi
description: Okunabilir tasarım kaynağı (React JSX + CSS) — ekranları birebir eşlemek için
metadata: 
  node_type: memory
  type: reference
  originSessionId: 3c1c5505-1248-4e5e-a584-059ca945608e
---

Onaylı tasarımın **okunabilir** kaynağı: `design/AdenaBaby/` (Claude Design export).
Ekranları Flutter'a çevirirken buraya bak — bundled `Adena Baby - Standalone.html` paketli/okunmaz, bunlar açık:

- `adena.css` — design token'ları (renkler, gölge, radius). Önemli: `--bg=--cream=#FFF8F4`, `--cream-2=#FFF1E9`, `--coral=#FF8A7A`, `--coral-d=#F2705E`, `--coral-dd=#E2553F`, `--ink=#3D2B26`, `--muted=#A08C83`. Kategori renkleri + `-bg` tonları da burada.
- `ui.jsx` — ortak bileşenler: `Logo` (aden=ink + dolu #F2705E kalp + a=coral-d + baby=muted/600, weight 900), `Phone`, `StatusBar`, `TopBar`, `BottomNav`, `PercentileChart`.
- `icons.jsx` — çizgi ikon seti (stroke 1.8, yuvarlak uç) + `CAT` kategori meta.
- `screens-onboard.jsx` (splash/login/born-q/date/profile/invite), `screens-tracking.jsx`, `screens-waiting.jsx`, `screens-health.jsx`, `screens-settings.jsx`, `screens-extra.jsx`, `screens-entry.jsx`.
- `screenshots/preview.png` — render önizleme (görsel doğrulama).

[[skeleton-ve-performans]] ile birlikte: yeni ekranları bu kaynaktan birebir + skeleton/lazy ile yap.
