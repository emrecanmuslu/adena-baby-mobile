import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT token'larını güvenli (şifreli) depolar.
class TokenStorage {
  // iOS accessibility VARSAYILAN (whenUnlocked). `first_unlock`'a geçmek mevcut
  // kayıtla migration çakışması yaratıp güncelleme sonrası login'i patlatıyordu →
  // dokunulmuyor. Açılış donmasının çözümü: okuma fırlarsa RETRY + en sonunda null
  // (aşağıda). Bkz [[acilis-donmasi-keychain-fix]] [[home-bayat-yarin-kontrol]].
  static const _storage = FlutterSecureStorage();
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  Future<void> saveTokens({required String access, String? refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    if (refresh != null) {
      await _storage.write(key: _kRefresh, value: refresh);
    }
  }

  /// Keychain okuması iOS'ta soğuk başlatmada GEÇİCİ olarak FIRLATABİLİR (kilit/
  /// first-unlock geçişi, push isolate çakışması). Fırlarsa kısa backoff'la YENİDEN
  /// DENE — geçici hata genelde ~1-2 sn içinde geçer → mevcut oturumlu kullanıcı
  /// yanlışlıkla giriş ekranına DÜŞMESİN. Genuine "anahtar yok" (read null döner,
  /// fırlatmaz) → RETRY YOK, hemen null. Tüm denemeler fırlarsa null (asla
  /// yakalanmamış fatal/donma; en kötü ihtimal: giriş ekranı, sonraki açılış düzeltir).
  Future<String?> _read(String key) async {
    const delaysMs = [150, 300, 450, 600, 800];
    for (var i = 0; i <= delaysMs.length; i++) {
      try {
        return await _storage.read(key: key);
      } catch (_) {
        if (i == delaysMs.length) return null; // son deneme de fırlattı → pes
        await Future.delayed(Duration(milliseconds: delaysMs[i]));
      }
    }
    return null;
  }

  Future<String?> get accessToken => _read(_kAccess);
  Future<String?> get refreshToken => _read(_kRefresh);

  Future<bool> get hasSession async => (await accessToken) != null;

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
    } catch (_) {}
  }
}
