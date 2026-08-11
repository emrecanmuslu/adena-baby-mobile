import 'package:shared_preferences/shared_preferences.dart';

/// "Premium Karşılama Ekranı" (onboarding paywall) gösterim durumu.
///
/// Kural: bebek kurulumu bitince **bir kez** açılır, kullanıcı kapatırsa bir
/// daha ASLA gösterilmez (tekrar gösterim yok — ürün kararı).
///
/// İki bayrak SharedPreferences'ta (AdService/ReviewService ile aynı kalıcılık;
/// iOS'ta NSUserDefaults → Keychain'in aksine asla takılmaz):
/// - `pending`: bebek kuruldu, ekran daha açılmadı (ana sayfa ilk kareyi
///   çizince tüketilir — kurulum ekranından push etmek router redirect'iyle
///   yarışırdı).
/// - `shown`: ömür boyu bir kez gösterildi/tüketildi.
class OnboardingPaywall {
  OnboardingPaywall._();

  static const _kPending = 'onboarding_paywall_pending';
  static const _kShown = 'onboarding_paywall_shown';

  /// Bebek kurulumu (onboarding) tamamlandı → ekran sıraya alınır.
  /// Daha önce gösterildiyse hiçbir şey yapmaz.
  static Future<void> markPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kShown) == true) return;
      await prefs.setBool(_kPending, true);
    } catch (_) {}
  }

  /// Sırada bekleyen gösterimi **tüketir**: true dönerse çağıran ekranı açar.
  /// İkinci çağrıda hep false döner (tek-kez garantisi; ekran açılmadan önce
  /// işaretlenir — uygulama tam o anda kapanırsa da döngüye girilmez).
  static Future<bool> consume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kShown) == true) return false;
      if (prefs.getBool(_kPending) != true) return false;
      await prefs.setBool(_kShown, true);
      await prefs.remove(_kPending);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// YALNIZ geliştirme (Geliştirici sayfası): bayrakları temizleyip ekranı
  /// yeniden sıraya alır — akışı baştan test edebilmek için.
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kShown);
      await prefs.setBool(_kPending, true);
    } catch (_) {}
  }

  /// Gösterimi kalıcı olarak kapat (ör. kullanıcı zaten premium → hiç açma).
  static Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShown, true);
      await prefs.remove(_kPending);
    } catch (_) {}
  }
}
