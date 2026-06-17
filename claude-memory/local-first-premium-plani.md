---
name: local-first-premium-plani
description: "Free=yerel depolama, Premium=cloud yedek/senkron fikri; tasarım notu kök dosyada, başka oturumda uygulanacak"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0abfd143-cc48-40bd-a2ab-057f2ca5a75d
---

Sunucu maliyetini düşürmek için kullanıcının önerisi: **Free kullanıcı verilerini yalnız telefonda (yerel) tutsun, Premium kullanıcı buluta gitsin.** Premium yeniden konumlanır → "verilerin güvende, telefon kaybolsa bile kaybolmaz".

Tam tasarım notu: kök dizinde `LOCAL_FIRST_PREMIUM_TASARIM.md`. Durum=PLAN, kod yok, **başka bir oturumda uygulanacak** (2026-06-16 kararı).

Kritik noktalar: veri kaybı=güven kaybı riski (free'ye güvenlik ağı export öner), free→premium migrasyon + premium bitince veri politikası (rehin almak App Store riski), iki kaynaklı repo soyutlaması. Öneri yön: herkes offline-first, fark "cloud senkron açık/kapalı" bayrağı.

İlgili: [[para-kazanma-modeli]] [[sync-polling-mimarisi]] [[cloud-deploy-hetzner]]
