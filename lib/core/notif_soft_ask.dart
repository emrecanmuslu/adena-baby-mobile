import 'package:shared_preferences/shared_preferences.dart';

/// Bildirim "ön-izni" (uygulama içi soru) durumu.
///
/// Kural: sistem izin penceresi ASLA bağlamsız açılmaz — önce uygulama içi
/// alt sayfa ("Sonraki beslenmeyi hatırlatalım mı?") sorulur; sistem
/// penceresi yalnız kullanıcı "Bildirimleri aç" derse açılır.
/// - `asked`: ön-izin bir kez soruldu (yanıt ne olursa olsun tekrar sorulmaz).
/// - `accepted`: kullanıcı "Bildirimleri aç" dedi → otomatik planlayıcılar
///   gerektiğinde sistem iznini isteyebilir.
class NotifSoftAsk {
  NotifSoftAsk._();

  static const _kAsked = 'notif_soft_ask_asked';
  static const _kAccepted = 'notif_soft_ask_accepted';

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

  static Future<void> record({required bool accepted}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAsked, true);
      if (accepted) await prefs.setBool(_kAccepted, true);
    } catch (_) {}
  }
}
