---
name: faz1-kararlari-2026-06-11
description: "FAZ 1 kapsam kararları (2026-06-11) — para modeli, AI, düzeltilmiş yaş, sync, sosyal giriş"
metadata: 
  node_type: memory
  type: project
  originSessionId: 937eea7a-7db9-4463-ab41-f23ce7fd0c5c
---

2026-06-11'de FAZ 1 eksikleri gözden geçirildi; kullanıcı kararları:

- **Sosyal giriş (Google/Apple):** Flutter tarafı kuruldu (google_sign_in 7.2 + sign_in_with_apple 8.1, `data/social_auth_service.dart`, `features/auth/oauth_buttons.dart` — login+register butonları, tasarımdan birebir SVG logolar; repo `social()`, controller `socialLogin()`). Backend zaten hazırdı (`POST /auth/social`).
  - **GOOGLE bağlandı:** Web Client ID (`291426198839-...apps.googleusercontent.com`) → `api/.env` `GOOGLE_CLIENT_IDS` + build dart-define `GOOGLE_SERVER_CLIENT_ID`. Logo+ID'li debug APK **emulator-5554'e kuruldu**. Test debug keystore SHA-1 = `C1:C9:F0:80:38:EE:8E:A0:07:5B:0F:78:98:FF:E4:37:C4:2A:39:24`, package `com.adenababy.adena_baby`.
  - **Google için kullanıcı doğrulayacak (test edilmedi):** (1) `.env` sonrası **Django restart**, (2) Cloud Console'da **Android OAuth client** (package+SHA-1) var mı, (3) OAuth consent **test user** eklendi mi. Hata→toast: DEVELOPER_ERROR=Android client/SHA-1, invalid_token=GOOGLE_CLIENT_IDS/restart, access blocked=test user.
  - **APPLE + iOS:** bilinçli ertelendi. Apple capability/Services ID + Google **iOS client** (`GOOGLE_IOS_CLIENT_ID` + Info.plist reversed-id URL scheme) ileride. bkz [[platform-paritesi]]
- **Para modeli (premium/IAP):** ~~şimdilik her şey ÜCRETSİZ~~ → **GÜNCELLENDİ (2026-06-12): premium aktif** (RevenueCat + reklam + gating). Bu satır artık geçersiz; güncel model [[para-kazanma-modeli]].
- **AI veri dışa aktarımı:** FAZ 1'den **çıkarıldı**, gereksiz görüldü. İleride **basit LLM (chat tarzı)** değerlendirilebilir. bkz [[claude-api]] (AI eklenirse en güncel Claude modeli).
- **Düzeltilmiş yaş (prematüre):** **kalıcı kaldırıldı, geri eklenmeyecek.** Kalıntılar temizlendi: backend `gestational_age_at_birth_weeks` (migration `0006_remove_baby_gestational_age_at_birth_weeks`), `baby.dart`, serializer.
- **Gerçek zamanlı sync:** **socket YOK.** Yöntem: uygulama açılışında + **dakikada bir** istek; **bekleyen (pending) işlem varsa** güncelle. (Henüz uygulanmadı — planlanan yaklaşım bu.)
- **Bitti sayılanlar:** Canlı aktivite/ActivityEvent doluyor, akıllı nudge güncel hali uygun, randevu CRUD yapıldı, manuel testleri kullanıcı yaptı.

Kapsam dokümanı `FAZ_1_KAPSAM.md` bu kararlara göre işaretlendi.
