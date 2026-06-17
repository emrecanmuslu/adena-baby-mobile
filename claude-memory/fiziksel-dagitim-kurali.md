---
name: fiziksel-dagitim-kurali
description: "Fiziksel cihaza dağıtım kuralı: yalnız kullanıcı açıkça isteyince; her seferinde versiyon artır + App Distribution & TestFlight"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: ef7a7f33-2d05-4062-890d-05d9db01501e
---

Fiziksel cihazlara (Firebase App Distribution / TestFlight) build göndermek **YALNIZCA kullanıcı açıkça "fiziksel cihazlara gönderelim" (veya eşdeğeri) deyince** yapılır. Asla proaktif/otomatik dağıtma — analyze temiz olsa bile kendiliğinden gönderme. (Cloud/web için [[deploy-yalniz-acik-talimatla]] ile aynı ilke.)

**Why:** Kullanıcı dağıtımı kontrol etmek istiyor; her release tester'lara bildirim/güncelleme tetikler, istenmeden gitmemeli.

**How to apply — kullanıcı dağıt deyince sırasıyla:**
1. **Versiyon artır** — `mobile-app/pubspec.yaml` `version: X.Y.Z+B` (şu an `1.0.0+1`):
   - **Build numarası `+B`: HER seferinde +1** (App Distribution/store monoton artan build no ister; aksi halde yükleme reddedilir veya çakışır).
   - **Semantik `X.Y.Z`: işin kapsamına göre BEN belirlerim** — patch(Z)=hata düzeltme/küçük rötuş, minor(Y)=yeni özellik/kayda değer değişiklik (Z→0), major(X)=büyük kilometre taşı/kırıcı (Y,Z→0).
2. **Android:** `cd mobile-app && bash scripts/distribute-android.sh "<sürüm notu>"` ([[firebase-app-distribution]]) — release APK build (cloud API) + dağıtım.
3. **iOS:** TestFlight'a gönder (Mac/CI hazır olunca; `.github/workflows/ios.yml` api.adenababy.com ile). [[ios-push-widget-kalanlar]] [[platform-paritesi]]
4. **Sürüm notu** o build'de yapılan işi özetler (tester'lar görür).

[[platform-paritesi]] gereği ide'de iki kanala da (App Distribution + TestFlight) gönderilir; iOS tarafı Mac kurulana kadar yalnız Android yapılır, bu durumu kullanıcıya hatırlat.
