import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/auth_repository.dart';
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
      return await _repo.me();
    } catch (_) {
      // Token geçersiz/temizlenmiş — çıkış durumuna düş.
      await ref.read(tokenStorageProvider).clear();
      return null;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repo.login(email: email, password: password),
    );
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
  }

  Future<void> updateName(String name) async {
    final user = await _repo.updateName(name);
    state = AsyncData(user);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    state = const AsyncData(null);
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);
