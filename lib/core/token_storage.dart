import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT token'larını güvenli (şifreli) depolar.
class TokenStorage {
  // NOT: iOS accessibility VARSAYILAN (whenUnlocked) bırakıldı. `first_unlock`'a
  // geçmek mevcut (whenUnlocked) kayıtla migration çakışması yaratıp saveTokens'i
  // (write) iOS'ta patlatıyordu → güncelleme sonrası "giriş yapılamıyor". Açılış
  // donmasının asıl çözümü, OKUMALARI try/catch'e almaktır (aşağıda): Keychain
  // okuması fırlarsa (kilit/transient) null döner → Dio interceptor'ında
  // yakalanmamış fatal/donma olmaz. Bkz [[acilis-donmasi-keychain-fix]].
  static const _storage = FlutterSecureStorage();
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  Future<void> saveTokens({required String access, String? refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    if (refresh != null) {
      await _storage.write(key: _kRefresh, value: refresh);
    }
  }

  // Keychain okuması iOS'ta HATA FIRLATABİLİR (kilit/erişim/transient). Fırlatırsa
  // null dön → açılış auth akışı çökmesin/donmasın (splash donmasının kök nedeni:
  // okuma fırlatıp Dio interceptor'ında yakalanmadan fatal oluyordu, /auth/me
  // Future'ı çözülmüyordu → router splash'te asılı kalıyordu).
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
