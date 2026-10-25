import 'package:shared_preferences/shared_preferences.dart';

/// "Premium Karşılama Ekranı" (onboarding paywall) gösterim durumu.
///
/// Kural: kurulumdan sonra **bir kez**, ama kurulumun hemen ardından değil —
/// ilk anlamlı andan sonra: ilk kayıt yapıldığında; kayıt yapılmazsa ertesi
/// günün ilk açılışında. Kullanıcı kapatırsa bir daha ASLA gösterilmez.
///
/// Bayraklar SharedPreferences'ta (iOS NSUserDefaults → Keychain'in aksine
/// asla takılmaz):
/// - `pending`: bebek kuruldu, ekran daha açılmadı (+ `pending_at` günü).
/// - `shown`: ömür boyu bir kez gösterildi/tüketildi.
/// - `onboarded_at`: kurulumun tamamlandığı an (yedekleme uyarısı ilk günlerde
///   gösterilmesin diye).
class OnboardingPaywall {
  OnboardingPaywall._();

  static const _kPending = 'onboarding_paywall_pending';
  static const _kPendingAt = 'onboarding_paywall_pending_at';
  static const _kShown = 'onboarding_paywall_shown';
  static const _kOnboardedAt = 'onboarding_done_at';

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Bebek kurulumu (onboarding) tamamlandı → ekran sıraya alınır.
  /// Daha önce gösterildiyse hiçbir şey yapmaz.
  static Future<void> markPending({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kShown) == true) return;
      await prefs.setBool(_kPending, true);
      await prefs.setString(_kPendingAt, _day(now ?? DateTime.now()));
    } catch (_) {}
  }

  /// Sırada bekleyen gösterimi **tüketir**: true dönerse çağıran ekranı açar.
  /// [hasRecord] = kullanıcı ilk kaydını yaptı. Kayıt yoksa ancak kurulum
  /// gününden SONRAKİ bir günde tüketilir. İkinci tüketimde hep false
  /// (tek-kez garantisi; ekran açılmadan önce işaretlenir).
  static Future<bool> consume({required bool hasRecord, DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kShown) == true) return false;
      if (prefs.getBool(_kPending) != true) return false;
      final at = prefs.getString(_kPendingAt);
      // Eski sürümden kalan (tarihsiz) bekleyen bayrak → eskisi gibi hemen.
      final nextDay = at == null || _day(now ?? DateTime.now()).compareTo(at) > 0;
      if (!hasRecord && !nextDay) return false;
      await prefs.setBool(_kShown, true);
      await prefs.remove(_kPending);
      await prefs.remove(_kPendingAt);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// YALNIZ geliştirme (Geliştirici sayfası): bayrakları temizleyip ekranı
  /// yeniden sıraya alır — akışı baştan test edebilmek için (tarihsiz → hemen).
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kShown);
      await prefs.remove(_kPendingAt);
      await prefs.setBool(_kPending, true);
    } catch (_) {}
  }

  /// Gösterimi kalıcı olarak kapat (ör. kullanıcı zaten premium → hiç açma).
  static Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShown, true);
      await prefs.remove(_kPending);
      await prefs.remove(_kPendingAt);
    } catch (_) {}
  }

  /// Kurulum (bebek/gebelik/adet) tamamlandı — ilk kez yazılır, ezilmez.
  static Future<void> markOnboarded({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kOnboardedAt) != null) return;
      await prefs.setString(
          _kOnboardedAt, (now ?? DateTime.now()).toUtc().toIso8601String());
    } catch (_) {}
  }

  /// Kurulum başarısız olduysa (bebek oluşturulamadı) yazılan bayrakları geri
  /// al. [hadOnboarded]: deneme öncesi kurulum anı zaten var mıydı.
  static Future<void> rollbackSetup({required bool hadOnboarded}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPending);
      await prefs.remove(_kPendingAt);
      if (!hadOnboarded) await prefs.remove(_kOnboardedAt);
    } catch (_) {}
  }

  /// Kurulum anı (yoksa null — bu özellikten önce kurulmuş eski kullanıcı).
  static Future<DateTime?> onboardedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_kOnboardedAt);
      return s == null ? null : DateTime.tryParse(s)?.toLocal();
    } catch (_) {
      return null;
    }
  }
}
