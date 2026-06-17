---
name: beslenme-hatirlatici
description: "Yapılandırılabilir beslenme hatırlatıcısı — config family-settings'te, kesin alarm + heads-up + ertele"
metadata: 
  node_type: memory
  type: project
  originSessionId: 51705ee7-5832-41ca-b19e-8c7ff489b39a
---

"Sonraki beslenme" sabit tahminden çıkarılıp **kullanıcı ayarlı besleme hatırlatıcısına** çevrildi (kullanıcı 2026-06-11'de istedi).

**Config nerede:** Backend'de reminder schedule PATCH'i olmadığı için ayar **family-settings `feed_reminder`** altında tutuluyor (units gibi kısmi güncellenir) — `models/feed_reminder.dart` `FeedReminderConfig`, `family_settings.dart` `feedReminderProvider`/`updateFeedReminder`. Alanlar: enabled, interval_min, base_type ('all'|'breast'|'formula'), pre_min, **sound** (bool). NOT: reminders ekranındaki Reminder(type:'feed') satırı KULLANILMIYOR (ekleme sheet'inden çıkarıldı).

**2026-06-11 revizyon (kullanıcı):** "Ortalama" hesap modu **tamamen kaldırıldı** (model `mode` alanı silindi, sheet'teki "Hesap modu" sekmesi gitti) — herkes **sabit aralık**. Varsayılanlar: interval 120 dk (2 saat), pre_min 30. **Sesli alarm varsayılan KAPALI** (`sound:false`) — kullanıcı sheet'teki "Sesli alarm: Sessiz/Sesli" sekmesinden açar.

**Hesap:** `nextFeedEstimate(cfg, records)` (family_settings.dart) — son (baz türü) beslenmesi + interval (sabit). Süren emzirme çapa olmaz. Home "Sonraki beslenme" kartı hatırlatıcı kapalıyken bile gösterir: kapalıysa varsayılan `const FeedReminderConfig()` (her 2 saat, tüm beslenmeler), alt yazı "Son beslemeye göre · her 2 saat"; açıksa cfg + cfg.summary.

**Bildirim:** `NotificationService.scheduleFeedReminder(... sound:)` — ana uyarı (feedMainId 800001, kesin alarm `exactAllowWhileIdle`) + opsiyonel ön-hatırlatma (feedPreId 800002). **Ses kanala bağlı (Android):** sesli → `feed_reminders` kanal, Importance.max/heads-up/playSound; sessiz → ayrı `feed_reminders_silent` kanal, Importance.low/playSound:false/vibrasyon yok. Ses tercihi ertele için bildirim **payload'ında** taşınır ('feed:1'/'feed:0') → foreground `_onResponse` `_feedSound` alanını, background `notificationBackgroundHandler` payload'ı okur. Kesin alarm için manifest `SCHEDULE_EXACT_ALARM` + `ActionBroadcastReceiver`, `requestExactAlarmsPermission` çağrılıyor. `sync()` cancelAll yerine yalnız reminder id'lerini iptal eder (feed 800xxx / sayaç 900xxx korunur).

**Tetikleme:** `_HomeScreenState.build` içinde feedReminder config + recentRecords izlenip her değişimde reschedule (her beslenme kaydında çapa güncellenir). Ayar UI: Hatırlatıcılar ekranı "Beslenme hatırlatıcısı" kartı + sheet. İlgili: [[suren-sayac-bildirimi]]
