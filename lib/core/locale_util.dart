import 'dart:ui';

/// Cihaz bölgesine/diline göre varsayılanlar. Kullanıcı henüz tercih yapmamışken
/// (ilk açılış / sunucuda dil-birim ayarı yokken) ilk değerleri buradan seçeriz;
/// kullanıcı ayarlardan her zaman değiştirebilir.

/// Cihaza göre varsayılan uygulama dili. KURAL: yalnız Türkiye → 'tr';
/// Türkiye dışı her zaman 'en'e düşer. Bölge (ülke) bilinmiyorsa cihaz diline
/// bakılır (tr → tr). Sunucudaki Country tablosu da aynı kuralı uygular
/// (yalnız TR translated=tr; gerisi 'en'e fallback).
String deviceDefaultLanguage() {
  final l = PlatformDispatcher.instance.locale;
  final country = l.countryCode?.toUpperCase();
  if (country != null) return country == 'TR' ? 'tr' : 'en';
  // Ülke bilinmiyorsa dile düş: yalnız Türkçe → tr.
  return l.languageCode.toLowerCase() == 'tr' ? 'tr' : 'en';
}

/// Cihaz bölgesi imperial birim kullanıyor mu (ABD, Liberya, Myanmar).
/// Bu ülkeler dışında her yerde metrik varsayılır.
bool deviceUsesImperial() {
  final cc = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
  return cc == 'US' || cc == 'LR' || cc == 'MM';
}
