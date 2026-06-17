---
name: home-screen-widget-backlog
description: "Backlog — Android/iOS ana ekran (home screen) widget'ı, \"son beslenme\" göstergesi için kullanıcı talebi"
metadata: 
  node_type: memory
  type: project
  originSessionId: b2080594-578c-4612-bf0c-867ab8072471
---

Kullanıcı (2026-06-13) telefon ana ekranına konulan Android/iOS **home screen widget** istiyor: özellikle **"son beslenme"** bilgisini göstersin (ne zaman, kaç saat önce vb.).

**DURUM (2026-06-13 ilerleme):**
- ✅ **Backend push katmanı YAPILDI**: `apps/common/push.py` (FCM, firebase-admin, arka plan thread, FIREBASE_CREDENTIALS yoksa no-op, UNREGISTERED token temizliği, Android data-only / iOS alert+content-available). Bağlandığı yerler: `records/views.py log_activity` → aile etkinliği (beslenme ise widget verisi taşır: `widget_update=feed`, `last_feed_ts`); `community/views.py` AnswerCreateView (soru sahibine) + BestAnswerView (cevap sahibine). settings'e `FIREBASE_CREDENTIALS` env, `firebase-admin` requirements+venv. `manage.py check` temiz.
- ✅ **Android widget YAPILDI+kuruldu**: `home_widget ^0.9.3`; `lib/core/widget_service.dart`; `notification_sync.dart` içinde `_WidgetSync` (aktif bebek son beslenme, foreground reaktif); native `FeedWidgetProvider.kt`+layout/xml/drawable/strings+manifest receiver. Debug APK derlendi+emulator-5554'e kuruldu. Dokununca uygulamayı açar. App group id: `group.com.adenababy.adena_baby`.
- ✅ **Android push ALMA YAPILDI+kuruldu (2026-06-13)**: Firebase projesi `adena-baby-e71ba`. `google-services.json` → android/app/ (kullanıcı koydu). Servis hesabı → `api/firebase-credentials.json` (gitignore'lu), `api/.env` `FIREBASE_CREDENTIALS` set; `push._get_app()` init OK doğrulandı. gradle `com.google.gms.google-services` 4.4.2 eklendi. Flutter: `firebase_core 3.6.0`+`firebase_messaging 15.1.3` (16.3/4.10'dan düşüldü — iOS CI SPM rsync bug'ı, bkz [[ios-push-widget-kalanlar]]; exact pin), `lib/core/push_service.dart` (top-level bg handler + ortak `handlePushMessage`: widget güncelle + `showActivity` ile yerel bildirim; iOS'ta APNs gösterdiyse tekrar gösterme; aile-etkinliği opt-in `ActivityNotifCache.enabled()` ile gated + cursor ilerlet → polling ile çift bildirim önleme). main.dart: `Firebase.initializeApp()`+`onBackgroundMessage`, `startForeground()`, oturum açılınca `registerToken` (`/me/devices`). Tam APK derlendi+emulator-5554'e kuruldu.
  - ⚠️ Sunucu: `.env` değişti → çalışan runserver/gunicorn FIREBASE_CREDENTIALS için RESTART gerekir (environ startup'ta okur). Hetzner'da da `.env`+restart.
  - ⚠️ Doğrulanmamış (cihazda test): terminated-state'te background isolate'ta `home_widget` method channel kayıtlı olmayabilir → widget güncellemesi düşebilir (try/catch'li, çökmez); bildirim gösterimi çalışmalı. İki hesap/cihazla gerçek test gerek.
- ⏳ **BEKLEYEN — iOS** (Mac gerekir): `GoogleService-Info.plist` Runner'a; WidgetKit extension `FeedWidget` (SwiftUI) + App Group `group.com.adenababy.adena_baby`; APNs Auth Key (.p8) → Firebase; Xcode Push Notifications + Background Modes capability. iOS client id → backend GOOGLE_CLIENT_IDS (ayrı konu).

**Xiaomi/MIUI widget seçicide görünmüyordu (2026-06-13, commit 96fb633):** Release APK'da receiver doğru kayıtlıydı (R8 elememişti, minify zaten kapalı) ama `feed_widget_info.xml`'de önizleme yoktu. MIUI/HyperOS launcher önizlemesiz (previewImage/previewLayout) app widget'larını seçicide GÖSTERMEZ. Çözüm: `android:previewLayout="@layout/feed_widget"` + `android:previewImage="@mipmap/ic_launcher"` eklendi. Genel Android 12+ best-practice de bu.

**Bildirim mimarisi kararı (2026-06-13):** Zaman-bazlı hatırlatıcılar (beslenme/randevu/aşı/süren sayaç/sessiz saat) YEREL kalır (çevrimdışı + kesin zamanlama + sunucu yükü yok). Yalnız cihazın bilemeyeceği olaylar push olur: aile etkinliği + topluluk. [[suren-sayac-bildirimi]] [[hatirlatici-sistemi]] [[bakici-bildirim-paylasim-2026-06-13]]

**Kararlar (2026-06-13 görüşme):**
- Widget'a dokununca → **uygulamayı açar** (hızlı kayıt değil, v1).
- Güncelleme kapsamı: **yalnız uygulama açık/önplandayken** widget güncellenir (mevcut polling ile). Çapraz-cihaz anlık senkron (Z ekler → Y'nin widget'ı anında) ŞİMDİLİK YOK.
  - Yol A (arka plan polling / workmanager) ve Yol B (push) tartışıldı, ikisi de şimdilik ertelendi.
- FCM maliyeti soruldu: **FCM mesaj gönderimi tamamen ücretsiz** (limitsiz, mesaj başı ücret yok); APNs de ücretsiz; Apple Developer $99/yıl zaten App Store için gerekli. Gerçek bedel = geliştirme eforu (~1-1.5g). Saf Messaging → Firebase Spark (free) planında kalır; Firestore/Functions/Storage'a bulaşmazsan Blaze gerekmez. Backend'de Device.push_token + ActivityEvent ("push beslemesi") iskelesi zaten hazır.

**Teknik notlar (konuşurken değerlendir):**
- Flutter'da native widget gerekir; `home_widget` paketi standart yol (Android App Widget + iOS WidgetKit köprüsü). Native taraf (Kotlin AppWidgetProvider + Swift WidgetKit/SwiftUI) yazılması şart, salt-Dart değil.
- Veri köprüsü: uygulama son beslenme kaydını paylaşılan depoya yazar (Android SharedPreferences / iOS App Group UserDefaults), widget oradan okur.
- Güncelleme: kayıt eklenince widget refresh tetiklenir; periyodik "X saat önce" için widget kendi zamanlayıcısı.
- [[platform-paritesi]] gereği iki platformda da tasarlanmalı.
- [[suren-sayac-bildirimi]] (uyku/emzirme bildirimi) ile veri kaynağı örtüşür — son beslenme zamanı zaten mevcut.
