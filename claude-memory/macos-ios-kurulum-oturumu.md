---
name: macos-ios-kurulum-oturumu
description: "macOS VM'de Flutter projeyi iOS simülatörde ayağa kaldırma — adım adım kurulum, kaldığımız nokta Adım 6"
metadata: 
  node_type: memory
  type: project
  originSessionId: 11d6645e-2365-4475-b3d4-2345e38687f8
---

Windows host üzerinde **macOS 15 (Sequoia) sanal makinesinde** Flutter mobil projeyi (adena-baby-mobile) iOS simülatörde çalıştırma kurulumu. Adım adım ilerliyoruz; kullanıcı her seferinde "adım N" deyince sıradaki adımı veriyorum.

**Ortam notları:**
- VM clipboard bozuk → host'tan paste düzgün çalışmıyor, satırları böler. Çözüm: komutları **elle yazdır** ya da tek satırlık komut ver.
- Ağ: NAT; başta 169.254 (DHCP başarısız) sorunu vardı, sonra düzeldi — internet çalışıyor.
- Xcode: macOS 26 gerektirdiği için en yeni sürüm kurulamadı; **Xcode 16.4** (macOS 15'e uyan en yüksek) developer.apple.com/download/all'dan indirildi, /Applications/Xcode.app'e açıldı. iOS kilit ekranı widget geliştirme 16.4'te sorunsuz.

**Tamamlanan adımlar:**
1. ✅ Xcode 16.4 indirildi + Applications'a açıldı (welcome ekranı geldi, proje oluşturulmadı)
2. ✅ Homebrew 6.0.2 kuruldu (PATH ~/.zprofile'a eklendi)
3. ✅ `brew install --cask flutter` + `brew install git cocoapods`
4. ✅ SSH **deploy key** ile klonlandı: `~/.ssh/adena_mobile_deploy` (passphrase'siz), public key repo `.../settings/keys`'e eklendi. `git config --global core.sshCommand "ssh -i ~/.ssh/adena_mobile_deploy -o IdentitiesOnly=yes"` ayarlandı; klon `git@github.com:emrecanmuslu/adena-baby-mobile.git` → `~/Desktop/baby-app/mobile-app`
5. ✅ `flutter pub get` + `flutter doctor` çalıştı. Chrome eksik (önemsiz, web içindir). Xcode satırı henüz tam değildi.

**TÜM ADIMLAR TAMAM (2026-06-17):** Adım 6'da sorun = Xcode `~/Downloads`'a `.xip` açılmış ama `/Applications`'a taşınmamıştı → `mv ~/Downloads/Xcode.app /Applications/` sonra `xcode-select -s`/`-runFirstLaunch`/`-license accept`/`-downloadPlatform iOS` → `flutter doctor` Xcode ✅ (Xcode 16.4, Flutter 3.44.2, macOS 15.5 darwin-x64). Android/Chrome ✗ önemsiz (bu Mac yalnız iOS). Adım 7: `flutter run` ilk denemede **SPM/Firebase hatası** verdi (`firebase_sdk_version.rb fileNotFound`) → `flutter config --no-enable-swift-package-manager` + `flutter clean` + `pub get` + `run` ile çözüldü; uygulama iPhone 16 Plus simülatöründe ayağa kalktı.

Simülatör tam yolu (open -a bulamazsa): `open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app`.

**ŞU ANKİ İŞ (2026-06-17):** iOS native push+widget'ın 99 USD GEREKTİRMEYEN kısmı (kullanıcı seçti). Bkz [[ios-push-widget-kalanlar]]. Yapılacak: (1) GoogleService-Info.plist indir+ekle (Firebase proje adena-baby-e71ba, bundle com.adenababy.adenaBaby), (2) WidgetKit FeedWidget extension kodu (App Group group.com.adenababy.adena_baby, key'ler baby_name + last_feed_ms String, mercan #FF8A7A). Push'un gerçek testi + APNs/App Group gerçek-cihaz 99 USD'ye kaldı.

**FEEDWIDGET İLERLEME (2026-06-17):** GoogleService-Info.plist Runner'a eklendi (bundle com.adenababy.adenaBaby, Firebase proje adena-baby-e71ba). FeedWidget Widget Extension target'ı Mac'te Xcode 16.4 ile oluşturuldu — Xcode 16 **PBXFileSystemSynchronizedRootGroup** (senkron klasör) kullanıyor → ios/FeedWidget/ içindeki dosyalar otomatik derlenir, pbxproj'da tek tek file ref YOK (dosya ekle/sil/değiştir serbest, pbxproj cerrahisi gerekmez). İş akışı: Mac'te commit+push → Windows'tan pull+düzelt+push → Mac'te pull. Yapıldı (commit 5b73881): FeedWidget.swift bizim 'son beslenme' kodu (@main FeedWidgetBundle.swift'te), FeedWidgetControl.swift silindi, deployment target 18.5→15.0, GoogleService takipten çıkıp .gitignore'a eklendi (geçmişte hâlâ var ama düşük riskli istemci anahtarı), Runner/Info.plist FLTEnableImpeller=false geri alındı. **BEKLEYEN:** kullanıcı Mac'te pull + GoogleService'i ios/'a geri kopyala + `flutter build ios --simulator --no-codesign` ile derlemeyi doğrula. Sonra App Group capability + gerçek-cihaz/push testi = 99 USD'ye kaldı.

**SİMÜLATÖR KULLANILMIYOR (2026-06-17 karar):** GPU'suz VM'de iOS Simülatörü Flutter'ı çizemiyor — Metal yok → "Software rendering is incompatible with Impeller" → kapkara ekran. `flutter run --no-enable-impeller` flag'i iOS'ta uygulanmadı; Info.plist `FLTEnableImpeller=false` (PlistBuddy) + `flutter clean` de çözmedi. Sonuç: bu VM'de simülatör testi terk edildi. **iOS testi kullanıcının fiziksel iPhone 15 Pro'sunda yapılacak (orada uygulama sorunsuz çalışıyor).** Mac VM yalnızca Xcode (kod yazma, target ekleme, build) için kullanılacak. NOT: widget App Group + push gerçek-cihaz testi yine 99 USD ister (free provisioning App Group capability'yi desteklemez); o yüzden ücretsiz aşamada hedef = kodu yaz + Xcode'da kur + derlensin, çalışma-anı testi 99 USD alınınca.

İlgili: [[ios-push-widget-kalanlar]] (Mac'te yapılacak push/widget işleri), [[oturum-durumu-fiziksel-test]]
