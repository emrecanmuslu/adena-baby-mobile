---
name: web-deploy-runbook
description: "adenababy.com web sitesi (CANLI) yeniden dağıtım runbook'u — push + sunucuda git pull"
metadata: 
  node_type: memory
  type: project
  originSessionId: e827f02d-b5a1-429d-b2f1-59e7de1d576f
---

**adenababy.com tanıtım sitesi CANLI** (Hetzner, Cloudflare ardında). Kaynak: `web/` klasörü = GitHub `git@github.com:emrecanmuslu/adena-baby-web.git` (private). Detaylı mimari [[landing-one-page]]'de.

## REDEPLOY (web değişikliğini yayına alma)
1. **Yerelde push:**
   `cd C:\Users\Dev\Desktop\baby-app\web && git add -A && git commit -m "..." && git push origin main`
2. **Sunucuda çek + nginx reload** (tek komut):
   ```
   ssh root@91.99.19.82 'bash /opt/adena/web/deploy/deploy.sh'
   ```
   (deploy.sh = `cd /opt/adena/web && git pull --ff-only && nginx -t && systemctl reload nginx`)
3. **Doğrula** (curl LOCAL hook'a takılabilir; SSH içinden çalıştır):
   ```
   ssh root@91.99.19.82 'curl -s -o /dev/null -w "%{http_code}\n" https://adenababy.com/'
   ```

## Önemli sunucu detayları
- Sunucuda kod: `/opt/adena/web`. Remote **git@github-web:emrecanmuslu/adena-baby-web.git** (SSH alias `github-web` → `~/.ssh/adena_web_deploy` deploy key; API'nin `github.com`/`adena_deploy` mapping'i ayrı, bozma).
- nginx: `/etc/nginx/sites-available/adenababy` (symlink enabled). 443 dinler; eski sslip `adena` config'i 443'te SNI ile bir arada. Eski nginx 1.24 → `listen 443 ssl http2;` formu (`http2 on;` HATA verir).
- SSL: Cloudflare Origin Cert `/etc/ssl/cloudflare/adenababy.{pem,key}` + Cloudflare Full(strict). certbot YOK. Cert dosyaları boşsa `nginx -t` patlar.
- DNS Cloudflare'de (NS alina/elmo.ns.cloudflare.com), @/www/api hepsi Proxied. www→apex 301. Always Use HTTPS açık.
- nginx config değişip cert yolu/yeni server eklenirse: önce cert dosyalarının dolu olduğundan emin ol, sonra `nginx -t`.

## Cloudflare cache (ÖNEMLİ)
HTML (uzantısız index) Cloudflare'de cache'lenmez → metin değişiklikleri anında yansır. AMA `assets/*.css`, görseller, favicon **30 gün cache'lenir** (cache-control max-age=2592000). styles.css / ekran görseli / OG değiştiren deploy sonrası eski sürüm görünebilir → Cloudflare panel → **Caching → Configuration → Purge Everything** (veya tek URL purge). Alternatif kalıcı çözüm: asset URL'lerine ?v=hash ekle.

## API not
- `api.adenababy.com` aynı sunucuda gunicorn'a proxy (Django ALLOWED_HOSTS'ta var). API redeploy AYRI → [[cloud-deploy-hetzner]].
