---
name: yas-genisletme-backlog
description: "İleride yapılacak 2-5 yaş zenginleştirme backlog'u (WHO 24-60 ay + milestone + içerik)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 40f87d3b-4fdf-4bc9-a1bf-aebd177f4a73
---

2–5 yaş kitlesi için zenginleştirme kısmen yapıldı. Kalan öncelik sırası:

1. ✅ **WHO 24–60 ay büyüme tabloları — TAMAM (2026-06-14).** `who_lms.dart` 0–60 ay, `who_growth.dart` `maxMonth=60`. Kaynak/yöntem: [[who-lms-veri-kaynagi]]. (BMI-for-age henüz yok, istenirse eklenebilir.)
2. **Milestone kataloğunu 36 ay → 48/60 aya uzat** — `milestone_catalog.py`'a 4-5 yaş göstergeleri. (Katalog 2026-06-14 zenginleşti ama tavan hâlâ 36 ay.)
3. **24–60 ay yaşa uygun makaleler** — içerik motoru `age_min/max_month` filtreli; seed ekle. (Mevcut makaleler çoğunlukla 0–12 ay.)
4. (orta) Diş 2. büyük azılar; aşı takviminde 48 ay okul öncesi dozu.

**Why:** Çoğu "veri/içerik doldurma", yeni mimari değil; düşük risk. Ama retention özelliği olarak konumlanmalı — reklamın ana vaadi 0-12 ay kalsın (bkz [[hedef-kitle-konumlandirma]]). WHO veri üretim yöntemi: [[who-lms-veri-kaynagi]].
