---
name: yayin-eksikleri-checklist
description: Mağaza yayını (TR+ABD) öncesi eksikler listesi; kök YAYIN_EKSIKLERI.md dosyasında tutuluyor
metadata: 
  node_type: memory
  type: project
  originSessionId: 4bcc597a-c6e1-4d61-8baa-e6a4eef269d9
---

2026-06-15 yapılan yayın hazırlık denetiminin (3 paralel ajan: teknik/yasal/UX) çıktısı `C:\Users\Dev\Desktop\baby-app\YAYIN_EKSIKLERI.md` dosyasında tutuluyor. Madde bitince **satır silinerek** ya da `[x]` ile kapatılıyor — güncel durum hep o dosyada.

Karar: uygulama özellik olarak olgun ama yayına hazır DEĞİL; eksikler özellik değil yayın hazırlığı + yasal belge kalemleri.

**2026-06-16 koddan DOĞRULANMIŞ durum** (madde no = YAYIN_EKSIKLERI.md):

KOD TARAFI BİTMİŞ (`[x]`) — yeniden yapma: #2 yasal sayfalar, #7 açık rıza, #8 yaş kapısı, #9 prod sertleştirme, #10 imzalı medya, #13 tıbbi feragat, #14 export, #15 hesap silme grace, #16 EN çeviri, #17 erişilebilirlik, #20 US/CDC aşı.

**Cloud deploy durumu (api git, son deploy = commit 263f88f):** CLOUD'DA CANLI → #2, #7, #8, #9, #13. CLOUD'A GİTMEMİŞ (263f88f'den sonraki commit'ler, kod tamam ama deploy bekliyor) → #10 imzalı medya (e76c843, ayrıca nginx `deny /media/(babies|memories)/` kuralı), #14 export + #15 hesap silme grace (86e6d2f, migrate 0008 + cron `purge_deleted_accounts`), #11 EN transparency (4e3cd8f), #20 US/CDC aşı (825eb2a/0967ed5/4ef89f8), #17 erişilebilirlik. Local tüm migration'lar uygulandı (#15 0008_user_deletion_requested_at bugün 2026-06-16 local'e migrate edildi). "deploy et" denince git pull + migrate + seed + nginx + cron yapılır.

GERÇEK BLOKLAYICILAR — hâlâ açık (kodda doğrulandı): **#1** Android release imzası debug keystore'da (`build.gradle.kts:36` getByName("debug"), key.properties YOK), **#5** iOS `.entitlements`+`GoogleService-Info.plist` YOK (Mac), **#6** mağaza varlıkları sıfır. Hepsi kullanıcı tarafında (keystore/Mac/asset) — kod tarafında bloklayıcı kalmadı.

**#4 prod API URL/TLS — ÇÖZÜLDÜ (2026-06-16):** `api.adenababy.com` canlı, Cloudflare arkası + herkesçe güvenilir cert (Google Trust Services), `/api/docs/` 200 · `/auth/me` 401. config.dart default'u local kalıyor (dev için) ama release/dağıtım build'leri `--dart-define=API_BASE_URL=https://api.adenababy.com/api/v1` kullanıyor (distribute script + iOS workflow). Eski sslip URL'i kapalı. [[cloud-deploy-hetzner]] [[firebase-app-distribution]]

KISMİ (kod tamam, dış adım kaldı): **#11** 3. taraf veri beyanı → Play Data Safety + App Store Privacy Labels formları, **#12** SCHEDULE_EXACT_ALARM manifest doğru → Play Console exact-alarm formu, **#18** RevenueCat anahtarları+store ürünleri, **#19** iOS izin EN `.strings` dosyaları VAR ama pbxproj'de bağlı değil (knownRegions=en+Base, tr yok; InfoPlist.strings variant bağlanmalı — Mac/Xcode).

**Yasal belgelerden başlama kararı (sonraki oturum):** Kullanıcı birey (şirketi yok); birey olarak iki mağazada yayın+gelir mümkün. Gizlilik politikasında ad+e-posta yeterli, adres/telefon TR+US için gerekmez (AB'ye satış olursa DSA gereği adres şart). TR'de mobil uygulama geliştirici gelir vergisi istisnası (GVK mük. 20/B) + özel banka hesabı seçeneği var → mali müşavire sorulacak; sağlık verisi olduğu için VERBİS gerekir mi de sorulacak. Google bireysel hesapta ~12 tester/14 gün kapalı test kuralı yayın takvimine eklenecek.

Planlanan belge seti (TR+EN): (1) Gizlilik Politikası = KVKK aydınlatma + CCPA/COPPA tek belge, (2) Kullanım Koşulları/EULA + tıbbi feragat, (3) kayıt ekranı açık rıza metni+checkbox, (4) backend rıza kaydı (kabul tarihi+belge sürümü). Barındırma /privacy /terms dil-duyarlı, app'ten url_launcher ile link. KARARLAR HENÜZ VERİLMEDİ: barındırma yeri (domain mi / GitHub Pages / test sunucu) + pazar kapsamı (TR+US mü AB de mi) + ad-soyad + iletişim e-postası kullanıcıdan alınacak. Kullanıcı "başlamadan önce yapılması gereken önemli işler var" deyip yeni oturuma erteledi.

İlgili: [[entegrasyon-bekleyen-tokenlar]] [[ios-push-widget-kalanlar]] [[para-kazanma-modeli]] [[oturum-durumu-fiziksel-test]]
