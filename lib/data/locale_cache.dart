import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Son seçilen dili kalıcı saklar — açılışta ANINDA okunur (sunucu beklemeden).
/// Dil değişiminde uygulama yeniden başlatıldığı için, doğru dilin restart
/// sonrasında ve çevrimdışıyken de korunması bu cache'e bağlıdır. Sunucu değeri
/// gelince güncellenir. Değerler: 'tr' | 'en' | ...
class LocaleCache {
  static const _storage = FlutterSecureStorage();
  static const _kLocale = 'app_locale';

  Future<String?> read() async {
    try {
      final v = (await _storage.read(key: _kLocale))?.trim();
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String locale) async {
    try {
      await _storage.write(key: _kLocale, value: locale);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kLocale);
    } catch (_) {}
  }
}
