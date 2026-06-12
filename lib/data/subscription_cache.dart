import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Son bilinen premium durumunu kalıcı saklar — açılışta ANINDA (flaş'sız) okunur,
/// API gelince güncellenir. Böylece premium kullanıcıya hiçbir ekranda rozet/kilit
/// flaş'ı görünmez.
class SubscriptionCache {
  static const _storage = FlutterSecureStorage();
  static const _kPremium = 'sub_is_premium';

  Future<bool> read() async {
    try {
      return (await _storage.read(key: _kPremium)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> write(bool isPremium) async {
    try {
      await _storage.write(key: _kPremium, value: isPremium ? '1' : '0');
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kPremium);
    } catch (_) {}
  }
}
