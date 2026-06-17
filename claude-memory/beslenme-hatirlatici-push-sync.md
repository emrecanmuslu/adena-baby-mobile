---
name: beslenme-hatirlatici-push-sync
description: "paylaşımlı bebekte başka üye beslenme girince Y'nin yerel beslenme hatırlatıcısı FCM push ile yeniden planlanır"
metadata: 
  node_type: memory
  type: project
  originSessionId: 632c02f5-0603-4573-b4b2-416624c751d9
---

Sorun: beslenme hatırlatıcısı her cihazda YEREL hesaplanır (nextFeedEstimate, drift kayıtlarından). Kayıtlar yalnız uygulama ön plandayken sync olur (SyncService polling arka planda durur). X kayıt girince arka plandaki Y'nin hatırlatıcısı eski plana takılı kalıyordu.

Çözüm (HAFİF yaklaşım — arka planda drift sync'i değil): `family_activity` feed push'u Y'nin yerel hatırlatıcısını yeniden planlar.
- backend `_push_family_activity` (records/views.py): feed olayında `last_feed_ts` (süren emzirme dahil — başlangıç ts'i) + `feed_sub` taşır; `widget_update` yalnız tamamlanmış beslenmede.
- `FeedReminderSnapshot`/`FeedReminderCache` (data/feed_reminder_cache.dart): hatırlatıcı parametreleri (slot/interval/baseType/preMin/sound/quiet) ön planda `_syncFeed`'te secure storage'a yazılır; arka plan isolate buradan okur (drift/Riverpod gerekmez).
- `handlePushMessage` (push_service.dart) `_rescheduleFeedReminder`: next = last_feed_ts + interval; baseType filtresi nextFeedEstimate ile birebir.

**Test aracı:** Ayarlar → "Geliştirici · Bildirim & Push Testi" (yalnız kDebugMode; route `/dev`, features/dev/dev_tools_screen.dart). İKİ tür test: (1) "Beslenme ekle (gerçek) → Y'ye push" = bu cihazda RecordActions.addFeed ile GERÇEK kayıt → sunucu → diğer üyelere FCM push (çapraz-cihaz gerçek akış; paylaşımlı bebek+Y giriş+FCM gerekir). (2) "Yerel testler (bu cihaza)" = handlePushMessage'ı sahte payload'la çağırma + +1dk uyarı + showActivity; sunucu/paylaşım gerekmez. baseType filtresi için anne sütü/mama/biberon seçici. Ground-truth: `adb shell dumpsys alarm | grep adenababy`. Ayrıca members_screen'e pull-to-refresh eklendi.

**Kritik:** yeniden planlama, aile-etkinlik bildirimi opt-in'inden BAĞIMSIZ — Y "X kayıt ekledi" bildirimini kapatmış olsa bile çalışır (widget güncellemesi gibi koşulsuz, yalnız Y'nin kendi hatırlatıcısı açıksa gating'li). Emzirme STOP'ta push gitmez (log_activity create-only) ama başlangıç ts'i = nextFeedEstimate'in baz aldığı ts olduğundan sonuç aynı. Bilinen edge: geri-tarihli kayıt arka planda yanlış kayabilir, ön plan sync düzeltir. İlgili: [[home-screen-widget-backlog]] [[bakici-bildirim-paylasim-2026-06-13]] [[beslenme-hatirlatici]]
