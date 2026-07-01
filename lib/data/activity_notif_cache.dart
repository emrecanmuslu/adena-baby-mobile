import 'package:shared_preferences/shared_preferences.dart';

import 'local_prefs.dart';

/// Aile etkinlik bildirimi yerel durumu (cihaza özel; tercih sunucuya da senkronlanır):
///   • açık/kapalı tercihi (kişi başına, varsayılan AÇIK — yalnız açıkça kapatılırsa kapalı)
///   • bebek başına "en son görülen olay" zaman damgası (polling cursor'u)
///
/// Depo: SharedPreferences (iOS NSUserDefaults). Eskiden Keychain'deydi; iOS'ta
/// push/warm-resume sırasında Keychain takılması çift bildirim / yanlış cursor'a
/// yol açabiliyordu → prefs'e taşındı (eski Keychain değerleri tek seferlik göç).
class ActivityNotifCache {
  static const _kEnabled = 'family_activity_notif_enabled';
  static String _kSeen(String babyId) => 'family_activity_seen_$babyId';

  Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Varsayılan AÇIK: yalnız kullanıcı açıkça kapatmışsa ('0') kapalı.
      final (v, _) = await LocalPrefs.migrateString(prefs, _kEnabled);
      return v != '0';
    } catch (_) {
      return true;
    }
  }

  Future<void> setEnabled(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEnabled, v ? '1' : '0');
    } catch (_) {}
  }

  Future<DateTime?> lastSeen(String babyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final (s, _) = await LocalPrefs.migrateString(prefs, _kSeen(babyId));
      return (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastSeen(String babyId, DateTime ts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSeen(babyId), ts.toUtc().toIso8601String());
    } catch (_) {}
  }

  Future<void> clearSeen(String babyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kSeen(babyId));
    } catch (_) {}
  }
}
