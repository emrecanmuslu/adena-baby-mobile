import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification_service.dart';
import '../../core/providers.dart';
import '../../core/push_service.dart';
import '../../core/revenuecat_service.dart';
import '../../data/auth_repository.dart';
import '../../data/initial_import.dart';
import '../../data/local_session.dart';
import '../../data/social_auth_service.dart';
import '../../data/subscription_cache.dart';
import '../../models/user.dart';

/// Oturum durumu. State == null → çıkış yapılmış, User → oturum açık.
/// build() açılışta token varsa /auth/me ile kullanıcıyı doğrular.
class AuthController extends AsyncNotifier<User?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<User?> build() async {
    final hasSession = await ref.read(tokenStorageProvider).hasSession;
    if (!hasSession) return null;
    try {
      final user = await _repo.me();
      _syncRevenueCat(user);
      // Yerel veri izolasyonu: aktif hesabı set et (repo'lar buna göre kapsamlar).
      LocalSession.setActiveAccount(user.id);
      // Bu hesabın sunucu verisini bir kez yerele indir (local-first geçişi /
      // farklı cihaz). Hesap-bazlı bayrakla bir kez koşar.
      await ref.read(initialImportProvider).runIfNeeded();
      return user;
    } catch (_) {
      // Token geçersiz/temizlenmiş — çıkış durumuna düş.
      await ref.read(tokenStorageProvider).clear();
      return null;
    }
  }

  /// RevenueCat kullanıcı kimliğini bizim user.id'ye sabitler (webhook eşleşmesi).
  void _syncRevenueCat(User? user) {
    if (user != null) RevenueCatService.instance.identify(user.id);
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.login(email: email, password: password),
    );
    _syncRevenueCat(state.value);
    await _postLogin();
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.register(email: email, password: password, name: name),
    );
    _syncRevenueCat(state.value);
    await _postLogin();
  }

  /// Giriş/kayıt sonrası: oturum açıldıysa mevcut hesabın sunucu verisini bir
  /// kez yerele indir (taze login'de build() yeniden koşmaz; bu yolu da kapsar).
  Future<void> _postLogin() async {
    final u = state.value;
    if (u != null) {
      LocalSession.setActiveAccount(u.id);
      await ref.read(initialImportProvider).runIfNeeded();
    }
  }

  /// Parola sıfırlama kodu ister (e-postaya gönderilir). Oturum durumunu
  /// değiştirmez; hata UI'da yakalanır.
  Future<void> requestPasswordReset(String email) =>
      _repo.forgotPassword(email);

  /// Kod + yeni şifreyle sıfırlar ve başarılıysa otomatik giriş yapar.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.resetPassword(
          email: email, code: code, newPassword: newPassword),
    );
    _syncRevenueCat(state.value);
    await _postLogin();
  }

  /// Sosyal giriş (provider: 'google' | 'apple'). Kullanıcı sağlayıcı
  /// ekranını iptal ederse hata göstermeden çıkış durumunda kalır.
  Future<void> socialLogin(String provider) async {
    final social = ref.read(socialAuthServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final idToken =
          provider == 'google' ? await social.google() : await social.apple();
      if (idToken == null) return null; // iptal → çıkış durumunda kal
      return _repo.social(provider: provider, idToken: idToken);
    });
    _syncRevenueCat(state.value);
    await _postLogin();
  }

  /// Yasal rıza kapısından onay kaydı: backend'e yazar, oturum kullanıcısının
  /// consentRequired'ını düşürür → router rıza kapısından çıkarır.
  Future<void> recordConsent() async {
    await _repo.recordConsent();
    final u = state.value;
    if (u != null) state = AsyncData(u.copyWith(consentRequired: false));
  }

  Future<void> updateName(String name) async {
    final user = await _repo.updateName(name);
    state = AsyncData(user);
  }

  Future<void> deleteAccount() async {
    await PushService.instance.unregister(ref.read(apiClientProvider));
    await NotificationService.instance.cancelAll(); // eski hesabın bildirimleri kalmasın
    await _repo.deleteAccount();
    state = const AsyncData(null);
  }

  Future<void> logout() async {
    // Token HÂLÂ geçerliyken bu cihazın FCM kaydını sil (çıkıştan önce).
    await PushService.instance.unregister(ref.read(apiClientProvider));
    // Önceki hesabın zamanlanmış yerel bildirimlerini iptal et → yeni hesaba
    // "sonraki beslenme"/hatırlatıcı bildirimi sızmasın.
    await NotificationService.instance.cancelAll();
    await _repo.logout();
    await RevenueCatService.instance.logoutUser();
    await SubscriptionCache().clear(); // sonraki kullanıcıya premium sızmasın
    LocalSession.setActiveAccount(null); // yerel veri kapsamı kapanır (silinmez)
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);

/// O an oturum açık hesabın id'si — repo'lar/controller'lar yerel veriyi buna
/// göre kapsamlar (hesap değişince ilgili akışlar yeniden kurulur).
final activeAccountIdProvider = Provider<String?>(
    (ref) => ref.watch(authControllerProvider).asData?.value?.id);
