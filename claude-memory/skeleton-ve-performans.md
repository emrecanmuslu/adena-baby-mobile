---
name: skeleton-ve-performans
description: "UI standardı — yükleme durumlarında skeleton, büyük listelerde lazy/sayfalı yükleme"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 3c1c5505-1248-4e5e-a584-059ca945608e
---

Bundan sonra eklenen TÜM ekranlarda/veri yüklemelerinde performans + yükleme UX standardı uygulanmalı.

**Why:** 500+ kayıtla test edildiğinde uygulama kasılıyordu; tüm sekmeler aynı anda yükleniyordu ve yükleme sırasında loader yoktu (içerik geç geliyordu).

**How to apply:**
- **Skeleton:** Yükleme durumunda `lib/core/skeleton.dart` (`Skeleton`, `SkeletonRecordList`) kullan — spinner yerine içerik iskeleti. Yeni listelerde de aynısı.
- **Lazy:** Sekmeli ekranlarda yalnız aktif sekmeyi kur (IndexedStack yerine `switch(_tab)`).
- **Sayfalama:** Uzun listeler infinite scroll — drift'te `..limit(n)` artan limit + `ScrollController` (örnek: `pagedRecordsProvider` + `timeline_view.dart`).
- **Küçük sorgu:** "Son N" gibi yerlerde tüm tabloyu çekme; limitli stream kullan (`watchRecent`). Ağır agregasyonu (grafik) yalnız o sekme açıkken çalıştır.
