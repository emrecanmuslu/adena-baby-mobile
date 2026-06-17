---
name: cloud-deploy-hetzner
description: "Test API Hetzner'da yayında — yeni oturumda bağlanıp redeploy için TAM RUNBOOK (komutlar, doğrulama, sorun giderme)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5a1718dd-f88e-4571-a2cc-054b7a6cea75
---

2026-06-12: Django API Hetzner sunucuya deploy edildi. TEST amaçlı — fiziksel telefon/iOS testleri buraya bakar. Local geliştirme HÂLÂ local Django'da kalır (cloudflared tünel artık gerekmiyor).

## Erişim
- **SSH:** `ssh root@91.99.19.82` — bu makineden (Dev kullanıcısı) **key-based çalışıyor**, parola/setup gerekmez; host known_hosts'ta.
- **Sunucu:** Hetzner Ubuntu 24.04. Kod: `/opt/adena/api` = `git@github.com:emrecanmuslu/adena-baby-api.git` clone'u (sunucuda deploy key `~/.ssh/adena_deploy` ile read-only `git pull` çalışır).
- **Local repolar:** api = `C:\Users\Dev\Desktop\baby-app\api` (remote: adena-baby-api), mobil = `mobile-app` (remote: adena-baby-mobile). Flutter: `/c/src/flutter/bin/flutter`.

## Stack
PostgreSQL 16 (DB+user `adena`, parola `/opt/adena/api/.env`'de) → gunicorn (systemd **`adena.service`**, 127.0.0.1:8001) → nginx reverse proxy → Let's Encrypt HTTPS.
- **API base (GÜNCEL, fiziksel cihaz/iOS build bunu kullan):** `https://api.adenababy.com/api/v1` — Cloudflare proxied, aynı sunucuda gunicorn'a (127.0.0.1:8001) gider. nginx `server_name api.adenababy.com` config'i `adenababy` dosyasında (api+web aynı dosyada).
- **sslip.io KAPATILDI (2026-06-16):** `91.99.19.82.sslip.io` nginx sitesi (`adena`) devre dışı (symlink silindi; config sites-available'da duruyor, yedek `/root/adena.nginx.bak.*`). Artık 000 döner. Tek API domaini = api.adenababy.com.

## Güvenlik (2026-06-16 sertleştirildi)
- **ufw aktif:** yalnız 22/80/443. Postgres(5432)+gunicorn(8001) zaten localhost-only.
- **SSH:** parola auth KAPALI, yalnız key (`/etc/ssh/sshd_config.d/99-adena-hardening.conf`). Bu makinede key var; başka makineden parola ile GİREMEZSİN → Hetzner web console fallback. PermitRootLogin prohibit-password.
- **fail2ban:** aktif (sshd jail; brute-force IP'leri banlıyor — sunucu saldırı altındaydı).
- **nginx:** `server_tokens off`. unattended-upgrades aktif. .env 600.
- **Korumalı media:** bebek/anı foto `/api/v1/files/<path>?e=&s=` imzalı; nginx `location ~ ^/media/(babies|memories)/ { deny all; return 404; }` her iki config'te. Düz `/media/babies|memories/` → 404. İçerik/fetüs public.
- **purge cron:** `0 3 * * * .../manage.py purge_deleted_accounts` (hesap silme grace temizliği).
- Swagger: `/api/docs/` · ReDoc: `/api/redoc/` · şema: `/api/schema/`
- Admin: `/admin/` (Türkçe) — admin@adena.app / RLQtp8rfnyb5

## REDEPLOY RUNBOOK (yeni oturumda backend güncelleme)
1. **Local'de değişiklikleri push et:**
   `cd C:\Users\Dev\Desktop\baby-app\api && git add -A && git commit -m "..." && git push origin main`
2. **Sunucuda çek + uygula** (tek komut):
   ```
   ssh root@91.99.19.82 'cd /opt/adena/api && git pull --ff-only && .venv/bin/pip install -q -r requirements.txt && .venv/bin/python manage.py migrate --noinput && .venv/bin/python manage.py collectstatic --noinput && systemctl restart adena && echo DONE:$(systemctl is-active adena)'
   ```
   (migrate/collectstatic gerekmezse no-op; sorun değil.)
3. **Doğrula** (sslip.io kapandı; api.adenababy.com Cloudflare arkasında → origin'i --resolve + -k ile test et):
   ```
   ssh root@91.99.19.82 'curl -sk --resolve api.adenababy.com:443:127.0.0.1 https://api.adenababy.com/api/v1/ping -o /dev/null -w "%{http_code}\n"'
   ```
   (migration/seed örneği: `ssh root@91.99.19.82 'cd /opt/adena/api && git pull --ff-only && .venv/bin/python manage.py migrate && .venv/bin/python manage.py seed_translations --locale en && systemctl restart adena'`)

## APK / iOS build (telefon cloud'a baksın)
- **APK:** `cd mobile-app && /c/src/flutter/bin/flutter build apk --release --dart-define=API_BASE_URL=https://api.adenababy.com/api/v1` → `build/app/outputs/flutter-apk/app-release.apk`
- **iOS (GitHub):** `mobile-app/.github/workflows/ios.yml` workflow_dispatch input `api_base_url` varsayılanı `https://api.adenababy.com/api/v1` (Actions → Run workflow → hazır gelir).

## Sorun giderme
- Servis durumu/log: `ssh root@91.99.19.82 'systemctl status adena --no-pager; journalctl -u adena -n 50 --no-pager'`
- Nginx: `nginx -t && systemctl reload nginx`; log `/var/log/nginx/error.log`
- DB bağlantısı: `.env` DATABASE_URL; `sudo -u postgres psql -d adena`
- gunicorn root olarak çalışıyor (test basitliği; git pull root yapar, izin sorunu olmaz). Hardening sonra.

## Notlar
- Yeni Python paketi eklersen requirements.txt'e ekle (pip install adımı çeker).
- Yeni model/migration → migrate adımı uygular. Sunucu DB Postgres (local sqlite'tan farklı; sadece migration'lar taşınır, veri değil).
- Social login client ID'leri prod .env'de boş (email/şifre çalışır). RevenueCat/AdMob token yok (placeholder).
- HTTPS sertifikası certbot ile otomatik yenilenir (systemd timer).
- **PROD'DA `seed_demo` ÇALIŞTIRMA — YASAK.** `seed_demo` ekran görüntüsü için demo hesap/kayıt üretir (demo-bebek@adena.test / demo-gebelik@adena.test, sifre123) — yalnız local/SS. Prod deploy'da SADECE: migrate + (gerekirse) seed_pricing/seed_content/seed_legal + collectstatic + restart. Kullanıcı 2026-06-15 bunu açıkça uyardı.