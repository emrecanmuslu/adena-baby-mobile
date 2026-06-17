---
name: ingilizce-ve-bolgesellestirme
description: İngilizce tam destek + cihaz-bölgesine bağlı davranış (TR+US lansmanı); seed/locale mimarisi
metadata: 
  node_type: memory
  type: project
  originSessionId: 5d996a60-f08a-4706-b6a6-0d5b6ebb3c1f
---

2026-06-15: Uygulama TR + US (Türkçe + İngilizce) için hazırlandı. Yapılanlar:

**UI çevirisi (i18n):** 891 benzersiz `tr()/trp()` metni İngilizce'ye çevrildi → `api/apps/translations/data/en.json`. Yeni komut `seed_translations --locale en` (data/<locale>.json okur, TranslationString+TranslationValue upsert, idempotent). Kaynak=TR metin=anahtar; çeviri yoksa TR'ye düşer. [[i18n-ceviri-sistemi]]

**Dinamik içerik çok-dilli:** Article/ContentCategory/PregnancyWeek modellerine `locale` alanı + `unique_together` (slug/week diller arası ORTAK, locale ayırt eder). Mevcut kayıtlar migration'da 'tr'. View'ler `resolve_locale` ile filtreler. İngilizce seed: `seed_content_en` (7 kat/29 makale), `seed_pregnancy_weeks_en` (37 hafta, imperial birim+US meyveler). WHO LMS sayısal → tek tablo. [[statik-icerik-api-migrasyonu]] [[seed-icerik-genisletme]]

**Milestone/diş:** DB'de TR title/name tutulur; serializer locale'e göre KATALOGTAN döndürür (migration'sız, mevcut bebeklere de yansır). `milestone_catalog_en.py` (58 anahtar), `teeth_catalog.TEETH_TYPES_EN`. milestone_detail(key, locale), tooth_name(pos, locale).

**Locale çözümü:** `api/apps/translations/locale.py` `resolve_locale(request)`: ?locale= → Accept-Language → 'tr'. Flutter zaten her istekte `Accept-Language: I18n.instance.locale` gönderiyor (api_client.dart) → içerik otomatik doğru dil.

**Cihaz-bölgesi davranışı (Flutter):** `core/locale_util.dart` deviceDefaultLanguage() (tr cihaz→tr, diğer→en) + deviceUsesImperial() (US/LR/MM). İlk açılışta dil cihazdan; UserSettings.language default "" (boş=seçilmedi) → client cihaz dilini uygular+kaydeder. Birim: `Units.deviceDefault()` (US→imperial), `Units.fromMap` eksik alanları bölge varsayılanına düşürür. `core/dates.dart` locale-duyarlı tarih/saat (tr: gg AAA·24s / en: AAA gg·12s AM/PM); tüm `DateFormat('...','tr_TR')` bununla değişti. Premium fiyat fallback locale'e göre ($/₺). main.dart initializeDateFormatting() tüm locale'ler.

**Yönetilebilir fiyat + indirim (DB):** `PricingPlan` modeli (accounts; admin-editable) plan başına price_try/usd + original_price_* (indirim/üstü çizili) + badge_tr/en + sale_ends_at. `GET /pricing/plans` locale para birimiyle (en→USD/$, diğer→TRY/₺) + discount_percent. `seed_pricing` komutu. Flutter: pricingProvider → premium_screen RC fiyatı yoksa DB fiyatına, sonra placeholder'a düşer; indirimde üstü çizili eski fiyat + rozet. KISIT: gerçek IAP tahsilat fiyatı App Store/Play'de; DB yalnız gösterim/fallback/dev-activate süresini sürer; gerçek indirimli tahsilat = mağaza "introductory offer". [[para-kazanma-modeli]]

**Sunucu-yönetimli diller + ülkeler:** `Language`(code,native/english_name,enabled,is_default) + `Country`(code,name_tr/en,dial_code,currency,uses_imperial,default_language FK,translated,sales_enabled) translations app'inde. `GET /i18n/locales`, `GET /i18n/countries` (catch-all <locale>'den ÖNCE). `seed_locales` (tr+en, 61 ülke; en=is_default). Flutter: supportedLocalesProvider→dil seçici+main supportedLocales DİNAMİK (yeni dil eklenince otomatik görünür, çevirisi i18n bundle'dan çekilir); countriesProvider→regionImperialProvider→activeUnitsProvider birimi cihaz ülkesine göre Country tablosundan sürer (cihaz heuristik fallback).

**KURAL — Türkiye dışı her zaman EN:** deviceDefaultLanguage cihaz ÜLKESİ TR ise tr, değilse en. Backend `content_locale(request)` (locale.py): ham istek dili tr→tr, gerisi (en/de/fr/yok)→en; içerik view'leri + health serializer'lar bunu kullanır (çevirisi olmayan locale Türkçe'ye DEĞİL en'e düşer). Country.translated=False → resolved_locale en.

**Cache (son kullanıcıyı etkileyen veri):** `core/json_cache.dart` write-through; locales/countries/pricing ağ hatası/çevrimdışı/sonraki açılışta diskten. i18n string bundle + tema + premium zaten cache'li.

NOT: CLAUDE.md'lerdeki "Tüm UI Türkçe" artık geçerli değil.
