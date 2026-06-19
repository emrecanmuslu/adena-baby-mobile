import 'dart:ui';

import 'package:flutter/widgets.dart';

/// Cihaz bölgesine/diline göre varsayılanlar. Kullanıcı henüz tercih yapmamışken
/// (ilk açılış / sunucuda dil-birim ayarı yokken) ilk değerleri buradan seçeriz;
/// kullanıcı ayarlardan her zaman değiştirebilir.

/// Cihaz locale'ini binding'in platform dispatcher'ı üzerinden okur. Çalışma
/// anında bu, `PlatformDispatcher.instance` ile AYNI nesnedir (davranış birebir),
/// ancak testte `TestWidgetsFlutterBinding` sahte locale enjekte edebilsin diye
/// binding köprüsünden geçer. Tüm çağrılar binding init sonrası olduğundan
/// `WidgetsBinding.instance` her zaman mevcuttur; yine de binding'in gerçekten
/// bulunmadığı (init öncesi) olası durum için dart:ui singleton'ına düşeriz.
Locale _deviceLocale() {
  try {
    return WidgetsBinding.instance.platformDispatcher.locale;
  } catch (_) {
    return PlatformDispatcher.instance.locale;
  }
}

/// Cihaza göre varsayılan uygulama dili. KURAL: yalnız Türkiye → 'tr';
/// Türkiye dışı her zaman 'en'e düşer. Bölge (ülke) bilinmiyorsa cihaz diline
/// bakılır (tr → tr). Sunucudaki Country tablosu da aynı kuralı uygular
/// (yalnız TR translated=tr; gerisi 'en'e fallback).
String deviceDefaultLanguage() {
  final l = _deviceLocale();
  final country = l.countryCode?.toUpperCase();
  if (country != null) return country == 'TR' ? 'tr' : 'en';
  // Ülke bilinmiyorsa dile düş: yalnız Türkçe → tr.
  return l.languageCode.toLowerCase() == 'tr' ? 'tr' : 'en';
}

/// Cihaz bölgesi imperial birim kullanıyor mu (ABD, Liberya, Myanmar).
/// Bu ülkeler dışında her yerde metrik varsayılır.
bool deviceUsesImperial() {
  final cc = _deviceLocale().countryCode?.toUpperCase();
  return cc == 'US' || cc == 'LR' || cc == 'MM';
}
