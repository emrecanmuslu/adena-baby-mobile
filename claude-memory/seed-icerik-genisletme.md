---
name: seed-icerik-genisletme
description: Seed/içerik genişletme durumu + gebelik içeriği negatif-yaş konvansiyonu
metadata: 
  node_type: memory
  type: project
  originSessionId: 5d4e3e8a-6a15-4b8e-bacf-bfae777e4fd1
---

2026-06-14 genişletildi (tümü özgün yazıldı):
- **milestone_catalog.py** ~58 taşa çıktı (1-36 ay, yenidoğan+15/30 ay dahil); her taşta `description`+`tip` (DB'de değil, serializer katalogtan `key` ile sunar — migration yok). Detay sheet + kategori dökümü eklendi. Bkz [[gelisim-bolumu-tamamlandi]] yoksa.
- **pregnancy_weeks.dart** `_weekNotes` 4-40 haftanın tamamı dolu.
- **symptom.dart** `trSymptomInfo(key)` 14 belirtiye bakım+"ne zaman doktora" rehberi; kayıt formunda `_SymptomInfoCard` ile gösterilir.
- **seed_content.py** 8→29 makale; yeni **"gebelik" kategorisi** + 0-12 ay zenginleştirme.

**KRİTİK konvansiyon — gebelik makaleleri:** `age_min_month=-9, age_max_month=-1` (NEGATİF). Sebep: doğmuş bebek yaş şeridi `age_months>=0` sorgular → gebelik makaleleri sızmaz. Bekleme modunda content_hub `_PregnancyStrip` bunları **kategori bazlı** (`category='gebelik'`, yaş filtresi yok) gösterir; `babyAgeMonths` expecting'te null döndüğü için yaş şeridi gebede çalışmaz. Yeni gebelik makalesi eklerken yaş aralığını negatif ver.

Hâlâ backlog: WHO LMS 24-60 ay (bkz [[yas-genisletme-backlog]]).
