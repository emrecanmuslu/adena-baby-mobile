import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/push_service.dart';
import '../../core/revenuecat_service.dart';
import '../../data/auth_repository.dart';
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
  }

  Future<void> updateName(String name) async {
    final user = await _repo.updateName(name);
    state = AsyncData(user);
  }

  Future<void> deleteAccount() async {
    await PushService.instance.unregister(ref.read(apiClientProvider));
    await _repo.deleteAccount();
    state = const AsyncData(null);
  }

  Future<void> logout() async {
    // Token HÂLÂ geçerliyken bu cihazın FCM kaydını sil (çıkıştan önce).
    await PushService.instance.unregister(ref.read(apiClientProvider));
    await _repo.logout();
    await RevenueCatService.instance.logoutUser();
    await SubscriptionCache().clear(); // sonraki kullanıcıya premium sızmasın
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);
