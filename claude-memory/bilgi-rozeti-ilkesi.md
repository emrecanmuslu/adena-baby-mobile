---
name: bilgi-rozeti-ilkesi
description: "UX ilkesi — her alan/bölüm başlığının yanında '!' yardım rozeti olmalı; dokununca özelliği anlatan dialog açılır"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

Uygulama **en basit/acemi kullanıcı için bile** anlaşılır olmalı. Bu yüzden **her alanın ve bölüm başlığının yanına bir "!" (bilgi) rozeti** konur; kullanıcı dokununca o özelliğin **ne işe yaradığını ve nasıl kullanıldığını** anlatan kısa bir dialog açılır (jargon yok, sade Türkçe, örnekli).

**Why:** Kullanıcı 2026-06-11'de istedi — beslenme hatırlatıcısı sheet'indeki tek üst bilgi notu yetersiz/genel kalıyordu ("Baz alınan beslenme ne demek?" gibi sorular). Çözüm: bağlamsal, alan-bazlı yardım.

**How to apply:**
- Mekanizma `core/ad_widgets.dart`'ta hazır: `AdField(label:, info:, child:)` ve `adSec(title, info:)` opsiyonel `info` alır → otomatik `AdInfoDot` ("!" rozeti) ekler. Rozet `showAdInfo(context, title, body)` dialogunu açar (sade, tek "Anladım" butonlu, coral "!" amblemli).
- Sheet/dialog başlıklarına da elle `AdInfoDot(title:, body:, size: 16)` eklenebilir (bkz reminders_screen.dart beslenme & sessiz saat sheet başlıkları).
- **Yeni alan/ekran eklerken her zaman `info` metni yaz** — bunu standart say. Metin: önce ne işe yaradığı, sonra nasıl kullanılacağı + somut örnek.
- Üst bilgi notları (\_InfoNote) kısa tutulur; ayrıntı per-alan "!" rozetine taşınır. **Metinlerde "(!) işaretine dokunarak..." gibi ipucu cümlesi YAZMA** (kullanıcı istemedi) — rozet kendiliğinden keşfedilir.

Uygulanan ilk yerler: beslenme hatırlatıcısı sheet'i (Aralık/Baz/Ön-hatırlatma/Sesli alarm) + sessiz saat sheet'i. Diğer ekranlar zamanla aynı desene geçirilecek. bkz [[tasarim-bilesen-kiti]] [[beslenme-hatirlatici]] [[sessiz-saat]]
