---
name: deploy-yalniz-acik-talimatla
description: "Web (adenababy.com) ve cloud API'ye (Hetzner) ASLA otomatik deploy yapma — yalnız kullanıcı açıkça 'deploy et' dediğinde"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e59d8e37-6981-4692-940d-159e5621c4ec
---

Kullanıcı açıkça talimat vermedikçe **web (adenababy.com) ve cloud API'ye (Hetzner [[cloud-deploy-hetzner]]) ASLA deploy yapma** — git push, sunucuda git pull, deploy.sh, seed, migrate, restart dahil hiçbir canlı işlem.

**Why:** Kullanıcı 2026-06-15 net koydu: "ben söylemediğim sürece web ve cloud da otomatik deploy yapma hiç bir zaman". Canlı ortam kontrolü tamamen onda kalmalı.

**How to apply:**
- Tüm implementasyon/değişiklik local'de kalır; commit serbest ama `git push` bile açık talimat ister.
- Planlardaki "deploy" task'ları (ör. pricing/legal planı Task 10) kullanıcı "deploy et" diyene kadar BEKLER.
- Deploy zamanı geldiğinde önce kullanıcıya "deploy edeyim mi?" diye sor; onay gelince [[web-deploy-runbook]] / [[cloud-deploy-hetzner]] runbook'larını uygula.
- [[manuel-test-tercihi]] ile uyumlu (local APK kurulumu otomatik OK; canlı deploy değil).
