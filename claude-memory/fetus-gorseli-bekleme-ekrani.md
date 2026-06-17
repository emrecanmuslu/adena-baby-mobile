---
name: fetus-gorseli-bekleme-ekrani
description: "Bekleme ekranı haftalık fetus görseli — API media'dan (9:16), yuvarlak köşe overlay, ±5 gün gezinme"
metadata: 
  node_type: memory
  type: project
  originSessionId: 25600dfe-b590-4cea-aa23-44ac7147e1de
---

Bekleme (gebelik) ekranındaki haftalık gelişim görseli (2026-06-15):

- **Kaynak = API media**, uygulamada paketlenmez. Görseller `api/media/fetus/4.png` … `40.png` (haftaya göre). Prod (Hetzner) deploy'da `media/` git'e girmez → sunucudaki `media/fetus/`'a ayrıca yüklenmeli (nginx /media sunuyor). URL: `AppConfig.mediaBaseUrl` (apiBaseUrl'den `/api/v1` atılır) + `/media/fetus/$week.png`.
- **Görseller 9:16 dikey.** `expecting_home.dart` `_FetusImage`: 9:16, yuvarlak köşe (radius 26) + softShadow, `BoxFit.cover`, hafta değişince cross-fade; yüklenemezse meyve emojisine düşer.
- Rozetler ("X. Hafta Y. gün", "Bugüne dön") ve sol/sağ gezinme okları **görselin üzerinde** (Stack overlay), yarı saydam beyaz zemin.
- **Gezinme = gün bazlı ±5 gün** (`_dayOffset`); görsel yalnız hafta değişince değişir, gün içinde sabit kalır.

Hafta/veri doğruluğu: [[gebelik-haftasi-veri-dogrulama]]. Veri kaynağı: [[statik-icerik-api-migrasyonu]].
