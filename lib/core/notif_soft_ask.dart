import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bildirim "ön-izni" (uygulama içi soru) durumu.
///
/// Kural: sistem izin penceresi ASLA bağlamsız açılmaz — önce uygulama içi
/// alt sayfa ("Sonraki beslenmeyi hatırlatalım mı?") sorulur; sistem
/// penceresi yalnız kullanıcı "Bildirimleri aç" derse açılır.
/// - `asked` / `asked_at`: ön-izin soruldu (ne zaman).
/// - `accepted`: kullanıcı "Bildirimleri aç" dedi → otomatik planlayıcılar
///   gerektiğinde sistem iznini isteyebilir.
class NotifSoftAsk {
  NotifSoftAsk._();

  static const _kAsked = 'notif_soft_ask_asked';
  static const _kAskedAt = 'notif_soft_ask_asked_at';
  static const _kAccepted = 'notif_soft_ask_accepted';

  /// "Şimdi değil" denmiş ön-izin, bildirim gerektiren bir planlama olursa
  /// bu süre sonra yeniden sorulabilir (kullanıcı hatırlatıcı/ilaç kurduysa
  /// bildirimlerin sessizce hiç gelmemesi daha kötü).
  static const reAskAfter = Duration(days: 7);

  /// Bir planlayıcı bildirim gerektirdi ama izin yok ve ön-izin henüz
  /// kabul edilmedi → asıl ekranlar (ana sayfa / Adet Takvimi) bunu dinler ve
  /// uygun anda ön-izni gösterir. Değer artan sayaçtır.
  static final ValueNotifier<int> wanted = ValueNotifier<int>(0);

  static void requestLater() => wanted.value++;

  static Future<bool> asked() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_kAsked) ?? false;
    } catch (_) {
      return true; // okunamıyorsa sorma
    }
  }

  static Future<bool> accepted() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_kAccepted) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Planlama nedeniyle ön-izin şimdi sorulabilir mi: hiç sorulmadıysa ya da
  /// reddedileli [reAskAfter] geçtiyse (kabul edildiyse sormaya gerek yok).
  static Future<bool> mayAskAgain({DateTime? now}) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_kAccepted) == true) return false;
      if (p.getBool(_kAsked) != true) return true;
      final at = DateTime.tryParse(p.getString(_kAskedAt) ?? '');
      return at == null || (now ?? DateTime.now()).difference(at) >= reAskAfter;
    } catch (_) {
      return false;
    }
  }

  static Future<void> record({required bool accepted, DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAsked, true);
      await prefs.setString(
          _kAskedAt, (now ?? DateTime.now()).toUtc().toIso8601String());
      if (accepted) await prefs.setBool(_kAccepted, true);
    } catch (_) {}
  }
}
