---
name: sessiz-saat
description: "Sessiz saat (quiet hours) — zaman pencereli bildirim susturma; Sesli/Sessiz toggle'dan farklı, her zaman kazanır"
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

Sessiz saat = **zamana bağlı** bildirim susturma (kullanıcı 2026-06-11'de istedi). [[beslenme-hatirlatici]]'daki Sesli/Sessiz toggle'dan farkı: toggle her zaman geçerli (hep sesli / hep sessiz), sessiz saat sadece belirlenen saat aralığında etkili.

**Kullanıcı kararları:** (1) Pencerede bildirim **sessizce gelir** (ses/titreşim yok ama yine düşer), bastırılmaz. (2) Sessiz saat **her zaman kazanır** — alarm "Sesli" olsa bile pencerede sessiz. Efektif ses = `soundEnabled && !quiet.covers(bildirimAnı)`.

**Model:** `models/quiet_hours.dart` `QuietHours{enabled, startMin, endMin}` (dakika/gün-içi, varsayılan 22:00–07:00, kapalı). `covers(DateTime)` gece yarısını aşan aralığı destekler (startMin>endMin → `m>=start || m<end`). `hhmm()`/`label`/`summary` yardımcıları.

**Provider:** `family_settings.dart` `quietHoursProvider` + `updateQuietHours` (family-settings `quiet_hours` JSON alanı, units/feed_reminder gibi kısmi PATCH).

**Uygulanışı:** `NotificationService.scheduleFeedReminder(... quiet:)` — ana uyarı ve ön-hatırlatma AYRI zamanlarda olduğu için her biri için efektif ses ayrı hesaplanır. Şu an SADECE beslenme hatırlatıcısına uygulanıyor (tek sesli bildirim o); vitamin/günlük reminder'lar henüz dahil değil. Home `_syncFeedReminder` quietHoursProvider'ı izleyip geçer (ayar değişince reschedule).

**UI:** Hatırlatıcılar ekranı "Sessiz saat" kartı (`_QuietHoursCard`, moon ikonu + sleep rengi) + `showQuietHoursSheet`/`_QuietHoursSheet` (başlıkta aç/kapa switch + Başlangıç/Bitiş `showTimePicker` alanları + Kaydet).

**Backend:** `FamilySettings.quiet_hours` JSONField eklendi, migration `0004_familysettings_quiet_hours` **uygulandı** (migrate OK, check temiz). Migration sonrası **Django restart** gerekir. bkz [[api-degisiklik-izni]]
