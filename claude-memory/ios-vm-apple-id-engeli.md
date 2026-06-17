---
name: ios-vm-apple-id-engeli
description: macOS VM'de Apple ID/iCloud/Xcode girişi sahte donanım kimliği yüzünden başarısız (Verification Failed); ücretsiz imzalama VM içinden imkânsız
metadata:
  type: project
---

macOS 15 VMware VM'de Apple ID girişi (iCloud System Settings + Xcode → Accounts) **"Verification Failed – an unknown error occurred"** ile başarısız oluyor. Hesap sağlam (appleid.apple.com'a 2FA ile girilebiliyor), ağ/TLS sağlam (idmsa/gsa/developerservices2/appstoreconnect hepsi HTTP 200), saat doğru.

**Kök sebep:** VM'in donanım kimliği geçersiz — `Model Identifier: VMware20,1`, `Serial: VMaC2GbubG9E` (sahte), `board-id: 0VPTXG`. Apple auth makineyi gerçek Apple donanımı olarak tanımıyor.

**Why:** Apple iCloud/GSA doğrulaması gerçek Apple SMBIOS (geçerli seri no + board-id + model) ister; varsayılan VMware kimlikleri bunu geçemez.

**How to apply:** Bu VM içinden Xcode'a Apple ID eklenemez → Personal Team seçilemez → ücretsiz imzalı cihaz kurulumu yapılamaz. İki çıkış yolu:
1. **Windows host'ta Sideloadly/AltStore** — Mac'te `flutter build ios --no-codesign` ile imzasız .app/.ipa üret, Windows'a taşı, iPhone'u Windows'a tak, Sideloadly ile ücretsiz Apple ID imzalayıp kur (VM donanım engelini atlar).
2. **VMware .vmx SMBIOS spoof** (host tarafı) — geçerli Apple `board-id`/`hw.model`/`serialNumber`/`MLB`/`ROM` değerleri ekle, yeniden başlat; sonra Xcode girişi normal çalışır. Daha "doğru" ama host tarafında işlem ister.

Bağlam: [[macos-ios-kurulum-oturumu]], [[platform-paritesi]], [[ios-push-widget-kalanlar]].
