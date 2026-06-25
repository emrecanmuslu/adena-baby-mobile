import 'package:shared_preferences/shared_preferences.dart';

/// TANI-GEÇİCİ (kullanıcı "kaldır" deyince SİL): warm-resume'da Home bayat /
/// "API'ye sync etmedi" sorununu cihazda yakalamak için sync/auth/bg-sync izleri.
///
/// SharedPreferences'a halka-tampon olarak yazar; HEM ön plan HEM arka plan
/// isolate'i yazabilir ([FeedReminderCache]/[ActivityNotifCache] ile aynı desen —
/// `reload()` ile diğer isolate'in yazdığı görülür). Ön plan resume'da [readAll]
/// ile okuyup Crashlytics'e TEK non-fatal olarak basar (bkz main.dart _onForeground).
/// Tüm çağrı yerleri `TANI-GEÇİCİ` ile işaretli → `grep -rn "TANI-GEÇİCİ"` ile temizle.
class SyncDiag {
  static const _key = 'tani_sync_diag';
  static const _max = 80; // son ~80 satır yeter (1 gece + sabah birkaç resume)

  /// Tek satır iz ekler (otomatik 'MM-ddTHH:mm:ss' damgalı). Asla patlamaz.
  static Future<void> add(String line) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload(); // başka isolate'in (bg sync) yazdıklarını da gör
      final list = p.getStringList(_key) ?? <String>[];
      final ts = DateTime.now().toIso8601String().substring(5, 19); // MM-ddTHH:mm:ss
      list.add('$ts $line');
      if (list.length > _max) list.removeRange(0, list.length - _max);
      await p.setStringList(_key, list);
    } catch (_) {
      // tanı izi — hiçbir koşulda akışı bozmamalı
    }
  }

  /// Birikmiş tüm izleri döner (ön plan resume'da Crashlytics'e basmak için).
  static Future<List<String>> readAll() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      return p.getStringList(_key) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  /// İzleri temizler (Crashlytics'e bastıktan sonra → aynı satırlar tekrar gitmesin).
  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}
