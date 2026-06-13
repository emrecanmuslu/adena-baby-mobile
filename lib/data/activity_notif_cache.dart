import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Aile etkinlik bildirimi yerel durumu (cihaza özel, sunucuya gitmez):
///   • açık/kapalı tercihi (kişi başına, opt-in — varsayılan kapalı)
///   • bebek başına "en son görülen olay" zaman damgası (polling cursor'u)
/// Tema cache'i deseniyle aynı (FlutterSecureStorage).
class ActivityNotifCache {
  static const _storage = FlutterSecureStorage();
  static const _kEnabled = 'family_activity_notif_enabled';
  static String _kSeen(String babyId) => 'family_activity_seen_$babyId';

  Future<bool> enabled() async {
    try {
      return (await _storage.read(key: _kEnabled)) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool v) async {
    try {
      await _storage.write(key: _kEnabled, value: v ? '1' : '0');
    } catch (_) {}
  }

  Future<DateTime?> lastSeen(String babyId) async {
    try {
      final s = await _storage.read(key: _kSeen(babyId));
      return (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastSeen(String babyId, DateTime ts) async {
    try {
      await _storage.write(key: _kSeen(babyId), value: ts.toUtc().toIso8601String());
    } catch (_) {}
  }

  Future<void> clearSeen(String babyId) async {
    try {
      await _storage.delete(key: _kSeen(babyId));
    } catch (_) {}
  }
}
