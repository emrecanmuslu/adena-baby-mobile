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
  static const _kNotified = 'family_activity_notified_ids';
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

  /// Bir aktivite olayı için bildirim gösterilmeli mi? İlk kez görülüyorsa kaydeder
  /// ve true döner; daha önce gösterildiyse (push VEYA polling tarafından) false.
  /// Push ve polling aynı olayı YARIŞ içinde işleyebildiğinden çift bildirimi bu
  /// olay-id dedup'ı engeller. Son 100 id tutulur (UUID'ler, virgülle ayrık).
  Future<bool> markNotifiedIfNew(String eventId) async {
    if (eventId.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final (raw, _) = await LocalPrefs.migrateString(prefs, _kNotified);
      final ids = (raw == null || raw.isEmpty) ? <String>[] : raw.split(',');
      if (ids.contains(eventId)) return false;
      ids.add(eventId);
      final trimmed = ids.length > 100 ? ids.sublist(ids.length - 100) : ids;
      await prefs.setString(_kNotified, trimmed.join(','));
      return true;
    } catch (_) {
      return true; // hata → kaçırmaktansa göster
    }
  }
}
