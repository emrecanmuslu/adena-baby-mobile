# CLAUDE.md — Adena Baby (Flutter Mobil)

Bu dosya, bu dizinde çalışan Claude Code'a rehberlik eder. Talimatlara uy.

## Genel Bakış
"Adena Baby" bebek bakım takip uygulamasının mobil istemcisi. **Flutter**, **Android-öncelikli** (iOS sonra Mac/CI ile). Tüm UI Türkçe. Backend: `../api` (Django REST, `../API_SOZLESME.md`). Tasarım referansı: `../design/Adena Baby - Standalone.html` + `../TASARIM_PROMPT.md` (onaylı palet/yerleşim — yeniden icat etme, uygula).

## Geliştirme

Flutter PATH'te değilse tam yol: `/c/src/flutter/bin/flutter` (3.44.1 stable).
```bash
flutter pub get
flutter analyze            # her değişiklikten sonra çalıştır, temiz tut
flutter test
flutter run -d <device>
flutter build apk --debug  # Android hattını doğrula
```

### Cihaz — MuMuPlayer (AVD yavaş kaldı)
```bash
# adb: ~/AppData/Local/Android/Sdk/platform-tools/adb.exe
adb connect 127.0.0.1:7555     # veya 16416 → cihaz "emulator-5556" (SM-A5560, Android 12, x86_64)
adb devices
flutter run -d emulator-5556
```
Ekran görüntüsü ile UI doğrulama: `adb -s emulator-5556 exec-out screencap -p > /tmp/s.png` sonra oku.

### ⚠️ Backend'e bağlanırken (KRİTİK)
- **MuMu host PC'ye `10.0.2.2` ile ULAŞAMAZ** (o sadece AOSP/AVD emülatörü için). MuMu → `lib/core/config.dart` `apiBaseUrl` = **PC'nin LAN IP'si** (`ipconfig` → IPv4, ör. `http://192.168.1.X:8000/api/v1`).
- **AVD** kullanılırsa `http://10.0.2.2:8000/api/v1` doğru.
- `--dart-define=API_BASE_URL=...` ile override edilebilir.
- http:// kullandığımız için **Android cleartext izni** gerekir (debug manifest `usesCleartextTraffic=true` veya network_security_config).
- Backend açık olmalı: `cd ../api && ./.venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000`.

## Mimari / Stack
- **State:** flutter_riverpod 3.x (ProviderScope kökte)
- **Routing:** go_router (oturum yoksa giriş, varsa ana sayfa)
- **HTTP:** dio — `lib/core/api_client.dart` (JWT interceptor + 401'de otomatik refresh)
- **Token:** flutter_secure_storage — `lib/core/token_storage.dart`
- **Offline DB:** drift (+ sqlite3_flutter_libs) — yerel kayıt + sync (build_runner codegen)
- **Bağlantı:** connectivity_plus (online/offline algısı → sync tetikleme)
- **UUID:** uuid (istemci-üretimli id; backend ile aynı)

```
lib/
  core/
    theme.dart          — AppColors (mercan #FF8A7A / şeftali / kategori renkleri), AppTheme açık+koyu
    config.dart         — apiBaseUrl
    api_client.dart     — Dio + JWT + refresh
    token_storage.dart  — secure storage
  main.dart             — ProviderScope + MaterialApp + tema
  (eklenecek: models/, data/ (repository+drift), features/ (auth, home, records, timeline...), router.dart)
```

## Konvansiyonlar
- **Offline-first:** kayıtlar yerelde (drift) tutulur, istemci-üretimli UUID ile; online olunca `/sync` (delta, son-yazan-kazanır). UI yerel DB'yi dinler (reaktif), sync arka planda.
- **UI Türkçe**, palet `AppColors`'tan, sıcak/minimalist. Navigasyon: 3 sekme (Ana Sayfa·Günlük Akış·Grafikler) + merkez (+); ayarlar sağ üst profil.
- **İki mod:** bekleme (gebelik) / takip (doğmuş) — bebek `status` alanına göre.
- Build: `android/app/build.gradle.kts` — compileSdk/targetSdk=36, minSdk=Flutter varsayılanı (Android 6.0 hedefi). applicationId `com.adenababy.adena_baby`.

## Durum
Tamamlanan + sıradaki adım için bkz. **`../DURUM.md`**. Şu an temel (tema/api client/token/config/splash) kuruldu, MuMu'da çalışıyor; sıradaki: **auth dikey dilimi** (modeller + repository/provider + go_router + giriş/onboarding ekranları).
