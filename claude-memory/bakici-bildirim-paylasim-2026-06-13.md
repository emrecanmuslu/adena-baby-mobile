---
name: bakici-bildirim-paylasim-2026-06-13
description: Bakıcı sınırlı-yazma + aile etkinlik bildirimi + çok-bebek bildirim + çıkarılan üye temizliği (uygulandı)
metadata: 
  node_type: memory
  type: project
  originSessionId: 40f87d3b-4fdf-4bc9-a1bf-aebd177f4a73
---

2026-06-13'te tamamlanan paylaşım/bildirim işleri (analyze temiz + APK build geçti):

**Bakıcı (caregiver) = sınırlı yazma** — backend `babies/permissions.py` `can_full_write` (owner/parent). Kayıt: bakıcı ekler ama yalnız KENDİ kaydını düzenler/siler (detail + /sync conflict ile). Sağlık (aşı/milestone/diş/hatırlatıcı) + anı oluştur/düzenle/sil + anne takibi(MomEntry GET dahil) → owner/parent. Mobil: `Baby.canFullWrite/isCaregiver`; anı ekle/sil gizli, sağlık toggle'ları + diş sheet bakıcıya kapalı (toast), anne takibi ekranı bakıcıya "yalnız ebeveyn" mesajı, kayıt silme sheet'inde başkasının kaydına Sil yok.

**Aile/Paylaşım UI:** üye satırında rol değiştirme (Ebeveyn/Bakıcı yap) KALDIRILDI — rol davet anında sabit; sahip yalnız "Çıkar" yapar.

**Aile etkinlik bildirimi (opt-in, Yol A = polling+yerel, push YOK):** `ActivityNotifCache` (enabled + bebek başına lastSeen cursor), `FamilyActivityWatcher` (tüm bebekleri yoklar, başkasının eylemi → yerel bildirim, başlık=bebek adı). Backend `ActivityView ?since=` filtresi.
- **Toggle yeri (2026-06-14 güncellendi):** Ayarlar'dan ÇIKARILDI → artık **Aile/Paylaşım ekranında** (`members_screen.dart`, "Bildirimler" bölümü). Ayarlarda arama; orada yok.
- **Flood düzeltmesi (2026-06-14):** kapatıp tekrar açınca bayat cursor yüzünden biriken tüm geçmiş tek seferde bildiriliyordu. `ActivityNotifEnabled.set(true)` artık `poll(silent: true)` çağırır; `poll`/`_pollBaby`'de `silent` parametresi geçmişi bildirmeden yalnız cursor'u en yeniye çeker. Koşul: `if (since != null && !silent)`. İlk-defa-açış (since==null) davranışı aynı.
- **Dev test:** `dev_tools_screen.dart`'a "Beslenme uyarısını +1 dk planla (sessiz)" butonu eklendi (mevcut sesli butonun sessiz eşi; çift-kanal sesli/sessiz testi).

**Çok-bebek bildirimleri:** bildirim id'leri `Baby.notifSlot` (id.hashCode%1000) ile bebek başına ayrık; `NotificationService.{feedMainIdFor/feedPreIdFor/sleepIdFor/breastIdFor}`. Sayaç+beslenme artık TÜM bebekler için `FamilyNotificationSync` (MaterialApp.builder, görünmez) ile kurulur — home_screen'deki aktif-bebek-only sync kaldırıldı. Başlıklara bebek adı eklendi. Feed snooze payload'ı `feedsoundslotad` taşır.

**Çıkarılan üye temizliği:** `BabyController.refresh()` öne gelince/açılışta (main.dart `_onForeground`) listeyi tazeler; kaybolan bebeğin `recordRepository.purgeBaby` ile yerel drift verisi silinir + sayaç/cursor temizlenir + "erişimin kaldırıldı" bildirimi.

**Kararlar:** çok bebek FREE kalır (sadece davet/aile paylaşımı premium — [[para-kazanma-modeli]]). İlgili: [[suren-sayac-bildirimi]], [[beslenme-hatirlatici]], [[devir-notu-kaldirildi]].
