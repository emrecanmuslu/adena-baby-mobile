import 'package:flutter/foundation.dart';
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

  /// "Bu anahtar için Keychain'de değer YOK — temiz bir okumayla kanıtlandı"
  /// işareti (prefs). Hiç yazılmamış anahtarlarda (ör. opsiyonel analitik rızası,
  /// seçilmemiş tema) `prefs.getString` her açılışta null döndüğü için göç denemesi
  /// SÜREKLİ tekrarlanıyordu; yavaş Android cihazlarda Keystore ilk açılışı 2 sn'lik
  /// timeout'a takılıp açılış adımını 5 sn sınırına dayıyordu (Crashlytics:
  /// `startup_timeout: session+slots`, 25 kullanıcı). İşaret konduktan sonra o
  /// anahtar için Keychain'e bir daha HİÇ dokunulmaz.
  static String _seenKey(String key) => 'kcx_$key';

  /// Bu süreçte Keychain okuması bir kez takıldı/hata verdi → aynı açılışta kalan
  /// anahtarlar için tekrar 2 sn beklemenin anlamı yok (kanal zaten tıkalı).
  /// Anlamsal olarak "okunamadı" (=true) döndürmeye devam ederiz → çağıran taraf
  /// yeni değer ÜRETMEZ (localUserId yetim kalmasın).
  static bool _kcUnavailable = false;

  /// Yalnız testler için: süreç-statik "Keychain erişilemiyor" bayrağını sıfırlar.
  @visibleForTesting
  static void resetForTests() => _kcUnavailable = false;

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
    // Daha önce temiz okuduk ve Keychain'de yoktu → bir daha sorma (hızlı yol).
    if (prefs.getBool(_seenKey(key)) == true) return (null, false);
    // Bu açılışta Keychain zaten cevap vermiyor → boşuna bekleme.
    if (_kcUnavailable) return (null, true);
    try {
      final old = await _kc.read(key: key).timeout(const Duration(seconds: 2));
      if (old != null && old.isNotEmpty) {
        await prefs.setString(key, old);
        await _kc.delete(key: key); // göç tamam → Keychain'i temizle
        return (old, false);
      }
      // Temiz okuma + değer yok → kalıcı olarak işaretle, bir daha bakma.
      await prefs.setBool(_seenKey(key), true);
      return (old, false);
    } catch (_) {
      _kcUnavailable = true;
      return (null, true); // Keychain takıldı/hata → çağıran üretmesin
    }
  }
}
