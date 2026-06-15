import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// İlk-giriş tanıtım turlarının "görüldü" durumunu kalıcı saklar. Ekran başına
/// bir anahtar; tur bir kez gösterilir. Tek bir CSV değerinde tutulur.
class TourCache {
  static const _storage = FlutterSecureStorage();
  static const _k = 'tour_seen_v1';

  Future<Set<String>> read() async {
    try {
      final s = await _storage.read(key: _k);
      if (s == null || s.isEmpty) return <String>{};
      return s.split(',').where((e) => e.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> add(String key) async {
    final s = await read()..add(key);
    try {
      await _storage.write(key: _k, value: s.join(','));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _k);
    } catch (_) {}
  }
}
