---
name: firebase-app-distribution
description: Android test build dağıtımı Firebase App Distribution ile (USB/adb yerine); iOS TestFlight Mac sonrası
metadata: 
  node_type: memory
  type: project
  originSessionId: ef7a7f33-2d05-4062-890d-05d9db01501e
---

2026-06-16 kuruldu: fiziksel cihaza her seferinde USB/adb ile kurmak yerine **Firebase App Distribution**. Tester'lar e-posta + "App Tester" uygulaması ile bildirim alır, tıklayıp kurar/günceller.

**Karar gerekçesi:** Kullanıcı mağaza-benzeri kolay güncelleme istedi ama henüz kullanıcı yok → production track gereksiz/yavaş (Play bireysel hesapta ~12 tester/14 gün kapalı test zorunlu; iOS review gün alır). App Distribution = review yok, public değil, ekstra iş yok (aynı APK farklı kanal). Manuel adb ile production arası orta yol.

**Kurulum (hazır):**
- Script: `mobile-app/scripts/distribute-android.sh ["sürüm notu"]` → release APK build (cloud API'ye dart-define) + `firebase appdistribution:distribute`.
- Firebase projesi `adena-baby-e71ba`, Android app id `1:160566700344:android:5a4f7f9d13923ee4f8f9cd`, package `com.adenababy.adena_baby`.
- Firebase CLI 15.x kurulu + login yapılmış (bu makinede). `firebase appdistribution:distribute` ilk çağrıda App Distribution'ı otomatik provision etti (öncesinde `testers:list` 404 dönüyordu — normal, henüz build yüklenmemişti).
- Varsayılan tester `emrecan.muslu@gmail.com` (script TESTERS env veya virgüllü liste ile çoğaltılır). İlk release 1.0.0(1) dağıtıldı.
- Build cloud API'ye bağlanır: `API_BASE_URL=https://api.adenababy.com/api/v1` (herkesçe güvenilir TLS — Google Trust Services; [[cloud-deploy-hetzner]]).

**Bilinen sınırlar test build'inde:** sosyal giriş / IAP / reklam token'ları boş → o akışlar pasif, e-posta girişi + çekirdek takip çalışır ([[entegrasyon-bekleyen-tokenlar]]). Release imzası hâlâ debug keystore (YAYIN #1) — App Distribution için sorun değil, mağaza yüklemesi öncesi upload keystore gerekir.

**iOS:** TestFlight ile yapılacak — Mac kurulduktan sonra (GoogleService-Info.plist + entitlements + APNs; [[ios-push-widget-kalanlar]]). Mevcut `.github/workflows/ios.yml` (api_base_url varsayılanı api.adenababy.com) temel alınabilir.

İlgili: [[yayin-eksikleri-checklist]] [[platform-paritesi]]
