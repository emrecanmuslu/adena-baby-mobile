import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Açılış-kritik (gizli OLMAYAN) tercihler için ortak depo yardımcıları.
///
/// iOS'ta `SharedPreferences` = NSUserDefaults (plist). Keychain'in aksine soğuk
/// başlatmada / cihaz kilitten yeni çıkarken "protected data" beklemez → ASLA
/// takılmaz. Eski sürümlerde bu değerler `flutter_secure_storage` (Keychain)
/// içindeydi; aşağıdaki yardımcılar tek seferlik okuyup prefs'e taşır.
/// (Yalnız JWT token gibi GERÇEKTEN gizli veriler Keychain'de kalır.)
class LocalPrefs {
  static const _kc = FlutterSecureStorage();

  /// prefs'te [key] yoksa Keychain'den göç etmeyi dener.
  ///
  /// Dönüş: (değer, keychainOkunamadı). `keychainOkunamadı=true` → Keychain okuması
  /// hata/timeout verdi; **değer var olabilir ama okunamadı**, bu yüzden çağıran
  /// taraf YENİ bir değer ÜRETMEMELİDİR (ör. localUserId yetim kalmasın). Okuma
  /// temiz olur da değer gerçekten yoksa (null, false) döner → güvenle üretilebilir.
  static Future<(String?, bool)> migrateString(
      SharedPreferences prefs, String key) async {
    final cur = prefs.getString(key);
    if (cur != null) return (cur, false);
    try {
      final old = await _kc.read(key: key).timeout(const Duration(seconds: 2));
      if (old != null && old.isNotEmpty) {
        await prefs.setString(key, old);
        await _kc.delete(key: key); // göç tamam → Keychain'i temizle
      }
      return (old, false);
    } catch (_) {
      return (null, true); // Keychain takıldı/hata → çağıran üretmesin
    }
  }
}
