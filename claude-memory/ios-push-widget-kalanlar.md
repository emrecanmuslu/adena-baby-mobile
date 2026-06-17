---
name: ios-push-widget-kalanlar
description: "iOS için kalan işler (Mac gerektirir) — FCM push receive + WidgetKit \"son beslenme\" widget'ı"
metadata: 
  node_type: memory
  type: project
  originSessionId: b2080594-578c-4612-bf0c-867ab8072471
---

Android push + ana ekran widget'ı TAMAM (bkz. [[home-screen-widget-backlog]]). Backend ve ortak Flutter kodu iki platform için de hazır. **iOS'ta kalan tek şey native kabuk — Mac + Xcode gerekir, sonraya bırakıldı (2026-06-13).**

**KARAR (2026-06-14):** Sanal Mac kurulumu ŞİMDİLİK ERTELENDİ — önce uygulamanın geri kalanı tamamlanacak, iOS native kabuk + sanal Mac sonra. **Maliyet netliği:** Bu iOS işlerinin (App Group + Widget veri paylaşımı + Push/APNs) **ÜÇÜ DE Apple Developer Program (99 USD/yıl) gerektirir** — sadece push değil. Ücretsiz Apple ID ("free provisioning") ile fiziksel cihazda yalnız genel uygulama + local notification test edilir (7 günde bir yeniden imza); App Group/Widget-data/Push ücretli hesap olmadan gerçek cihazda ÇALIŞMAZ. iOS push'un Firebase üstünden gitse bile sonunda APNs'e teslim olması Apple'ın zorunluluğu (Android'de FCM tek başına yeterli, iOS'ta değil). Plan: kodu yaz, 99 USD üyelik yayına çıkarken alınınca App Group/Widget/Push gerçek cihazda aktif edilip test edilecek. Donanım: Windows laptop i7-7700HQ (Intel, VT-x açık, 34GB RAM, VM D: sürücüsüne — C: dolu); sanal Mac yolu uygun ama GPU hızlandırma yok + fiziksel iPhone USB passthrough sancılı.

**Yapılacaklar (Mac'te):**
1. **Firebase iOS config:** `GoogleService-Info.plist`'i Firebase Console'dan indir (proje `adena-baby-e71ba`, iOS bundle id ile) → Xcode'da Runner target'ına ekle.
2. **APNs:** Apple Developer → Keys → APNs Auth Key (.p8) oluştur → Firebase Console → Cloud Messaging → APNs anahtarı olarak yükle.
3. **Xcode capabilities (Runner):** Push Notifications + Background Modes → Remote notifications (+ Background fetch opsiyonel).
4. **App Group:** Hem Runner hem Widget extension'a `group.com.adenababy.adena_baby` (WidgetService.dart bu id'yi kullanıyor; `HomeWidget.setAppGroupId` ile eşleşmeli).
5. **WidgetKit extension `FeedWidget`:** Xcode'da Widget Extension target ekle (adı `FeedWidget` — WidgetService.updateWidget iOSName ile eşleşir). SwiftUI view: paylaşımlı UserDefaults(suiteName: app group)'tan `baby_name` + `last_feed_ms` (String) oku, "Son beslenme · X önce" göster (mercan #FF8A7A). TimelineProvider ile periyodik yenile.
6. **Push receive iOS tarafı:** firebase_messaging zaten ekli; iOS'ta `requestPermission` + APNs token otomatik. Arka planda data+content-available ile `handlePushMessage` çalışır (backend zaten iOS'a alert+content-available gönderiyor). Test: gerçek cihaz (simülatörde push sınırlı).
7. (Ayrı konu) iOS Google login client id → `dart_defines.json` GOOGLE_IOS_CLIENT_ID + backend GOOGLE_CLIENT_IDS.

**Build:** `flutter build ipa --release --dart-define-from-file=dart_defines.json --dart-define=API_BASE_URL=https://91.99.19.82.sslip.io/api/v1`

Android'de doğrulanan davranışlar iOS'ta gerçek cihazla yeniden test edilmeli (özellikle terminated-state widget güncelleme).

