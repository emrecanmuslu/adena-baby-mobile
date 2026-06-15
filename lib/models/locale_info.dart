// Sunucu-yönetimli dil + ülke bilgisi (GET /i18n/locales, /i18n/countries).
// Yeni dil/ülke eklenince uygulama güncellemesi gerekmeden yansır.

class SupportedLocale {
  final String code; // tr, en, de
  final String nativeName; // Türkçe, English
  final String englishName; // Turkish, English
  final bool isDefault;

  const SupportedLocale({
    required this.code,
    required this.nativeName,
    required this.englishName,
    this.isDefault = false,
  });

  factory SupportedLocale.fromJson(Map<String, dynamic> j) => SupportedLocale(
        code: j['code'] as String,
        nativeName: (j['native_name'] as String?) ?? (j['code'] as String),
        englishName: (j['english_name'] as String?) ?? (j['code'] as String),
        isDefault: (j['is_default'] as bool?) ?? false,
      );
}

class CountryInfo {
  final String code; // ISO2: TR, US
  final String name;
  final String dialCode; // +90
  final String currency; // TRY, USD
  final bool usesImperial;
  final String locale; // bu ülke için çözülen uygulama dili (çeviri yoksa 'en')
  final bool translated;
  final bool salesEnabled;

  const CountryInfo({
    required this.code,
    required this.name,
    required this.dialCode,
    required this.currency,
    required this.usesImperial,
    required this.locale,
    required this.translated,
    required this.salesEnabled,
  });

  factory CountryInfo.fromJson(Map<String, dynamic> j) => CountryInfo(
        code: j['code'] as String,
        name: (j['name'] as String?) ?? '',
        dialCode: (j['dial_code'] as String?) ?? '',
        currency: (j['currency'] as String?) ?? '',
        usesImperial: (j['uses_imperial'] as bool?) ?? false,
        locale: (j['locale'] as String?) ?? 'en',
        translated: (j['translated'] as bool?) ?? false,
        salesEnabled: (j['sales_enabled'] as bool?) ?? true,
      );
}
