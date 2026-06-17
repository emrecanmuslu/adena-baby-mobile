---
name: faz3-uzman-icerik-topluluk-plani
description: FAZ 3 (c) uzman içeriği + topluluk — TAMAMLANDI; verilen kararların kaydı
metadata: 
  node_type: memory
  type: project
  originSessionId: bd1d3de8-169e-4f79-94bf-4fb3bd612698
---

**DURUM: TAMAMLANDI (2026-06-12/13).** FAZ 3 (c) = uzman içeriği + ebeveyn topluluğu yapıldı; aşağısı verilen kararların kaydıdır (uygulama detayı kodda).

**Uzman içeriği** (`apps/content`): ContentCategory + Article (Markdown gövde, yaş+kategori filtre, salt-okunur DRF, admin + `seed_content`). Mobil: content_repository, `core/ad_markdown.dart` (hafif tema-duyarlı MD; flutter_markdown EKLENMEDİ), features/content (hub + liste + detay). Köprüler: Sağlık Hub + ana sayfa "Senin için". Makale kaynağı = hem seed (6 kategori/8 makale) hem admin.

**Topluluk** (`apps/community`): biçim = **kızlarsoruyor tarzı zengin soru-cevap** (soru+cevap+yukarı/aşağı oy+en iyi cevap+kategori); moderasyon = **rapor + eşik(3) otomatik gizleme + admin inceleme**; kategoriler = **uzman içeriğiyle aynı** (ContentCategory); anonimlik = **sadece global ayar** (varsayılan gerçek isim, gönderi anında snapshot), bebek bilgisi paylaşılmaz. Model: Question/Answer/Vote/Report. 2026-06-13'te eklendi: kendi içeriğini düzenle/sil, sonsuz kaydırma, arama, kullanıcı profili (detay [[oturum-durumu-fiziksel-test]]).

Not: uzman içeriği ileride premium ayrımına aday olabilir ama şu an free ([[para-kazanma-modeli]]). bkz [[faz1-kararlari-2026-06-11]] [[faz2-faz3-secilen-kapsam]] [[navigasyon-kesfet-hub]]
