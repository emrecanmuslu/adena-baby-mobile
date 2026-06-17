---
name: home-ozellestirme-ve-senin-icin
description: "Home'da Hızlı Giriş/Son Aktivite özelleştirilebilir (UserSettings.quick_actions/home_cards) + \"Senin için\" keşif bölümü (2026-06-12)"
metadata: 
  node_type: memory
  type: project
  originSessionId: e71a7c63-04ee-4578-9c21-eacd349fcfe1
---

İki home iyileştirmesi yapıldı (2026-06-12, analyze temiz, APK emulator-5554):

**1) "Senin İçin" bölümü** — eski "UZMAN REHBERİ" home bloğu kaldırıldı; yerine dönüşümlü **`_ForYouSection`** (home_screen.dart): yaşa uygun 1 uzman yazısı + 1 popüler topluluk sorusu (communityFeedProvider sort=top). "Tümü" → /discover. İkisi de yoksa gizlenir. Amaç: hem home kısalsın hem Topluluk keşfedilsin. bkz [[navigasyon-kesfet-hub]]

**2) Hızlı Giriş + Son Aktivite ÖZELLEŞTİRİLEBİLİR.** Kullanıcı içgörüsü: yenidoğan için uyku takibi anlamsız (sürekli uyurlar), ~3-4 aydan sonra önemli → sabit feed/bez/uyku yerine kullanıcı seçsin.
- Mevcut **`UserSettings.quick_actions` + `home_cards`** JSON alanları kullanıldı (zaten serializer'da; **backend değişikliği/migration YOK**). Liste = RecordType adları (`feed`,`diaper`...). Varsayılan feed/diaper/sleep.
- `features/home/home_layout.dart`: `HomeLayout{quick,lastActivity}` + `HomeLayoutController` (AsyncNotifier; settings()'ten yükler, setQuick/setLastActivity → updateSettings). `kHomeCardChoices` = seçilebilir 8 tür.
- `features/home/home_layout_editor.dart`: `showHomeLayoutEditor(isQuick, current)` sheet — 1–4 tür seç, sıralı (numara rozeti), yenidoğan-uyku ipucu notu.
- Home: her iki bölüm başlığı artık **`_EditableSec`** (sağda kalem ✎ ikonu → editör). Hızlı Giriş satırı `layout.quick`'ten (`_quickCardFor`: uyku özel başlat/bitir, diğerleri showRecordForm), Son Aktivite `layout.lastActivity`'den render. Çekirdek sıralama (Sonraki beslenme/Bugün) dokunulmadı.
