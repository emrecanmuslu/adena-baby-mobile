---
name: dil-degisince-app-restart
description: Dil değişince RestartWidget ile uygulama ağacı sıfırlanır + LocaleCache kalıcı seçim
metadata: 
  node_type: memory
  type: project
  originSessionId: c8fd0cab-3779-43f7-85b9-7e3b0f3da6f9
---

Görünüm ekranından dil seçilince uygulama yeniden başlatılır: `core/restart_widget.dart` (`RestartWidget` kök ağacı UniqueKey ile sıfırlar) `main.dart`'ta ProviderScope'u sarar; appearance_screen dil seçince `setLocale` → `RestartWidget.restartApp(context)`. Sebep: `AnimatedBuilder(I18n.instance)` rebuild'i const/önceden-build ekranlara ulaşmıyordu, metinler yeni dilde değerlenmiyordu.

`data/locale_cache.dart` (`LocaleCache`, secure storage) seçilen dili kalıcı saklar; `LocaleController.build()` önce cache'i okur (restart sonrası + çevrimdışı güvenli), cache yoksa sunucu ayarına düşer. Not: cross-device dil senkronu artık startup'ta yerel seçime öncelik verir (cache varsa sunucu okunmaz). Bkz [[i18n-ceviri-sistemi]], [[gorunum-birimler-birlesti]].
