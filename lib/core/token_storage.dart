import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT token'larını güvenli (şifreli) depolar.
class TokenStorage {
  // iOS: afterFirstUnlock → token cihaz KİLİTLİYKEN de (ilk açılıştan sonra) okunur.
  // Varsayılan whenUnlocked, uygulama push/arka plan sync ile kilitliyken token'a
  // erişince errSecInteractionNotAllowed FIRLATIYORDU; push sonrası simgeden soğuk
  // açılışta da bu hata interceptor'da yakalanmadan fatal olup açılışı splash'te
  // donduruyordu. Eski (whenUnlocked) kayıtlar sonraki login/refresh'te yeniden
  // yazılınca bu erişime geçer. Bkz [[acilis-donmasi-keychain-fix]].
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  Future<void> saveTokens({required String access, String? refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    if (refresh != null) {
      await _storage.write(key: _kRefresh, value: refresh);
    }
  }

  // Keychain okuması iOS'ta HATA FIRLATABİLİR (kilit/erişim/transient platform
  // channel). Fırlatırsa null dön → açılış auth akışı çökmesin/donmasın (splash
  // donmasının kök nedeni: okuma fırlatıp Dio interceptor'ında yakalanmadan fatal
  // oluyordu, /auth/me Future'ı çözülmüyordu → router splash'te asılı kalıyordu).
  Future<String?> get accessToken async {
    try {
      return await _storage.read(key: _kAccess);
    } catch (_) {
      return null;
    }
  }

  Future<String?> get refreshToken async {
    try {
      return await _storage.read(key: _kRefresh);
    } catch (_) {
      return null;
    }
  }

  Future<bool> get hasSession async => (await accessToken) != null;

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
    } catch (_) {}
  }
}
