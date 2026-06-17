---
name: entegrasyon-bekleyen-tokenlar
description: "Test aşaması — Google/Apple login, reklam, ödeme entegrasyonlarının durumu ve dış token/native bekleyen işleri"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0773296e-97a8-4e55-a562-5d4b11012c11
---

Test aşaması kararı (2026-06-13): Google iOS login, reklam ve ödeme **şimdilik bırakıldı**; lansman/ücretli hesap zamanı tamamlanacak. Mevcut durum — "token alınacak" varsayımı login+ödeme için doğru ama **reklam için değil** (SDK henüz yok).

## Google login — kod TAM
- Web client ID `dart_defines.json`'da + backend `.env GOOGLE_CLIENT_IDS`'te (eşleşti). Android client ID alındı.
- **Android'in çalışması için:** debug SHA-1 `C1:C9:F0:80:38:EE:8E:A0:07:5B:0F:78:98:FF:E4:37:C4:2A:39:24` Google Cloud Android OAuth client'ına eklenecek (release/Play App Signing SHA-1 de lansmanda). Build: `scripts/run.sh apk` (= `--dart-define-from-file=dart_defines.json`).
- **iOS için EKSİK:** iOS client ID alınmadı + `ios/Runner/Info.plist`'e REVERSED_CLIENT_ID URL scheme eklenecek. `dart_defines.json GOOGLE_IOS_CLIENT_ID` boş.

## Apple (iCloud) login — kod TAM
- iOS native akış hazır (`social_auth_service.dart`). EKSİK: **ücretli Apple Developer** ($99/yıl) + App ID'de "Sign in with Apple" capability + Xcode'da Runner.entitlements + backend `.env`'de `APPLE_BUNDLE_IDS=com.adenababy.adenaBaby` (şu an yorumlu). iOS bundle = `com.adenababy.adenaBaby` (Android: `com.adenababy.adena_baby`).
- **Ücretsiz Apple ID + Sideloadly ile çalışmaz** (entitlement yetkilendirilemez) → ancak ücretli hesap + TestFlight/imza ile. Android'de Apple butonu Services ID kurulmadıkça gizli.

## Ödeme (RevenueCat) — kod TAM
- `purchases_flutter` entegre (`revenuecat_service.dart`: configure/purchase/restore/offerings). EKSİK sadece: RC public key'ler (`dart_defines.json REVENUECAT_ANDROID_KEY/IOS_KEY`) + RC dashboard'da ürün/abonelik tanımları. Boşken RC sessizce kapalı, premium yalnız backend'den okunur ([[para-kazanma-modeli]]).

## Reklam (AdMob) — ⚠️ ENTEGRASYON EKSİK (sadece token değil)
- `ad_service.dart` şu an **placeholder** (satır 97 TODO). `google_mobile_ads` paketi pubspec'te **YOK**. Yapılacak: paket ekle + InterstitialAd yükle/göster kodu + AdMob **app id**'sini AndroidManifest/Info.plist'e ekle + birim id'leri (`dart_defines.json ADMOB_*`). Yani burada token öncesi gerçek SDK işi var.

İlgili: [[oturum-durumu-fiziksel-test]] [[para-kazanma-modeli]] [[platform-paritesi]]
