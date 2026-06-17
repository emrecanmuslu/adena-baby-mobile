---
name: gebelik-haftasi-veri-dogrulama
description: "Bekleme ekranı gebelik haftası verisinin doğrulama kararları — kilo=Hadlock, boy=BabyCentre baş-topuk, hafta=tamamlanan, CRL→baş-topuk 20.hf"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 25600dfe-b590-4cea-aa23-44ac7147e1de
---

Bekleme (gebelik) ekranı haftalık boy/kilo verisi doğrulandı (2026-06-15) ve referansları:

- **Kilolar = Hadlock fetal ağırlık standardı** (klinik). 16h≈100g, 20h≈300g, 24h≈600g, 28h≈1.0kg, 32h≈1.7kg, 36h≈2.6kg, term 40h≈3.5kg. BabyCentre tüketici değerleri daha yüksektir; Hadlock tercih edildi, DEĞİŞTİRME.
- **Boylar = BabyCentre baş-topuk eğrisi** (20. hf sonrası). 20–25. haftalarda yapay sıçrama vardı (24h=30→25h=34.6 hatası); 21–26 düzeltildi (27.4/29/30.6/32.2/33.7/35.1).
- **Ölçüm konvansiyonu:** ilk haftalar baş–popo (CRL), ~20. haftadan sonra baş–topuk → 19→20. haftada (15.3→25.6cm) doğal sıçrama; HATA DEĞİL. Bilgi rozetinde (AdInfoDot) açıklanıyor; boy/kilo'nun ortalama olduğu, sapmanın normal olduğu da burada.
- **Hafta gösterimi = TAMAMLANAN hafta** (LMP'den, `daysPregnant ~/ 7`). Etiket "X. Hafta Y. gün" = Xw(Y-1)d; "39. Hafta 1. gün" = 39w0d. Görsel + ölçü + etiket hepsi tamamlanan haftaya dayanır (eskiden +1 kaymıştı, düzeltildi). Header `_babyAgeShort` da aynı formüle (gece-yarısı bazlı gün farkı) çekildi — `DateTime.now()` saat dahil kullanınca sınırda 1 hafta kayıyordu.

Veri iki yerde aynı: backend `seed_pregnancy_weeks.py` + mobil gömülü `pregnancy_weeks.dart` (bkz [[statik-icerik-api-migrasyonu]]).
