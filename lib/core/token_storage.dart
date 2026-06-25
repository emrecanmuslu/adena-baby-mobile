import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT token'larını güvenli (şifreli) depolar.
class TokenStorage {
  // iOS: AfterFirstUnlock**ThisDeviceOnly** → token cihaz KİLİTLİYKEN de (reboot
  // sonrası ilk açılıştan SONRA) okunur. Bu, push/arka plan ile açılışta veya soğuk
  // başlatmada Keychain hatasını (errSecInteractionNotAllowed -25308) çözer — splash
  // donmasının + auth sorununun ASIL kök çözümü. ThisDeviceOnly = yedeğe/başka cihaza
  // sızmaz (auth token için güvenli, Apple'ın arka-plan-token önerisi).
  // Tek kaçınılmaz istisna: cihaz reboot olup HİÇ açılmadıysa hiçbir sınıf okuyamaz
  // → aşağıdaki retry + try/catch graceful ele alır (null → login, açılışta düzelir).
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  Future<void> saveTokens({required String access, String? refresh}) async {
    // Yazmadan ÖNCE eski kaydı sil: farklı accessibility'li (ör. eski whenUnlocked)
    // bir kayıt varsa çakışıp "item already exists" ile patlamasın (delete,
    // accessibility'den BAĞIMSIZ siler). Migration'ı garanti eder.
    try {
      await _storage.delete(key: _kAccess);
    } catch (_) {}
    await _storage.write(key: _kAccess, value: access);
    if (refresh != null) {
      try {
        await _storage.delete(key: _kRefresh);
      } catch (_) {}
      await _storage.write(key: _kRefresh, value: refresh);
    }
  }

  /// Keychain okuması iOS'ta GEÇİCİ olarak FIRLATABİLİR (reboot-öncesi ilk açılış
  /// vb.). Fırlarsa kısa backoff'la YENİDEN DENE → geçici hata geçince token okunur
  /// (mevcut oturumlu kullanıcı giriş ekranı görmesin). Genuine "anahtar yok"
  /// (null döner, fırlatmaz) → retry yok. Tüm denemeler fırlarsa null (donma yok).
  Future<String?> _read(String key) async {
    const delaysMs = [150, 300, 450, 600, 800];
    for (var i = 0; i <= delaysMs.length; i++) {
      try {
        return await _storage.read(key: key);
      } catch (_) {
        if (i == delaysMs.length) return null;
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
