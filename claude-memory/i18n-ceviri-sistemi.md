---
name: i18n-ceviri-sistemi
description: "Sunucu-yönetimli çeviri (i18n): kaynak metin=anahtar, Django admin'den yönetilir, versiyonlu cache, tr() + otomatik toplama"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

Çoklu dil sistemi (kullanıcı 2026-06-11'de istedi; şimdilik TR + EN). **Yaklaşım: kaynak metin = anahtar** (gettext/OTA mantığı) — kodda `tr('Selam Nasılsın?')` yazılır; çeviri yoksa kaynağa (TR) düşülür. Ayrı key dosyası YOK. Tüm diller **Django admin'den** yönetilir.

**Backend (`apps/translations`):** `TranslationString(source unique=TR metin, auto)` + `TranslationValue(string, locale, text)` (esnek — yeni dil = migration GEREKMEZ) + `Catalog(version)` singleton. Versiyon `TranslationValue` post_save/delete signal'iyle artar (kaynak toplama versiyonu artırmaz). Admin: TranslationString + inline değerler. Migration `0001_initial` uygulandı. INSTALLED_APPS + config/urls'e eklendi → **Django restart gerekir**.
- `GET /api/v1/i18n/<locale>?v=<int>` → değişmişse `{version, strings:{kaynak:çeviri}}`, aynıysa `{unchanged:true}`. TR'de boş.
- `POST /api/v1/i18n/report {sources:[...]}` → bilinmeyen TR metinleri `auto=True` ile ekler (panelde belirir, çevirisi sonradan girilir).

**App:** `core/i18n.dart` `I18n` (ChangeNotifier) + global `tr(src)`; `data/i18n_repository.dart` (dio fetch + path_provider JSON cache `i18n_<locale>.json`, versiyon farkıyla; çevrimdışı→cache); `features/settings/locale_controller.dart` `LocaleController` (UserSettings.language'a yazar — zaten vardı; bundle'ı sync edip I18n'e uygular). `main.dart`: `AnimatedBuilder(animation: I18n.instance)` ile dil/bundle değişince tüm ağaç yenilenir, `locale: Locale(localeStr)`. tr() çevirisi bulunamayan TR metni 3 sn debounce ile `/i18n/report`'a gönderir (otomatik toplama).

**Dil seçimi:** Görünüm sayfasında (`appearance_screen.dart`) Türkçe/English satırları → `setLocale`. Dil adları çevrilmez.

**DURUM:** Altyapı + tüm UI ekranları `tr()` ile sarıldı. 2026-06-11'de paralel workflow (33 ajan) ile **499 statik string / 27 dosya** sarıldı (analyze temiz, build+install OK). bkz [[gorunum-birimler-birlesti]]

**İNTERPOLASYON + BİLDİRİMLER (2. workflow, 18 ajan):** `trp(src, {ph: değer})` yardımcısı eklendi (i18n.dart). İnterpolasyonlu metinler `trp('{n} gün önce', {'n': n})` kalıbına çevrildi (**77 metin / 18 dosya**). 'Sağ/Sol' gibi interpolasyona beslenen değerler tanımlandıkları yerde tr()'lendi. notification_service title/body/kanal adları tr/trp ile sarıldı (ana isolate'ta yüklü; arka plan snooze isolate'ı TR'ye düşer — kabul). analyze+build OK.

**KASITLI TR KALAN (doğru):** Türkçe kelime İÇERMEYEN saf-veri interpolasyonları ('${ml}ml', '$h:$m', tarih), dil adları ('Türkçe'/'English'), map key'leri, ikon/route/DateFormat. Çoğul gramer (1 gün vs 2 gün) basit; placeholder yerleştirme, çoğul kuralı yok.

**Test verisi:** DB'de 'Görünüm'→'Appearance' (en) çevirisi var (canlı demo).
