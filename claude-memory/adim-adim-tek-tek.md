---
name: adim-adim-tek-tek
description: "Kurulum/işlem adımlarını TEK TEK ver; kullanıcı 'sonraki adım' demeden devamını yazma"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e51c6cff-6270-4246-90b0-fd1273406874
---

Çok adımlı işlemlerde (özellikle iOS/Xcode/terminal kurulumu) adımları **tek tek** ver. Bir adımı yaz, dur, kullanıcının yapıp "sonraki adım" / "tamam" demesini bekle. Tek seferde tüm adımları sıralama.

**Neden:** Kullanıcının adımlar arasında soruları olabiliyor; topluca verilince soru sorma fırsatı kaçıyor ve kafa karışıyor.

**Nasıl uygula:** Her yanıtta yalnızca **bir sonraki tek adımı** ver + gerekirse o adıma dair kısa açıklama. Sonraki adımı ancak kullanıcı onaylayınca ver. (Genel planı bir kez özetlemek olur, ama yürütmeyi adım adım yap.)
