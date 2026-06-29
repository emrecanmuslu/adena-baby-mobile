import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_reminder.dart';

/// Beslenme hatırlatıcı ayarının CİHAZ-YEREL kalıcı deposu (bebek başına).
///
/// Önceden bu ayar sunucudaki `FamilySettings.feed_reminder` alanında PAYLAŞIMLI
/// tutuluyordu → tüm aile üyeleri aynı aralığı paylaşıyordu (son yazan kazanır);
/// anne aralığı 2 saate çekince başka üyeninki de 2 saat oluyordu. Artık her cihaz
/// kendi hatırlatıcı tercihini saklar: anne 3 saat, baba 2 saat bağımsız.
///
/// Depo: SharedPreferences (gizli değil) — [FeedReminderCache] (arka plan push'un
/// okuduğu snapshot) bu değerden türetilir; bu store ise UI'ın okuyup yazdığı
/// kaynak gerçektir. Tüm beslenme hatırlatıcı kayıtlarını tek seferde okur.
class FeedReminderStore {
  static const _prefix = 'feed_reminder_cfg_';
  static String _key(String babyId) => '$_prefix$babyId';

  Future<Map<String, FeedReminderConfig>> readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final out = <String, FeedReminderConfig>{};
      for (final k in prefs.getKeys()) {
        if (!k.startsWith(_prefix)) continue;
        final raw = prefs.getString(k);
        if (raw == null || raw.isEmpty) continue;
        final babyId = k.substring(_prefix.length);
        out[babyId] =
            FeedReminderConfig.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> write(String babyId, FeedReminderConfig cfg) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(babyId), jsonEncode(cfg.toMap()));
    } catch (_) {}
  }
}
