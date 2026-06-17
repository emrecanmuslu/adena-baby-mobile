---
name: manuel-test-tercihi
description: Analyze sonrası APK build+adb install otomatik; UI tap/screencap otomasyonu yok, uygulamayı kullanıcı açıp manuel test eder
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 3c1c5505-1248-4e5e-a584-059ca945608e
---

Flutter/cihaz testlerinde adb ile UI otomasyonu (input tap/text + screencap + ekran görüntüsü analizi) YAPMA. Bunun yerine kullanıcıya **ne test edeceğini adım adım söyle**, manuel yapsın.

**Why:** Sürekli koordinat seçip input yazdırmak, ekran görüntüsü alıp analiz etmek gereksiz çok token tüketiyor (her ss ~bin token + kararsız, klavye/stylus panelleri yüzünden tekrar gerekiyor).

**How to apply:** Kod + `flutter analyze` + (varsa) widget/unit testleri ben çalıştırırım; uçtan uca/UI doğrulamasını "şu ekranda şunu yap, şunu görmelisin" listesiyle kullanıcıya bırak. Otomatik ss almak yerine gerekirse kullanıcıdan ss iste.

**Build/yükleme akışı (2026-06-11 güncelleme):** Her `flutter analyze` TEMİZ geçtikten sonra OTOMATİK olarak `flutter build apk --debug` alıp `adb -s emulator-5556 install -r` ile emülatöre yükle. Yani APK build + `adb install` artık İSTENEN otomasyon (önceki "adb otomasyonu yapma" sadece UI tap/text/screencap otomasyonu için geçerli). Uygulamayı `flutter run`/launch ile AÇMA — kullanıcı uygulamayı kendisi açıp manuel test eder.

**PEKİŞTİRME (2026-06-11, kullanıcı tekrar hatırlattı):** screencap/ekran görüntüsü alma + input tap ile UI sürme YAPMA — kullanıcı açıkça "ss al / ekranı göster" demedikçe. Build+install yeter; doğrulamayı kullanıcı kendisi yapar. (Bu oturumda dark mod doğrulaması için fazla ss alındı; kullanıcı uyardı.)
