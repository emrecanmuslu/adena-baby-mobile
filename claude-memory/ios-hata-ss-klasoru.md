---
name: ios-hata-ss-klasoru
description: "Kullanıcı 'ss aldım hataya bakar mısın' deyince → ios-erros klasöründeki EN SON eklenen görseli oku"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e51c6cff-6270-4246-90b0-fd1273406874
---

Kullanıcı "ss aldım hataya bakar mısın" (veya benzeri: ekran görüntüsü/hatayı paylaştım) dediğinde, her zaman `C:\Users\Dev\Desktop\baby-app\ios-erros` klasöründeki **en son eklenen** (en yeni mtime'lı) görseli Read ile aç ve incele.

**Neden:** macOS VM clipboard bozuk, kullanıcı host'a metin yapıştıramıyor; hata loglarını ekran görüntüsü olarak bu klasöre atıyor.

**Nasıl uygula:** `ls -t ios-erros/` ile en yeni dosyayı bul, onu Read et. "En son" = klasöre en son eklenen tek görsel. (Klasör adı `ios-erros` — kullanıcının yazımı.)
