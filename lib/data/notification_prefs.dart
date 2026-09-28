import 'package:shared_preferences/shared_preferences.dart';

/// Bildirim GÖRÜNÜRLÜĞÜ tercihleri (cihaz-yerel). "Ayarlar & Profil → Bildirimler"
/// sayfasının kaynağıdır.
///
/// KRİTİK KURAL — yalnız GÖRÜNÜRLÜK kapanır, veri akışı DEĞİL: push mesajları
/// cihaza gelmeye devam eder ve sessizce işlenir (senkron tetiği, ana ekran
/// widget'ı, beslenme hatırlatıcısının yeniden planlanması). Kapatılan tek şey
/// bildirimin gösterilmesidir → aile paylaşımında veri KAYBOLMAZ. Tek istisna
/// iPhone'da force-quit durumu (bkz. Bildirimler sayfasındaki uyarı kartı).
///
/// Depo: SharedPreferences (iOS NSUserDefaults) — arka plan isolate'ı (FCM push
/// işleyici) da okuyabilsin diye Keychain DEĞİL. Yeni anahtarlar olduğu için
/// [LocalPrefs.migrateString] göçü gerekmez (boşuna Keychain okuması yapmayalım;
/// arka planda takılabiliyor).
///
/// Varsayılan: TÜMÜ AÇIK — yalnız kullanıcı açıkça kapatırsa ('0') kapalıdır.
/// Böylece güncelleyen mevcut kullanıcının davranışı değişmez.
class NotificationPrefs {
  NotificationPrefs._();
  static final NotificationPrefs instance = NotificationPrefs._();

  /// Süren uyku/emzirme sayacının kalıcı bildirimi (kronometreli, sessiz kanal).
  static const timers = 'notif_timers';

  /// Topluluk bildirimleri — sorumuza cevap geldi / cevabımız "en iyi" seçildi.
  static const community = 'notif_community';

  /// Ön planda çıkan uygulama-içi üst banner (push geldiğinde).
  static const inAppBanner = 'notif_in_app_banner';

  // ── Sağlık modülü hatırlatıcıları (yerelde hesaplanır, bebek verisine göre
  // otomatik planlanır — kullanıcı zamanlama girmez, yalnız aç/kapa yapar). ──

  /// En yakın (zorunlu, yapılmamış) aşının tarihinde tek seferlik hatırlatma.
  static const vaccine = 'notif_vaccine';

  /// Bir sonraki gelişim atağı yaklaşırken (huzursuz öncesi pencere) hatırlatma.
  static const leap = 'notif_leap';

  /// Son ölçümden ~30 gün sonra "büyüme ölçümü gir" dürtmesi.
  static const growth = 'notif_growth';

  /// Gebelikte her hafta değişince (bekleme modu) hatırlatma.
  static const pregnancyWeek = 'notif_pregnancy_week';

  /// Gelişim basamaklarını işaretlemeyi unutmamak için periyodik dürtme.
  static const milestone = 'notif_milestone';

  /// Diş çıkışlarını işaretlemeyi unutmamak için periyodik dürtme (min. tipik
  /// diş ayından itibaren).
  static const tooth = 'notif_tooth';

  /// Her ilaç/vitamin planının günlük saatinde hatırlatma.
  static const medication = 'notif_medication';

  /// Bu sınıfın yönettiği tüm anahtarlar (toplu okuma için).
  static const all = [
    timers, community, inAppBanner,
    vaccine, leap, growth, pregnancyWeek, milestone, tooth, medication,
  ];

  Future<bool> enabled(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) != '0';
    } catch (_) {
      return true; // okunamazsa bildirimi göster (sessizce kaybetme)
    }
  }

  Future<void> setEnabled(String key, bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, v ? '1' : '0');
    } catch (_) {}
  }

  /// Tüm tercihleri tek seferde okur (UI açılışı için).
  Future<Map<String, bool>> readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {for (final k in all) k: prefs.getString(k) != '0'};
    } catch (_) {
      return {for (final k in all) k: true};
    }
  }
}
