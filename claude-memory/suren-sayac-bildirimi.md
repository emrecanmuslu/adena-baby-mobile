---
name: suren-sayac-bildirimi
description: "Uyku/emzirme süren sayaçları için cihaz bildirimi — kronometre yöntemi, foreground service YOK (bilinçli karar)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 51705ee7-5832-41ca-b19e-8c7ff489b39a
---

Süren uyku ve emzirme sayaçları, uygulama içi sayaca ek olarak **cihaz bildiriminde** de gösterilir (kullanıcı 2026-06-11'de istedi).

**Mimari karar (kullanıcı onayladı):** Android `usesChronometer` ile **kronometre bildirimi** kullanılıyor; **foreground service KULLANILMIYOR** ve bildirim üzerinde aksiyon butonu YOK (dokun → uygulama açılır). `NotificationService.showTimer/cancelTimer` (`lib/core/notification_service.dart`, 'timers' kanalı, low importance, ongoing). Tetikleme: `_HomeScreenState.build` içinde `ongoingSleepProvider`/`ongoingBreastProvider` izlenip `_syncSleepTimer/_syncBreastTimer` çağrılıyor (her sekmede ayakta).

**Bilinen sınır (hata değil):** Sistem uygulamayı tamamen öldürürse bildirim güncellenmeyebilir. "Öldürülse bile yaşasın" istenirse `flutter_foreground_task` ile gerçek servise geçmek gerekir — bilinçli olarak ertelendi. iOS'ta canlı sayan bildirim (Live Activity) ayrı/karmaşık; şimdilik Android odaklı.

Emzirme bildirimi **toplam** süreyi sayar (sol+sağ, aktif segment dahil); duraklatınca kronometre durur, süre body'de kalır. İlgili: [[manuel-test-tercihi]]
