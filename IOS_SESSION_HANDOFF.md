# iOS Oturum Devri (Handoff) — Mac'te Claude Code için

> Bu dosya, Windows'taki Claude oturumundan Mac'teki yeni oturuma bağlam aktarımı içindir.
> Mac'te yeni Claude Code oturumu açıldığında **ilk iş bu dosyayı oku.** İş bitince silinebilir.
> **İletişim dili: Türkçe. Adımları TEK TEK ver, kullanıcı "sonraki adım" demeden devamını yazma.**

## Proje
- **Adena Baby** — bebek bakım/takip uygulaması. Flutter mobil istemci (`~/Desktop/baby-app/mobile-app`), backend `../api` (Django). UI Türkçe + İngilizce. Bundle id: **`com.adenababy.adenaBaby`**.
- Repo: `github.com/emrecanmuslu/adena-baby-mobile`, branch **main**. İki klon var: Windows ve bu Mac. (Mac SSH deploy key ile klonlanmıştı: `~/.ssh/adena_mobile_deploy`.)

## Ortam (önemli)
- Windows host üstünde **macOS 15 VM** (VMware), **GPU yok**.
- Xcode **16.4**, Flutter **3.44.2** (`/usr/local/bin/flutter`).
- ⚠️ **iOS Simülatörü bu VM'de Flutter'ı ÇİZEMİYOR** (Metal yok → "Software rendering is incompatible with Impeller" → kapkara ekran). Impeller'ı kapatmak da çözmedi. **Simülatör kullanılmıyor.** Uygulama testi kullanıcının **fiziksel iPhone 15 Pro'sunda** yapılacak (orada sorunsuz çalışıyor). VM yalnız Xcode + build için.

## Şu anki görev: iOS native push + "son beslenme" widget'ı — SADECE ÜCRETSİZ KISIM
Kullanıcı kararı: 99 USD GEREKTİRMEYEN işler şimdi (kodu yaz + derlensin). **App Group veri paylaşımı + APNs/Push + widget'ın gerçek-cihaz testi → 99 USD Apple Developer üyeliği ister** (ücretsiz hesap App Group capability'sini desteklemez). Plan: kod hazır olsun, üyelik alınınca capability'ler eklenip gerçek cihazda test edilecek.

## Şu ana kadar YAPILANLAR (hepsi push'lu, son commit `5d7aa72`)
1. **GoogleService-Info.plist** Runner'a eklendi (Firebase proje `adena-baby-e71ba`). Dosya **`.gitignore`'da** (API anahtarı içerir) — repoda yok, sadece yerelde `ios/GoogleService-Info.plist`.
2. **FeedWidget Widget Extension target'ı** Xcode 16 ile oluşturuldu. Xcode 16 **PBXFileSystemSynchronizedRootGroup** (senkron klasör) kullanıyor → `ios/FeedWidget/` içindeki dosyalar otomatik derlenir, pbxproj'da tek tek file-ref yok (dosya ekle/sil serbest).
3. **`ios/FeedWidget/FeedWidget.swift`** = "son beslenme" widget'ı. `@main` `FeedWidgetBundle.swift`'te. Kullanılmayan `FeedWidgetControl.swift` silindi.
4. Widget extension **deployment target 18.5 → 15.0**.
5. **Build cycle düzeltmesi** (commit `5d7aa72`): Runner build phases'te **"Embed Foundation Extensions" → "Thin Binary" ÖNCESİNE** alındı (flutter/flutter#135056). Önceki build hatası buydu: *"Cycle inside Runner; building could produce unreliable results"*.

### Widget veri sözleşmesi (`lib/core/widget_service.dart`)
- App Group: **`group.com.adenababy.adena_baby`**
- Anahtarlar: `baby_name` (String), `last_feed_ms` (String — epoch ms; `"-1"` = kayıt yok)
- `iOSName: 'FeedWidget'` → widget `kind` ile birebir aynı olmalı (öyle).
- Tasarım rengi mercan **#FF8A7A**.

## DURUM: ÜCRETSİZ AŞAMA TAMAM ✅ (2026-06-17)
- `git pull` çakışması `git stash` + `git pull` ile aşıldı (cycle-fix `5d7aa72` çekildi).
- **`flutter build ios --simulator --no-codesign` BAŞARILI:** `✓ Built build/ios/iphonesimulator/Runner.app`. Build cycle çözüldü, FeedWidget extension dahil her şey derleniyor.
- Temizlik: dangling `git stash` varsa `git stash drop` ile at (artık gerekmez, pbxproj git'ten geldi).
- Not: `flutter build ios --simulator` simülatörü AÇMAZ, sadece imzasız derleme kontrolüdür (bu VM'de simülatör zaten çizemiyor).

Ücretsiz yapılabilecek her şey bitti. Bundan sonrası (aşağıdaki "99 USD'ye kalan") üyelik + gerçek cihaz ister.

## 99 USD'YE KALAN (üyelik alınınca)
- Runner + FeedWidget hedeflerine **App Group `group.com.adenababy.adena_baby`** capability.
- **APNs Auth Key (.p8)** → Firebase Console → Cloud Messaging'e yükle.
- Runner'a **Push Notifications + Background Modes (Remote notifications)** capability.
- Gerçek iPhone 15 Pro'da kurulum (imzalama: Team seç) + widget'ın veriyi göstermesi + push alımı testi.
- (Ayrı) iOS Google login client id → `dart_defines.json` GOOGLE_IOS_CLIENT_ID + backend GOOGLE_CLIENT_IDS.

## Genel kurallar
- Türkçe konuş. Adımları tek tek ver. Asla otomatik deploy etme (web/cloud'a yalnız "deploy et" denince).
- `flutter analyze` temiz tutulur; Android tarafı zaten tamam (push + ana ekran widget'ı Android'de çalışıyor), iOS native kabuk kalıyordu.
