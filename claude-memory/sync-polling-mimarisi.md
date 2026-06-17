---
name: sync-polling-mimarisi
description: senkron/polling mimarisi — üç mekanizma + tek kullanıcıda periyodik istek kapalı (member_count gating)
metadata: 
  node_type: memory
  type: project
  originSessionId: 632c02f5-0603-4573-b4b2-416624c751d9
---

Üç ayrı mekanizma (karıştırma):
1. **SyncService** (records/record_controller.dart) — offline-first delta-sync, ASIL veri motoru. Yükler (dirty→sunucu) + çeker (server_changes→drift). Tetik: yazınca + açılış/resume + bağlantı + periyodik.
2. **FamilyActivityWatcher** (babies/activity_watcher.dart) — aktivite yoklaması (90sn+resume), sadece "X kayıt ekledi" BİLDİRİMİ; push'un yedeği. Veri taşımaz.
3. **FCM Push** (core/push_service.dart) — gerçek zamanlı bildirim + widget + hatırlatıcı yeniden planlama + foreground'da syncAll tetikleme. **Drift'e dokunmaz** (veriyi push güncellemez; sync güncceller).

**Önemli ilke:** push veriyi taşımaz, sync'i TETİKLER/haber verir. Tek kullanıcı bile sync'e muhtaç (buluta yükleme). Socket YOK → çok kullanıcıda açık/kapalı fark etmez diğerlerinin değişikliği yansımalı: kapalıyken push (hatırlatıcı/widget), açıkken push→syncAll + periyodik poll, reopen'da tam sync.

**member_count gating (battery/veri):** Baby'ye `member_count` eklendi (backend BabySerializer SerializerMethodField + tek aggregate sorgu Count, views.py counts dict; Flutter Baby.memberCount + isShared=memberCount>1). 
- `SyncService.syncAll({sharedOnly})`: periyodik tur `sharedOnly:true` → yalnız paylaşımlı bebek çeker. Açılış/yazma/bağlantı `false` → tüm bebekler (tek kullanıcı verisi de yüklenir/çekilir).
- `FamilyActivityWatcher.poll`: `!baby.isShared` ise atla.
- Sonuç: TEK KULLANICI bebekte arka planda HİÇ periyodik ağ isteği yok; veri yalnız açılış+yazınca güncellenir. Çok kullanıcıda push+poll tam çalışır.

**Güncelleme/silme gerçek zamanlılığı (sync_nudge):** log_activity yalnız `created`'da push atar → uyku/emzirme BİTİRME, düzenleme, silme (update/delete) Y'ye yansımıyordu (counter kaybolmuyordu). Çözüm: SyncView'da created olmayan değişiklik + RecordDetailView.patch/delete → `push_sync_nudge` = SESSİZ push (type:sync_nudge, bildirim göstermez; push.py `silent=True` iOS'ta content-available-only). İstemci main.dart onMessage: type `family_activity` VEYA `sync_nudge` → `syncAll()`. Böylece açık olan Y drift'i hemen çeker, ongoing sleep/breast counter düşer.

**İyileştirmeler (uygulandı):** (1) Logout/deleteAccount'ta `PushService.unregister` → `DELETE /me/devices` (token hâlâ geçerliyken) + `DeviceView.delete`; çıkılan hesaba/sonraki kullanıcıya push sızmasın. (2) Beslenme/randevu alarmı: kesin-alarm izni yoksa `_alarmMode()` exact→inexact fallback (uyarı kaybolmasın). (3) sync_nudge `requestSyncSoon()` ile 1.2sn debounce (ardışık düzenlemede tek sync). (4) sync_nudge `cancel=sleep|breast` → arka planda biten süren-sayaç bildirimini slot'tan iptal (slot=baby_id.hashCode%1000, Baby.notifSlot ile aynı). (5) Aktivite bildirimleri `groupKey` ile gruplanır. (6) FeedReminderCache.save bellek-guard (değişmedikçe keystore'a yazmaz).
**ERTELENDİ:** iki polleri (sync 60sn + aktivite 90sn) tek'e indirme — aktivite bildirimini sync pull'undan türetme refactor'ı; riskli, ayrı ele alınacak.

Pür-UI timer'lar (ağ isteği DEĞİL, dokunma): home_screen 30sn/1sn (sayaç çizimi), record_form 1sn. İlgili: [[beslenme-hatirlatici-push-sync]] [[bakici-bildirim-paylasim-2026-06-13]]
