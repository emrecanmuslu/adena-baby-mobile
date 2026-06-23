import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Geliştirici ortam değiştirici (YALNIZ debug) — seçili API tabanını kalıcı
/// saklar. null/boş = derleme varsayılanı. Açılışta AppConfig'e uygulanır.
class EnvCache {
  static const _storage = FlutterSecureStorage();
  static const _kEnv = 'dev_api_base_url';

  Future<String?> read() async {
    try {
      final v = await _storage.read(key: _kEnv);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String url) async {
    try {
      await _storage.write(key: _kEnv, value: url);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kEnv);
    } catch (_) {}
  }
}
