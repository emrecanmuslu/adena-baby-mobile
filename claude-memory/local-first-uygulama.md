---
name: local-first-uygulama
description: Local-first + premium-cloud mimarisi UYGULANDI (big-bang); dosyalar, gating bayrağı, cutover göçü, kapsam kararı
metadata:
  type: project
---

Local-first big-bang UYGULANDI (2026-06-17). Plan [[local-first-premium-plani]]'ndaki kararlar koda döküldü. Para modeli export kararı [[para-kazanma-modeli]] güncellendi (free'ye tam export açık).

**Merkez bayrak:** `cloudSyncEnabledProvider` (lib/data/sync_gate.dart) = oturum açık **&&** premium. Free (hesaplı/hesapsız) yerel-önce; cloud kullanıcı verisine hiç ağ gitmez. Tüm repo sync'leri ve `SyncService.syncAll()` bu bayrakla gate'li.

**Yerel depo:** Drift şeması (lib/data/local/app_database.dart, schemaVersion=4) tablolar: Records(zaten), Babies, Memories, MomEntries, CycleSettingsTable(singleton id='me'), CycleEntries. Hepsinde `_SyncCols` mixin (isDeleted/clientUpdatedAt/serverUpdatedAt/dirty). Babies'te `settings` JSON kolonu = aile ayarları (units/quiet_hours/feed_reminder yerelde). Foto: Memories.localPhotoPath (free, kalıcı app dizinine kopyalanır) → premium'da yüklenince `photo`=sunucu URL.

**Local-first'e çevrilen repo'lar:** baby/memory/mom/cycle (Drift birincil, premium-gated push/pull, imzalar korundu → ekranlar değişmedi). Records zaten offline-first'ti, sync'i gate'lendi.

**KAPSAM KARARI:** Health (aşı/milestone/diş/reminder) local-first'e ÇEVRİLMEDİ — sunucu kataloğu + int-ID'ye bağlı; tasarımın "aşı takvimi herkese cloud'dan" notuyla tutarlı → **(free) hesap gerektiren cloud** kaldı. Hesapsız kullanıcıda Keşfet'te `requireAccount` (lib/core/premium_gate.dart) ile "giriş yap" istenir. Topluluk da requireAccount.

**Auth-opsiyonel açılış:** LocalSession (lib/data/local_session.dart) = localUserId(createdBy) + yerel KVKK/18+ rıza. Router login zorlamasını kaldırdı: rıza(yerel)→bebek(yerel)→home; login yalnız premium/aile/topluluk isteyince. ConsentGate rızayı yerelde alır (hesaplıysa backend'e de yazar).

**CUTOVER GÖÇÜ (kritik):** Mevcut kullanıcı verisi yalnız sunucudaydı → v4'te yerel BOŞ olurdu. `InitialImportService` (lib/data/initial_import.dart) tek-sefer (LocalSession imported bayrağı) sunucu→yerel indirir; AuthController.build + login/register/social `_postLogin`'den çağrılır (premium'dan bağımsız). free→premium yönünde `MigrationController` (lib/data/migration_service.dart) yerel dirty veriyi cloud'a idempotent yükler; tam-ekran ilerleme overlay'i (features/settings/migration_overlay.dart, kök Stack). Dirty yoksa overlay atlanır.

**Backend (TAMAM, ama DEPLOY BEKLİYOR — canlıya gitmedi):** content + i18n CatalogView AllowAny (apps/content/views.py, apps/translations/views.py). İstemci-UUID create'ler idempotent (babies/memories/mom/cycle). `IsPremiumForWrite` permission (apps/accounts/permissions.py) → lapsed/free cloud'a yazamaz, okuma serbest. `purge_lapsed_premium_data` management command (60g grace; owner-only cloud veri siler, hesabı korur; --dry-run). Yeni migration YOK. Crontab'a eklenecek.

**ONBOARDING AKIŞI (hesapsız):** Splash → Rıza kapısı (Çıkış gizli + altta dil seçici LanguageQuickPick) → **Welcome/ProfileSetup** (lib/features/onboarding/profile_setup_screen.dart): ① "Hesapsız devam et" (ad-soyad → localNameProvider) VEYA ② "Hesap oluştur"/"Giriş yap" → Bebek ekle (hesapsızda davet-kodu yerine "Giriş yap", Çıkış gizli) → Home. Router'da ad kapısı: `needsName = user==null && localName boş` → /profile-setup. Auth: login/register geri butonu + aralarında pushReplacement (welcome stack'te kalır).

**401 DENETİMİ (tüm proje tarandı, hesapsız 401 kapatıldı):** Provider seviyesinde kısa-devre (!loggedIn → boş/free, ağ yok): `subscriptionProvider`→free, vaccines/milestones/teeth/reminders→boş, home "Senin için" community teaser çekilmez. Giriş-noktası gate'leri (requireAccount): Ayarlar "Aile/Paylaşım", Keşfet "Bebeğin Sağlığı"+"Topluluk", Reminders özel-hatırlatıcı kartı. Activity watcher zaten `me==null` no-op. Local-first repolar zaten gate'liydi.

**PROFİL (hesapsız):** home `_HeaderAvatar` + settings başlığı ad/baş-harf `localNameProvider`'dan; settings alt başlık "Yerel profil · rol"; "Çıkış yap"→"Giriş yap/Hesap oluştur"; ad düzenleme yerel kaydeder.

**i18n flaş düzeltmesi:** main() `_preloadLocaleBundle` (cache yoksa + cihaz dili≠tr → splash öncesi bundle getir, 4sn timeout); router `_RouterRefresh` I18n dinleyicisi (bundle gelince mevcut sayfa tazelenir); LanguageQuickPick (lib/core/language_quick_pick.dart) fallback `I18n.instance.locale` (TR→EN flaşı yok).

**Veri&Gizlilik (hesapsız):** initState /auth/me/settings atlanır; "Bulut yedekleme" kartı gerçek durum (cloudSyncEnabled: Açık / "Kapalı·Premium ile"); anonim+hesap-sil yalnız hesaplı; hesapsızda "Yerel verileri sil" = `AppDatabase.wipeAllData()` + `LocalSession.clearLocalProfile()` + restart (rıza kalır → tanışma ekranı).

**Yedek uyarısı:** BackupNagBanner free'de home'da. Export tam yerel kopya.

**BEKLEYEN İŞLER:** (1) **Adena Premium sayfası** local-first değer önermesine göre güncellenecek (kullanıcı istedi, henüz yapılmadı). (2) **Backend DEPLOY** (api.adenababy.com): content/i18n AllowAny + idempotency + grace canlıda DEĞİL — deploy edilince hesapsız EN/içerik canlıda çalışır. (3) Aşı/gelişim/diş ekranları hesapsızda boş (çökmez); istenirse local-first'e çevrilebilir.

**Test:** emulator-5554 (AVD), debug APK kurulu; analyze temiz; akış local Django'ya bağlı (10.0.2.2). Kullanıcı manuel test ediyor.