**ASIL KÖK NEDEN + ÇÖZÜM (2026-06-13, commit 95a4b90):** `ios/Runner.xcodeproj/project.pbxproj` daha önce SPM'e migrate edilmiş ve `FlutterGeneratedPluginSwiftPackage` referansları (XCLocalSwiftPackageReference / XCSwiftPackageProductDependency / packageReferences / packageProductDependencies / Frameworks build file) COMMIT'liydi. Bu yüzden `flutter config --no-enable-swift-package-manager` flag'i tek başına işe yaramıyordu — Xcode proje dosyasındaki ref'ler SPM çözmeye zorluyordu (önce firebase_messaging-16.3.0 SourcePackages rsync, downgrade sonrası firebase_core-3.6.0 SPM manifest `firebase_sdk_version.rb` fileNotFound). ÇÖZÜM: pbxproj'tan TÜM SPM ref'leri Python ile çıkarıldı (13 occurrence + 2 section) → proje CocoaPods kullanır + `ios/Podfile` (platform 13.0) eklendi + CI'da SPM flag pub get'ten ÖNCE kapatıldı (yeniden migrate olmasın). Artık SPM tamamen devre dışı, tüm plugin'ler CocoaPods podspec'iyle derlenir. firebase downgrade (3.6.0/15.1.3) hâlâ pinli ama SPM kapalı olduğu için aslında 16.3/4.10 da CocoaPods'la çalışırdı (gerekirse ileride yükseltilebilir). Kullanıcı CI'yı tekrar çalıştırıp doğrulamalı.
- **commit 549b42e:** CocoaPods'a geçince `pod install` deployment target ≥14.0 istedi → IPHONEOS_DEPLOYMENT_TARGET 13.0→**15.0** (pbxproj 3 yer + Podfile platform + post_install).
- **commit 2909998:** Swift derleme hatası `FIRAllocatedUnfairLock<()>` / "Argument passed to call that takes no arguments" (FirebaseCoreInternal HeartbeatStorage.swift) → Firebase SDK Swift 6 `sending` anahtar kelimesi kullanıyor, **Xcode 16+ (Swift 6) şart**. macos-14 runner = Xcode 15.4 (Swift 5). CI `runs-on: macos-14`→**macos-15** (Xcode 16). Ref: firebase/flutterfire#17496. Alternatif (gerekirse): Firebase SDK'yı `sending` öncesi sürüme pinle.

**(eski, kısmi) ÇÖZÜM (commit 4e25166):** Gerçek neden — `firebase_messaging 16.3.0`'ın SPM (`Package.swift`) paketi macOS CI'da `rsync mkdir SourcePackages failed` veriyordu. Mevcut diğer SPM pluginleri (share_plus, home_widget, sign_in_with_apple, flutter_local_notifications, google_sign_in) zaten Package.swift taşıyor ve sorunsuz derleniyordu → SPM'in kendisi değil, bu spesifik paket sorunlu. Çözüm: **firebase_messaging 15.1.3 + firebase_core 3.6.0** (messaging 15.1.3 Package.swift TAŞIMAZ → CocoaPods kullanılır; core 3.6.0 SPM ama diğerleri gibi sorunsuz). Her ikisi de iOS 13.0 ister (proje zaten 13.0). Önceki başarısız deneme (bca4d93: SPM-disable adımı + Podfile + 15.0) GERİ ALINDI — işe yaramamıştı. pubspec'te EXACT pin (caret değil) → yanlışlıkla SPM'li sürüme dönmesin. Android debug build doğrulandı, push API'leri 15.x'te aynı. Kullanıcı workflow_dispatch'i tekrar çalıştırıp doğrulamalı (Mac yok, yerel test edilemedi).
NOT (eski, geçersiz deneme):  Hata `rsync: mkdir SourcePackages/firebase_messaging-16.3.0 failed` (Flutter 3.44.1 + Firebase SPM bug) + Firebase iOS SDK 15.0 ister ama proje 13.0'daydı. Çözüm (Mac gerektirmeden, runtime Firebase işini açmadan):
- `.github/workflows/ios.yml`: build'den önce `flutter config --no-enable-swift-package-manager` → CocoaPods kullanılır (podspec'ler mevcut). SPM tamamen atlanır.
- `ios/Podfile` eklendi: `platform :ios, '15.0'` + post_install tüm pod'ları 15.0.
- `ios/Runner.xcodeproj/project.pbxproj`: IPHONEOS_DEPLOYMENT_TARGET 13.0→15.0 (3 yer).
- ⚠️ Mac'te DOĞRULANMADI (yerel Mac yok) — kullanıcı workflow_dispatch'i tekrar çalıştırıp doğrulamalı. Kök nedenleri hedefliyor, yüksek güven ama garanti değil.
- NOT: GoogleService-Info.plist HÂLÂ yok → iOS'ta Firebase runtime çalışmaz (Firebase.initializeApp try/catch'li, app çöker değil). Build + sideload testi çalışır; iOS PUSH yine de Mac kurulumunu bekler (yukarıdaki 1-6).
