import '../data/i18n_repository.dart';
import '../data/locale_cache.dart';
import 'i18n.dart';

/// M7 (D17) — arka plan isolate'leri (FCM bg işleyicisi, workmanager/BGTask
/// turu, bildirim "Ertele" eylemi) ana isolate'in I18n sözlüğünü paylaşmaz;
/// orada üretilen bildirim metinleri ("Kaydı unuttun mu?", "Ertele 10 dk",
/// kanal adları) Türkçe gidiyordu. Prefs'teki dil + diskteki çeviri cache'i
/// ucuzdur (bir prefs okuması + bir dosya) → bg girişlerinde bir kez ısıtılır.
/// Ağ YOK; cache yoksa Türkçe kalır (sunucu sözlüğü ön planda indirilir).
Future<void> warmI18nFromCache() async {
  try {
    // J13: bg'de Keychain'e hiç dokunma (saf prefs okuması).
    final locale = await LocaleCache().readPrefsOnly() ?? 'tr';
    if (locale == 'tr') {
      I18n.instance.apply('tr', const {});
      return;
    }
    final (_, strings) = await I18nRepository.readCachedStrings(locale);
    I18n.instance.apply(locale, strings);
  } catch (_) {
    // Prefs/dosya hatası → mevcut (TR) sözlükle devam.
  }
}
