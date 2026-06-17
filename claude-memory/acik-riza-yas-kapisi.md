---
name: acik-riza-yas-kapisi
description: "KVKK açık rıza + yaş kapısı (18+): kayıt kutusu + sosyal giriş rıza kapısı + denetlenebilir Consent modeli"
metadata: 
  node_type: memory
  type: project
  originSessionId: 87f75319-2d5c-4b96-a117-54fb0230fb23
---

YAYIN_EKSIKLERI #7+#8 kapatıldı (2026-06-15). Kararlar: OAuth=ilk girişte rıza kapısı ekranı (e-posta+OAuth tek mekanizma); saklama=denetlenebilir Consent modeli; sağlık rızası=tek birleşik (gizlilik metnine gömülü); kutu=tek "18+ ve kabul".

**Backend (api, commit ae3dd4a + 8514313):** `apps/accounts` yeni `Consent` modeli (user, consent_type=privacy|terms|age_18, version, source=register|social|gate, accepted_at) — kanıtlanabilir KVKK/GDPR izi, salt-okunur admin. `apps/accounts/consent.py`: `current_versions()` (LegalDocument'tan privacy/terms sürümü, fallback 1.0), `is_required(user)` (güncel sürümlü privacy+terms+age_18 eksikse True → sürüm değişince yeniden rıza), `record(user, source)` (3 satır bulk_create). Register artık `accepted_legal`+`age_confirmed` zorunlu (400 yoksa) + record. `POST /auth/consent` (auth) gate/social için. `/me` + register/login/social yanıtlarına `consent_required` eklendi. Migration `accounts/0007_consent`. 6 test.

**Mobil (mobile-app):** `User.consentRequired` istemci alanı (API'de user yanında `consent_required`); `_consumeAuth`+`me()` parse eder. Kayıt ekranı: paylaşımlı `LegalConsentCheckbox` (tek kutu, tıklanır Gizlilik/Şartlar linkleri [[legal-pricing-uygulama-durumu]] url_launcher); işaretlenmeden submit yok. `ConsentGateScreen` (/consent-gate): sosyal giriş / eski hesap için; router redirect `user.consentRequired` → kapıya, `recordConsent()` sonrası çıkar. `AuthController.recordConsent()` state.consentRequired=false yapar.

**i18n:** EN'e checkbox+gate metinleri eklendi; "Çıkış yap"=Sign out korundu (yanlışlıkla değişmişti, geri alındı). [[ceviri-en-karsiligi-zorunlu]]

analyze temiz, APK build+emulator-5554 kuruldu (local backend'e bağlı, migrate edildi).

**DEPLOY EDİLDİ (2026-06-16, commit 263f88f):** Hetzner'da migrate (accounts 0007) + seed_translations --locale en (7 yeni: consent 6 + feragat 1; link 6 önceki turda) + restart. Ön-kontrol temiz (DEBUG=False, ALLOWED_HOSTS daraltılmış, SECRET_KEY 67 char, nginx X-Forwarded-Proto var). Doğrulandı: `/auth/consent`→401 (auth), HSTS `max-age=31536000;includeSubDomains;preload`, X-Frame DENY, nosniff, legal/pricing hâlâ 200. NOT: eski/demo hesaplar artık ilk girişte rıza kapısı görür (beklenen).

**Prod sertleştirme (commit 0dd6bb5, YAYIN #9) CANLI:** `settings.py` DEBUG=False'ta güvensiz default'ları (SECRET_KEY default / ALLOWED_HOSTS=*) ImproperlyConfigured ile boot-engeller. Gelecekte sunucu `.env`'i bozulursa (SECRET_KEY/ALLOWED_HOSTS) gunicorn boot ETMEZ — deploy öncesi `.env` doğrula. SECURE_SSL_REDIRECT nginx X-Forwarded-Proto'ya bağlı (mevcut nginx gönderiyor); göndermezse `.env` SECURE_SSL_REDIRECT=False.
