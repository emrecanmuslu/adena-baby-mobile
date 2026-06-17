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

**Backend:** content + i18n catalog AllowAny yapıldı (hesapsız açılışta çeviri/içerik gelsin). İdempotent create + 60g grace purge ayrı oturumda (bkz özet/sonraki not).

**Yedek uyarısı:** BackupNagBanner (features/settings/backup_nag.dart) free'de home'da "verin yalnız bu telefonda". Export (data_export.dart) free'de tam yerel kopya (memories/mom/cycle dahil).

**Bilinen sınır:** hesap-değiştirme (aynı cihaz) yerel veriyi karıştırabilir (kişisel cihaz varsayımı); accountless'ta home milestone/reminder bölümleri boşa düşer (zarif).
