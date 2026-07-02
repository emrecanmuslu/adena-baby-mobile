import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification_service.dart';
import '../../core/providers.dart';
import '../../core/push_service.dart';
import '../../core/revenuecat_service.dart';
import '../../data/auth_repository.dart';
import '../../data/initial_import.dart';
import '../../data/local_session.dart';
import '../../data/slot_registry.dart';
import '../../data/social_auth_service.dart';
import '../../data/subscription_cache.dart';
import '../../models/user.dart';

/// Oturum durumu. State == null → çıkış yapılmış, User → oturum açık.
/// build() açılışta token varsa /auth/me ile kullanıcıyı doğrular.
class AuthController extends AsyncNotifier<User?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<User?> build() async {
    final storage = ref.read(tokenStorageProvider);
    if (!await storage.hasSession) return null;
    // Gerçek oturum var → misafir ("kayıt olmadan devam et") bayrağını kapat.
    unawaited(LocalSession.exitGuest());
    try {
      final user = await _repo.me();
      await LocalSession.cacheAuthUser(user.toJson()); // offline açılış yedeği
      _syncRevenueCat(user);
      // Yerel veri izolasyonu: aktif hesabı set et (repo'lar buna göre kapsamlar).
      LocalSession.setActiveAccount(user.id);
      // Bu hesabın sunucu verisini bir kez yerele indir (local-first geçişi /
      // farklı cihaz). Hesap-bazlı bayrakla bir kez koşar.
      await ref.read(initialImportProvider).runIfNeeded();
      return user;
    } catch (_) {
      // /auth/me başarısız. Token silme kararı TEK yerde: api_client._refresh
      // refresh token'ı yalnız sunucu AÇIKÇA reddederse siler. Buraya gelince:
      //  • token'lar HÂLÂ duruyorsa → yalnız GEÇİCİ ağ/sunucu hatası → oturumu
      //    KORU (offline-first): önbellekteki kullanıcıyla devam et.
      //  • token'lar GİTMİŞSE → refresh gerçek reddi gördü → gerçek çıkış.
      if (await storage.hasSession) {
        final cached = await LocalSession.cachedAuthUser();
        if (cached != null) {
          final user = User.fromJson(cached);
          _syncRevenueCat(user);
          LocalSession.setActiveAccount(user.id);
          return user; // çevrimdışı/geçici hata — kullanıcı login'e düşmez
        }
        // Önbellek yok ama token duruyor → login göster ama token'ı SİLME;
        // bir sonraki açılış internet/sunucu gelince normal akışla düzelir.
        return null;
      }
      await LocalSession.clearCachedAuthUser();
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
      // Misafir modundan çık (varsa) — yerel veri kapsamı gerçek hesaba geçer.
      // Misafir verisi varsa "aktaralım mı?" sorusu AdenaApp dinleyicisinde sorulur.
      await ref.read(guestModeProvider.notifier).exit();
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
    await SlotRegistry.instance.clear(); // slot haritası sıfırlansın (yeni hesap 0'dan)
    await _repo.deleteAccount();
    // logout ile AYNI temizlik: sonraki kullanıcıya premium/RC kimliği/yerel kapsam
    // sızmasın (deleteAccount eksikti → aynı cihazda yeni free kullanıcıya premium flaşı).
    await RevenueCatService.instance.logoutUser();
    await SubscriptionCache().clear();
    await LocalSession.clearCachedAuthUser();
    LocalSession.setActiveAccount(null);
    state = const AsyncData(null);
  }

  Future<void> logout() async {
    // Token HÂLÂ geçerliyken bu cihazın FCM kaydını sil (çıkıştan önce).
    await PushService.instance.unregister(ref.read(apiClientProvider));
    // Önceki hesabın zamanlanmış yerel bildirimlerini iptal et → yeni hesaba
    // "sonraki beslenme"/hatırlatıcı bildirimi sızmasın.
    await NotificationService.instance.cancelAll();
    await SlotRegistry.instance.clear(); // slot haritası sıfırlansın (yeni hesap 0'dan)
    await _repo.logout();
    await RevenueCatService.instance.logoutUser();
    await SubscriptionCache().clear(); // sonraki kullanıcıya premium sızmasın
    await LocalSession.clearCachedAuthUser(); // önbellekli kullanıcı sızmasın
    LocalSession.setActiveAccount(null); // yerel veri kapsamı kapanır (silinmez)
    state = const AsyncData(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);

/// O an oturum açık hesabın id'si — repo'lar/controller'lar yerel veriyi buna
/// göre kapsamlar (hesap değişince ilgili akışlar yeniden kurulur).
final activeAccountIdProvider = Provider<String?>((ref) {
  final uid = ref.watch(authControllerProvider).asData?.value?.id;
  if (uid != null) return uid;
  // Misafir ("kayıt olmadan devam et"): yerel veri kapsamı device-UUID'ye bağlanır
  // (LocalSession.activeAccountId ile aynı). Böylece misafir bebek/kayıt/adet
  // yerelde görünür ve misafir moduna geçince ilgili controller'lar yeniden kurulur.
  // localUserIdProvider (plain Provider) enterGuest ÜRETMEDEN önce okunmuşsa '' cache'ler
  // → kapsamı bozar; statik userId'yi DOĞRUDAN oku (enterGuest üretmiş olur, guestMode
  // flip'i bu provider'ı yeniden hesaplar).
  if (ref.watch(guestModeProvider)) {
    final gid = LocalSession.userId;
    return gid.isEmpty ? null : gid;
  }
  return null;
});
