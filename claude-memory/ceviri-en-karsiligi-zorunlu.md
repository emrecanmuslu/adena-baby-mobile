---
name: ceviri-en-karsiligi-zorunlu
description: "Yeni/düzeltilen her tr()/trp() metni için EN karşılığını da en.json'a ekle/güncelle ve seed et"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c8fd0cab-3779-43f7-85b9-7e3b0f3da6f9
---

Mobil uygulamada `tr()`/`trp()` ile yeni bir metin eklerken VEYA mevcut bir metni düzeltirken, İngilizce karşılığını da `api/apps/translations/data/en.json`'a eklemeyi/güncellemeyi unutma ve `manage.py seed_translations --locale en` ile DB'ye tohumla (katalog sürümü artar, uygulama bundle'ı yeniden çeker).

**Why:** Kaynak=anahtar (TR) sistemi; EN karşılığı yoksa uygulama İngilizce'de Türkçe gösterir (kullanıcı bunu "çevirisi eksik text" olarak fark etti). Bkz [[i18n-ceviri-sistemi]], [[ingilizce-ve-bolgesellestirme]].

**How to apply:** Bir Türkçe UI string'i sardığında/değiştirdiğinde aynı PR/işte: (1) en.json'a `"<TR kaynak>": "<EN>"` ekle (placeholder'ları {n}/{due} vb. birebir koru), (2) seed_translations çalıştır. Mevcut terminolojiyle tutarlı çevir (Daily Feed, Health Hub, Percentile, Ministry of Health, Caregiver…). Doğrulama: lib/'deki tüm statik tr/trp kaynaklarını çıkarıp en.json ile diff'le → 0 eksik olmalı. ASCII-only Türkçe kelimeler ve interpolasyonlu string'ler özel-karakter taramasıyla kaçar; konum-temelli (Text/label/param) + çok-kelimeli geniş tarama ile yakala. pregnancy_weeks.dart (API fallback içerik) ve dev/ araçları ile dil yerel adları ("Türkçe") sarılmaz.
