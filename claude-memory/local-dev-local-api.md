---
name: local-dev-local-api
description: "Local geliştirme HER ZAMAN local Django API'ye bağlanır (tünel yok); cloud yalnız fiziksel telefon/iOS build'leri için"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5a1718dd-f88e-4571-a2cc-054b7a6cea75
---

Local geliştirme her zaman **local Django API**'ye bağlanır — cloudflared tünel YOK, [[cloud-deploy-hetzner]] sunucusu DEĞİL. Cloud sunucu (91.99.19.82.sslip.io) yalnız **fiziksel telefon + iOS test build'leri** içindir.

**Why:** Kullanıcı local'de local Django çalıştırıp emülatörle geliştiriyor; cloud sadece gerçek cihaz testleri için ayrıldı.

**How to apply:**
- Emülatör/local APK build'lerinde `--dart-define=API_BASE_URL` VERME → `config.dart` varsayılanı kullanılır (`http://10.0.2.2:8000/api/v1` AVD; MuMu'da LAN IP — bkz mobile CLAUDE.md).
- Cloud URL'li dart-define'ı YALNIZ fiziksel telefon release APK'sı + iOS GitHub build'inde kullan.
- Aksini kullanıcı açıkça söylemedikçe bu geçerli ([[manuel-test-tercihi]] ile uyumlu: analyze temizse emülatöre APK kur).