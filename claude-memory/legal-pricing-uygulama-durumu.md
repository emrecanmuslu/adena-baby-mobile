---
name: legal-pricing-uygulama-durumu
description: "TAMAMLANDI (2026-06-15): yasal belgeler + pricing-site planının 10 task'i de bitti ve CANLI deploy edildi (api + web)"
metadata: 
  node_type: memory
  type: project
  originSessionId: e59d8e37-6981-4692-940d-159e5621c4ec
---

Onaylı spec: `docs/superpowers/specs/2026-06-15-pricing-api-and-legal-docs-design.md`
Uygulama planı (10 task, no-placeholder): `docs/superpowers/plans/2026-06-15-pricing-api-site-and-legal-docs.md`
Yürütme yöntemi: **subagent-driven** (her task: implementer → spec review → code-quality review), **main** branch (worktree yok), **DEPLOY YOK** ([[deploy-yalniz-acik-talimatla]] — yalnız kullanıcı "deploy et" deyince).
Kapsam kararı: **Tam spec (A pricing-site + B legal)**.

## BİTEN — Task 1-4: legal backend (LOCAL commit, push/deploy YOK)
`api` reposunda yeni `apps/legal` app: `LegalDocument` modeli (document_type privacy|terms|kvkk|cookies × locale tr|en, body Markdown, version, effective_date, published) + `LegalDocumentSerializer` (Markdown→`body_html`, `markdown` paketi) + AllowAny `GET /api/v1/legal/<type>` + `GET /api/v1/legal` (liste) + admin. `resolve_locale` (varsayılan tr). INSTALLED_APPS + config/urls + requirements güncellendi. Testler 6/6 geçti, check temiz.
- Commit aralığı: base `8e0d4c4` → head `c055584` (4 commit). Spec review ✅, code review **Approved (minör)**.
- **Minör takip (opsiyonel, sonraki oturum karar ver):** (1) `requirements.txt`'te `markdown` pinlenmemiş → prod için pinle; (2) `body_html` public siteye gider + python-markdown HTML sanitize ETMEZ → admin-yazımı düşük risk ama bleach/allowlist kararı ver; (3) iki view'da `get_queryset` birebir tekrar (DRY); (4) liste testinde "diğer locale hariç" assert eksik.

