---
name: kayit-zaman-secici-akisi
description: "Kayıt ekleme zaman seçici — önce saat, \"Tarih seç\"→takvimde güne dokununca otomatik saate dön"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c8644f44-9310-4034-9d03-d7c0356fd453
---

Kayıt ekleme ekranlarında zaman seçimi akışı (paylaşımlı `pickRecordDateTime` — `core/ad_widgets.dart`):
- Dokununca **önce saat seçici** açılır (kayıt çoğunlukla bugün için eklenir; bugün varsayılan).
- Saat seçicinin sol-alt aksiyon butonu **"Tarih seç"** (yerel `showTimePicker`'a 3. buton enjekte edilemediği için cancel slotu yeniden kullanıldı), onay = **"Tamam"**.
- "Tarih seç" → `CalendarDatePicker` özel diyaloğu (`_pickDateAutoAdvance`): bir güne dokununca **onay beklemeden anında kapanır ve otomatik saate döner**. Sağ üst "Vazgeç" tüm akışı iptal eder.
- Kullanan ekranlar: `records/record_form.dart`, `home/mom_tracking_screen.dart`. Yalnız-tarih ekranları (anı/diş/doğum tarihi) ve hatırlatıcı/randevu kapsam dışı.

**Why:** Kullanıcı bu akışı iki turda netleştirdi (önce "önce saat, sonra tarih sırayla", sonra "takvimde güne dokununca otomatik saate dönsün").
**How to apply:** Yeni kayıt ekleme ekranı eklerken date→time yerine `pickRecordDateTime(context, initial)` kullan. [[bilgi-rozeti-ilkesi]] [[tasarim-bilesen-kiti]]
