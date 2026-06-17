---
name: legal-veri-sorumlusu
description: Adena Baby yasal belgeler için veri sorumlusu kimliği + legal belge mimarisi
metadata: 
  node_type: memory
  type: project
  originSessionId: e827f02d-b5a1-429d-b2f1-59e7de1d576f
---

**Veri sorumlusu = Emrecan Muslu** (bireysel/şahıs, şirket DEĞİL). Yasal belgelerde geçecek bilgiler:
- Ad-soyad: **Emrecan Muslu**
- İletişim/başvuru e-postası: **emrecan.muslu@gmail.com** (özel domain maili kurulmadı; istenirse Cloudflare Email Routing ile destek@adenababy.com sonradan)
- Konum: **Sakarya, Türkiye** (tam açık adres verilmedi; şehir+ülke yeterli görüldü)
- VERBİS: bireysel/eşik altı → büyük olasılıkla **kayıt muafiyeti**; belgeye "VERBİS kaydı gerekmemektedir" notu.

## Yasal belge seti (TR+EN, site + app ortak kaynak)
Gizlilik Politikası, Kullanım Şartları, KVKK Aydınlatma Metni, Çerez Politikası. Ek bölümler (ayrı dosya değil): özel nitelikli sağlık verisi **açık rıza** (bebek ölçümleri), çocuk gizliliği, abonelik/iade (ödeme App Store/Google Play, iade mağazaya tabi).

## DURUM (2026-06-15) — UYGULANMADI, onay/başlangıç bekliyor
Tam tasarım/plan: **`docs/superpowers/specs/2026-06-15-pricing-api-and-legal-docs-design.md`**. Henüz HİÇBİR kod yazılmadı, HİÇBİR şey deploy edilmedi. Gereken tüm bilgi toplandı (yukarıdaki kimlik + 4 belge + içerik=taslak hazırla onayı). Sonraki adımlar (spec'te detaylı):
1. **Fiyat:** API prod'a deploy + `seed_pricing` (canlı endpoint şu an 404); site `/api/v1/pricing/plans` çeker, statik fallback kalır.
2. **Legal:** `apps/legal` (LegalDocument modeli + `/api/v1/legal/<type>` + `seed_legal` TR+EN taslak) + CORS allowlist; site `/gizlilik /kullanim-sartlari /kvkk /cerezler` sayfaları + footer linkleri.
3. **Deploy:** API push→pull+migrate+seed_pricing+seed_legal+restart (**seed_demo YASAK**), web push→deploy.sh.
4. Açık: prod'da eski demo data kontrolü/temizliği.

## Mimari (planlandı)
API: yeni `LegalDocument` modeli (locale tr/en + document_type + markdown body + body_html + published), `apps/content` desenini taklit; public endpoint `GET /api/v1/legal/<type>`. Seed: `seed_legal`. Site: `/gizlilik/ /kullanim-sartlari/ /kvkk/ /cerezler/` sayfaları endpoint'ten çekip render; footer linkleri bağlanır. App de aynı endpoint'i kullanabilir. Bkz [[landing-one-page]], [[yayin-eksikleri-checklist]] (KVKK açık rıza yüksek risk maddesi).