## BİTEN — Task 5-9: seed içerik + CORS + web (LOCAL commit, DEPLOY YOK)
- **api** repo (HEAD `f9fd6db`): Task 5 `seed_legal` (8 belge × tam TR+EN içerik, placeholder yok, tüm zorunlu bölümler doğrulandı — privacy body_html ~5.6K; dev'de seed 8 yeni, endpoint 200) + Task 6 CORS env-allowlist (DEBUG→allow-all, prod→adenababy.com default; prod simülasyonu doğrulandı) + minör #1 markdown==3.10.2 pinlendi.
- **web** repo (HEAD `2283594`): Task 7 pricing API fetch (TR+EN, statik fallback; `per`/`save` çakışmasını `perOf`/`saveOf` ile çözdüm) + Task 8 `.legal-*` CSS + 8 yasal sayfa (TR `/gizlilik /kullanim-sartlari /kvkk /cerezler` + EN `/en/privacy /terms /kvkk /cookies`, hepsi `legal-wrap` doğrulandı) + Task 9 footer linkleri (tr+en) + sitemap 8 yeni url (toplam 10, XML valid). CSS `?v=2`→`?v=4`.
- Pricing API yanıt şekli doğrulandı: `{plans:[{plan,price("₺590"),discount_percent}]}` — JS birebir uyumlu.
- **Açık minör (opsiyonel):** body_html site'de innerHTML ile enjekte ediliyor + python-markdown HTML sanitize etmiyor → yalnız admin (Emrecan) yazıyor, self-XSS riski, düşük; istenirse bleach. #3 view get_queryset DRY tekrarı + #4 liste testi assert hâlâ açık (minör).

## BİTEN — Task 10: DEPLOY (2026-06-15, kullanıcı "web deploy et" dedi → api bağımlılığı nedeniyle önce api sonra web)
- **api** push (f9fd6db) → Hetzner `git pull` + `pip install` + `migrate` (legal.0001 OK) + `seed_legal` (8 yeni) + `collectstatic` + `systemctl restart adena` → active. Endpoint canlı doğrulandı: `GET api.adenababy.com/api/v1/legal/privacy?locale=tr|en` → 200, body_html ~5.6K.
- **web** push (2283594) → `deploy.sh` (nginx reload OK). 8 yasal sayfa hepsi 200, styles.css?v=4 → 200.
- **CORS canlı doğrulandı**: `Origin: https://adenababy.com` ile legal + pricing → `access-control-allow-origin: https://adenababy.com` (cross-origin fetch çalışıyor).
- YAYIN_EKSIKLERI: #2/#3 birleştirildi (hosting bitti → KALAN yalnız uygulama-içi url_launcher link), #11 güncellendi (beyan bitti → KALAN mağaza formları). Kök git deposu değil, commit yok.
- **Açık kalan ufak iş:** uygulama içinden (ayarlar/kayıt) bu canlı yasal URL'lere `url_launcher` linki + mağaza Data Safety/Privacy Labels formları. [[yayin-eksikleri-checklist]]

## BİTEN — Uygulama-içi yasal link entegrasyonu (2026-06-15, plan dışı ek iş)
Kullanıcı "evet yapalım" dedi (kapsam: Ayarlar + Kayıt, bloklayan checkbox DEĞİL bilgi metni).
- **mobile-app** (commit, push YOK): yeni `lib/core/legal_links.dart` (`LegalDoc` enum + locale-doğru URL eşlemesi — TR `/gizlilik /kullanim-sartlari /kvkk /cerezler`, EN `/en/privacy /terms /kvkk /cookies`; `openLegalDoc` → url_launcher externalApplication + hata yönetimi). `config.dart` `WEBSITE_BASE_URL` (default https://adenababy.com). `privacy_screen.dart`'a "Yasal" bölümü (4 AdMenuItem). `register_screen.dart`'a tıklanır onay metni (TapGestureRecognizer, dispose'lu). `pubspec` url_launcher ^6.3.1. AndroidManifest `<queries>` https VIEW intent.
- analyze temiz, APK build geçti, emulator-5554'e kuruldu. UI testi kullanıcıda.
- **api** (commit, push YOK): `en.json`'a 11 yeni EN (Yasal, Gizlilik Politikası, Kullanım Şartları, KVKK Aydınlatma Metni, Çerez Politikası, "Web sayfasını açar", onay metni parçaları). Dev'de seed_translations --locale en çalıştı (katalog 3944).
- YAYIN_EKSIKLERI #2 → TAMAM işaretlendi (host + uygulama linki). #11 mağaza formları hâlâ açık.
- **BEKLEYEN OPERASYONEL (deploy):** Hetzner'da `git pull` + `seed_translations --locale en` (en.json'daki 11 yeni giriş canlıya); aksi halde EN'de bu 5 yasal etiket Türkçe görünür. Yalnız açık "deploy et" talimatıyla [[ceviri-en-karsiligi-zorunlu]].

## (referans) Plan'daki Task 10 deploy adımları
- **Task 5:** `seed_legal` komutu — 4 belge × TR+EN tam taslak (planda zorunlu bölümler listeli: veri sorumlusu Emrecan Muslu/emrecan.muslu@gmail.com/Sakarya; sağlık verisi açık rıza; 3.taraf Google/Apple/RevenueCat/Firebase; KVKK md.11 hakları + VERBİS muafiyeti notu; abonelik/iade; çocuk gizliliği; tıbbi feragat; CCPA). İçerik yazımı → **capable model** kullan. Taslaklar bağlayıcı değil, kullanıcı/avukat sonra gözden geçirir.
- **Task 6:** CORS sertleştirme (`settings.py`: DEBUG'da allow-all, prod'da `CORS_ALLOWED_ORIGINS` env, default adenababy.com + www).
- **Task 7:** Site pricing'i API'den çek (`web/index.html` + `web/en/index.html`, statik fallback korunur, TR=TRY / EN=USD, CSS `?v=4`).
- **Task 8-9:** 8 yasal sayfa (`/gizlilik /kullanim-sartlari /kvkk /cerezler` + `/en/privacy /terms /kvkk /cookies`) `body_html` fetch eder; `.legal-*` CSS; footer linkleri (tr+en); sitemap 8 giriş.
- **Task 10:** Deploy + uçtan uca doğrulama — **YALNIZ kullanıcı açık talimatıyla**. `seed_demo` ASLA. Bitince YAYIN_EKSIKLERI #2/#3 satırlarını sil.

## ÖNEMLİ bağlam (bu oturumda olan)
- Cloud API artık `git pull` ile **8e0d4c4**'te (bugün deploy edildi) + tüm seed'ler çalıştı → çeviri (1014) + 58 milestone + içerik/pricing canlı. AMA `apps/legal` commit'leri (c055584) **local'de, cloud'da YOK** (deploy edilmedi).
- Yeni doğru API adresi: **`https://api.adenababy.com/api/v1`** ([[cloud-deploy-hetzner]]); eski sslip.io kullanma.
- Güncel APK masaüstünde `C:\Users\Dev\Desktop\AdenaBaby.apk` (api.adenababy.com ile derli). GitHub iOS workflow varsayılanı da api.adenababy.com.
- İlgili: [[yayin-eksikleri-checklist]] [[legal-veri-sorumlusu]] [[oturum-durumu-fiziksel-test]]
