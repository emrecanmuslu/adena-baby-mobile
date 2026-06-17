---
name: navigasyon-kesfet-hub
description: "Alt menü 5. slotu = Keşfet hub'ı; Sağlık/Topluluk/Uzman Rehberi/Anılar oraya toplandı (IA kararı 2026-06-12)"
metadata: 
  node_type: memory
  type: project
  originSessionId: e71a7c63-04ee-4578-9c21-eacd349fcfe1
---

Kullanıcı UX değerlendirmesi sonrası alt menü/IA yeniden düzenlendi (2026-06-12). **Sorun:** Topluluk + Uzman Rehberi Sağlık Hub içine gömülüydü (2 kademe, "sağlık" değiller), Sağlık Hub hem alt menüde (❤️) hem Ayarlar'da tekrar ediyordu, Anılar yalnız Ayarlar'da gömülüydü.

**Karar = "Keşfet hub'ı" (kullanıcı bu seçeneği seçti):**
- Alt menü 5. slot: ❤️Sağlık → **✨/pusula Keşfet** (`compass` ikonu eklendi; `/discover`). Takip sekmeleri (Ana/Akış/➕/Grafik) dokunulmadı.
- Yeni ekran `features/discover/discover_screen.dart`: **Bebeğin Sağlığı** (→/health, bekleme modunda gizli) · **Topluluk** (→/community) · **Uzman Rehberi** (→/content) · **Anılar** (→/memories). adSec gruplu AdMenuItem'lar.
- Sağlık Hub'dan (`health_screen.dart`) Topluluk + Uzman Rehberi AdMenuItem'ları **kaldırıldı** (artık Keşfet'te; Sağlık Hub yine aşı/randevu/ateş&ilaç/gelişim/diş/hatırlatıcı).
- Ayarlar'dan (`settings_screen.dart`) **Sağlık Hub ve Anılar tekrarı kaldırıldı**. Bunun yerine **yalnız bekleme modunda** "Keşfet" kısayolu (compass) eklendi — çünkü bekleme modunda alt menü yok; takip modunda zaten ✨ slotu var (tekrar olmasın diye expecting-only).

**Sonuç:** Sağlık tekrarı bitti; Topluluk/İçerik/Anılar "sağlık değil" ama düzenli bir yuvada; tüm yüzeyler her iki modda erişilebilir. analyze temiz, APK emulator-5554'e kuruldu. bkz [[faz3-uzman-icerik-topluluk-plani]] [[tasarim-bilesen-kiti]]
