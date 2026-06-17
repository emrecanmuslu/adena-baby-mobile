---
name: hatirlatici-sistemi
description: Genel hatırlatıcı sistemi — özel (custom) + randevu (appt) hatırlatıcı; tek-seferlik & günlük schedule; randevu sheet entegrasyonu
metadata: 
  node_type: memory
  type: project
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

2026-06-11'de hatırlatıcı sistemi sadeleştirilip güçlendirildi (kullanıcı istedi). Eski 3 sabit tip (vitamin/aşı/dürtükleme) yerine **dinamik özel hatırlatıcı** + **randevu hatırlatıcısı**. Aşı/Dürtükleme zaten hiç bildirim atmıyordu (notification_service uygulamıyordu) — kaldırıldı, gerek görülmedi.

**schedule iki şekil (tür değil, ŞEKİL belirler):**
- Günlük: `{repeat:'daily', time:'HH:MM', title?}` → her gün o saat (matchDateTimeComponents.time)
- Tek-sefer: `{repeat:'once', at:ISO8601, title?}` → o anda bir kez, kesin alarm; geçmişse kurulmaz

`NotificationService.sync(reminders)` artık şekil-tabanlı (`notification_service.dart`): `_scheduleDaily(id,h,m,title)` ve `_scheduleOnce(id,when,title)`. Eski days_before/idle_hours şekilleri atlanır. Bildirim id = sunucu reminder.id (küçük int; feed 800xxx / sayaç 900xxx ile çakışmaz).

**"Hatırlatıcı ekle" sheet** (`reminders_screen.dart` `_AddReminderSheet`): Başlık + Tekrar (Her gün / Bir kez) + saat ya da tarih-saat seçici → `createReminder(type:'custom', schedule)`. `_typeLabel`/`_scheduleLabel`/`_typeVisual` custom+appt için güncellendi (başlık schedule'dan, zaman etiketi at/time'dan). `_StepRow` kaldırıldı.

**Randevu sheet entegrasyonu** (`record_form.dart` appointment dalı): "Hatırlatıcı kur" anahtarı (yeni randevuda varsayılan AÇIK — tasarım ScrDoctor "1 gün önce") + süre AdTabs {30 dk / 1 saat / 1 gün / Özel(saat stepper `_LeadStepRow`)}. Kaydedince `_syncApptReminder(data)`: eski reminder'ı (data['reminder_id']) siler, açıksa ve fireAt(=_ts − lead) gelecekteyse `createReminder(type:'appt', schedule:{repeat:'once', at, title:'Randevu: …', lead_min})` kurar, id+lead'i record.data'ya yazar (düzenlemede bulunsun), sonra `NotificationService.sync`. Böylece randevu hatırlatıcısı **Hatırlatıcılar ekranında listelenir ve silinebilir**. bkz [[bilgi-rozeti-ilkesi]] (alanlara info eklendi)

**Backend:** `Reminder.TYPES`'a `appt`+`custom` eklendi (max_length=10 yeterli), migration `0002_alter_reminder_type` **uygulandı**. Migration sonrası **Django restart** gerekir. bkz [[api-degisiklik-izni]]

**Bilinen sınır:** Genel reminder'lar yalnız Hatırlatıcılar ekranı açılınca sync olur (home sadece feed sync'ler); randevu yolunda explicit sync var. Randevu kaydı silinirse bağlı reminder otomatik silinmez (v1).
