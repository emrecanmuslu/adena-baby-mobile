import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/medication/med_scheduler.dart';
import '../../core/notification_service.dart';
import '../../core/providers.dart';
import '../../core/push_service.dart';
import '../../core/revenuecat_service.dart';
import '../../core/session_end.dart';
import '../../data/auth_repository.dart';
import '../../data/cycle_repository.dart';
import '../../data/initial_import.dart';
import '../../data/local_session.dart';
import '../../data/slot_registry.dart';
import '../../data/social_auth_service.dart';
import '../../data/subscription_cache.dart';
import '../../models/user.dart';
import '../records/record_controller.dart' show SyncService;

/// Oturum durumu. State == null → çıkış yapılmış, User → oturum açık.
/// build() açılışta token varsa /auth/me ile kullanıcıyı doğrular.
class AuthController extends AsyncNotifier<User?> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Oturum kuşağı (O34). Çıkış / hesap silme / zorunlu çıkış artırır. Ağ
  /// beklemiş her auth yolu başta değeri yakalar; yanıt dönünce değer değişmişse
  /// (ya da token gitmişse) state/önbellek/kapsam/import'a DOKUNMAZ — aksi hâlde
  /// geç gelen `/auth/me` çıkış yapılmış kullanıcıyı geri getiriyordu.
  int _epoch = 0;

  /// Yakalanan kuşak hâlâ geçerli mi (çıkış olmadı + token duruyor)?
  Future<bool> _stillCurrent(int epoch) async {
    if (epoch != _epoch || !ref.mounted) return false;
    return ref.read(tokenStorageProvider).hasSession;
  }

  @override
  Future<User?> build() async {
    final storage = ref.read(tokenStorageProvider);
    // K9: arka plan isolate'inde (workmanager/BGTask/FCM) yalnız kimlik gerekir;
    // /auth/me tazeleme + ilk import, RevenueCat identify ve exitGuest ön plana
    // ait işlerdir — bg'de HİÇ başlatılmaz (container dispose'dan önce bitmez,
    // her turda tam import tetikler, prefs bayraklarını ezerdi).
    final bg = ref.read(runningInBackgroundProvider);
    // O1: sunucu oturumu reddedince (refresh 401/400) zorunlu çıkış. Kanca
    // yalnız ön planda ve bu notifier yaşadığı sürece; dispose'da (hâlâ bizimse)
    // sıfırlanır → RestartWidget sonrası eski notifier çağrılmaz. Oturum yokken
    // de atanır: login() state'i rebuild olmadan değiştirir, kanca hazır olmalı.
    if (!bg) {
      final api = ref.read(apiClientProvider);
      void hook(SessionEndReason r) => _onSessionRejected(r);
      api.onSessionRejected = hook;
      ref.onDispose(() {
        if (identical(api.onSessionRejected, hook)) api.onSessionRejected = null;
      });
    }
    if (!await storage.hasSession) return null;
    // Gerçek oturum var → misafir ("kayıt olmadan devam et") bayrağını kapat.
    if (!bg) unawaited(LocalSession.exitGuest());
    // Local-first: önbellekte kullanıcı varsa AĞI BEKLEMEDEN hemen onunla dön —
    // splash/router bu future'ı bekliyor (bkz router.dart auth.isLoading), yavaş
    // ağda /auth/me'nin (15-20s timeout) bitmesini beklemek kullanıcıyı splash'te
    // gereksiz yere kilitliyordu. Doğrulama/güncelleme arkaplanda devam eder.
    final cached = await LocalSession.cachedAuthUser();
    if (cached != null) {
      final user = User.fromJson(cached);
      LocalSession.setActiveAccount(user.id);
      if (!bg) {
        _syncRevenueCat(user);
        unawaited(_refreshInBackground());
      }
      return user;
    }
    // Önbellek yok (ilk açılış / farklı cihaz) → gösterecek yerel veri
    // olmadığından burada ağı beklemek zorundayız (bg'de de: kimlik şart).
    try {
      final user = await _repo.me();
      await LocalSession.cacheAuthUser(user.toJson()); // offline açılış yedeği
      LocalSession.setActiveAccount(user.id);
      if (!bg) {
        _syncRevenueCat(user);
        await ref.read(initialImportProvider).runIfNeeded();
      }
      return user;
    } catch (_) {
      // /auth/me başarısız, önbellek de yok. Token silme kararı TEK yerde:
      // api_client._refresh refresh token'ı yalnız sunucu AÇIKÇA reddederse
      // siler — token duruyorsa yalnız geçici hata demektir, SİLME; login
      // göster, bir sonraki açılışta internet/sunucu gelince düzelir.
      if (await storage.hasSession) return null;
      await LocalSession.clearCachedAuthUser();
      return null;
    }
  }

  /// build() önbellekli kullanıcıyla anında dönünce, gerçek doğrulama/güncellemeyi
  /// arkaplanda tamamlar: /auth/me başarırsa taze veriyle state'i günceller +
  /// bir-kez cloud import'u tetikler; geçici ağ/sunucu hatasında SESSİZCE yutar
  /// (kullanıcı önbellekli veriyle kalmaya devam eder — gerçek red zaten
  /// api_client._refresh tarafından ele alınır).
  Future<void> _refreshInBackground() async {
    final epoch = _epoch;
    try {
      final user = await _repo.me();
      if (!await _stillCurrent(epoch)) return; // O34: bu arada çıkış yapıldı
      await LocalSession.cacheAuthUser(user.toJson());
      _syncRevenueCat(user);
      LocalSession.setActiveAccount(user.id);
      await ref.read(initialImportProvider).runIfNeeded();
      if (ref.mounted && epoch == _epoch) state = AsyncData(user);
    } catch (_) {
      // Geçici hata — önbellekli kullanıcıyla devam edilir, sessizce geç.
    }
  }

  void _onSessionRejected(SessionEndReason reason) {
    if (!ref.mounted || state.value == null) return; // çıkışta/misafirde no-op
    unawaited(sessionExpired(reason));
  }

  /// Zorunlu çıkış (O1): sunucu oturumu reddetti (başka cihazdan giriş / refresh
  /// süresi doldu) ya da token başka isolate'te silindi. Kullanıcı çıkışından
  /// FARKLI: yerel veri SİLİNMEZ (dirty kayıtlar aynı hesapla yeniden girişte
  /// gönderilir), yerel hatırlatıcılar iptal EDİLMEZ, slot haritası ve cihaz
  /// kaydı (yetki yok) dokunulmaz. Yalnız kimlik/yetki durumu temizlenir ve
  /// aile push'u bu cihaza gelmesin diye FCM token'ı silinir.
  Future<void> sessionExpired(SessionEndReason reason) async {
    _epoch++; // uçuştaki auth yanıtları artık geçersiz (O34)
    await ref.read(tokenStorageProvider).clear();
    await SessionEndCache.write(reason);
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Firebase hazır değil / platform hatası → sessiz.
    }
    await RevenueCatService.instance.logoutUser();
    await SubscriptionCache().clear();
    await LocalSession.clearCachedAuthUser();
    LocalSession.setActiveAccount(null);
    if (!ref.mounted) return;
    ref.read(sessionEndReasonProvider.notifier).set(reason);
    state = const AsyncData(null);
  }

  /// Öne gelişte/açılışta: state User ama token yok (başka isolate'teki bg
  /// turu refresh reddi aldı ve token'ı sildi) → zorunlu çıkışı uygula.
  Future<void> verifySession() async {
    if (!ref.mounted || state.value == null) return;
    if (await ref.read(tokenStorageProvider).hasSession) return;
    final reason = await SessionEndCache.read() ?? SessionEndReason.unknown;
    await sessionExpired(reason);
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
    final epoch = _epoch;
    final u = state.value;
    if (u != null) {
      // Misafir modundan çık (varsa) — yerel veri kapsamı gerçek hesaba geçer.
      // Misafir verisi varsa "aktaralım mı?" sorusu AdenaApp dinleyicisinde sorulur.
      await ref.read(guestModeProvider.notifier).exit();
      LocalSession.setActiveAccount(u.id);
      // J3: adet provider'ları state değişiminde (statik kapsam set edilmeden)
      // kurulmuş olabilir → statik güncellenince yeniden kur (syncIfCloud dahil).
      if (ref.mounted) {
        ref.invalidate(cycleSettingsProvider);
        ref.invalidate(cycleEntriesProvider);
      }
      // Offline açılış yedeği: taze login/kayıtta build() yeniden koşmadığı
      // için /auth/me önbelleği burada da yazılır — yoksa ilk soğuk açılış
      // çevrimdışıyken oturum çözülemez (repo'lar hesapsız kalır).
      await LocalSession.cacheAuthUser(u.toJson());
      // O1: eski "oturum sona erdi" nedeni bir sonraki çıkışta yanlış banner
      // göstermesin.
      await SessionEndCache.clear();
      if (ref.mounted) ref.read(sessionEndReasonProvider.notifier).set(null);
      if (epoch != _epoch) return; // O34: await'ler sırasında çıkış yapıldı
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
    final epoch = _epoch;
    await _repo.recordConsent();
    if (epoch != _epoch) return; // O34
    final u = state.value;
    if (u != null) state = AsyncData(u.copyWith(consentRequired: false));
  }

  Future<void> updateName(String name) async {
    final epoch = _epoch;
    final user = await _repo.updateName(name);
    if (epoch != _epoch) return; // O34: çıkış sonrası geç yanıt state'i geri getirmesin
    state = AsyncData(user);
  }

  Future<void> deleteAccount() async {
    // O10: geri alınamayan YEREL yan etkiler (bildirim iptali, slot haritası)
    // ağ isteği BAŞARDIKTAN sonra — istek düşerse hesap da oturum da yerel
    // hatırlatıcılar da olduğu gibi kalır. Cihaz kaydı silme sunucu işi, yerel
    // etkisi yok → auth hâlâ geçerliyken önce.
    await PushService.instance.unregister(ref.read(apiClientProvider));
    await _repo.deleteAccount();
    _epoch++; // O34
    // KB-9 (a): sunucu silmeyi onayladı → bu hesabın YEREL kapsamı da silinir
    // (drift satırları + foto dosyaları); başka hesap/misafir verisi kalır.
    // Başarısız olsaydı buraya gelinmez, yerelde hiçbir şey silinmezdi.
    final acct = LocalSession.activeAccountId;
    // I8/I16: ÖNCE kapsam + state kapanır (router doğrudan login'e; bebek akışı
    // boşalınca onboarding'e uğramaz, bulut işlemleri loggedIn=false ile durur),
    // SONRA yerel silme `whileWiping` içinde (süren tur satır geri eklemesin).
    LocalSession.setActiveAccount(null);
    if (ref.mounted) state = const AsyncData(null);
    if (acct != null) {
      try {
        final wiped = await SyncService.whileWiping(
            () => ref.read(databaseProvider).wipeAccountData(acct));
        for (final path in wiped.photoPaths) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      } catch (_) {
        // Yerel temizlik hatası oturum kapanışını engellemesin.
      }
    }
    await NotificationService.instance.cancelAll(); // eski hesabın bildirimleri kalmasın
    await MedicationScheduler.instance.clearRegistry();
    await SlotRegistry.instance.clear(); // slot haritası sıfırlansın (yeni hesap 0'dan)
    // logout ile AYNI temizlik: sonraki kullanıcıya premium/RC kimliği/yerel kapsam
    // sızmasın (deleteAccount eksikti → aynı cihazda yeni free kullanıcıya premium flaşı).
    await RevenueCatService.instance.logoutUser();
    await SubscriptionCache().clear();
    await LocalSession.clearCachedAuthUser();
    if (ref.mounted) state = const AsyncData(null);
  }

  Future<void> logout() async {
    _epoch++; // O34: uçuştaki /auth/me, updateName vb. yanıtları artık geçersiz
    // Token HÂLÂ geçerliyken bu cihazın FCM kaydını sil (çıkıştan önce).
    await PushService.instance.unregister(ref.read(apiClientProvider));
    // Önceki hesabın zamanlanmış yerel bildirimlerini iptal et → yeni hesaba
    // "sonraki beslenme"/hatırlatıcı bildirimi sızmasın.
    await NotificationService.instance.cancelAll();
    await MedicationScheduler.instance.clearRegistry();
    await SlotRegistry.instance.clear(); // slot haritası sıfırlansın (yeni hesap 0'dan)
    await _repo.logout();
    await RevenueCatService.instance.logoutUser();
    await SubscriptionCache().clear(); // sonraki kullanıcıya premium sızmasın
    await LocalSession.clearCachedAuthUser(); // önbellekli kullanıcı sızmasın
    LocalSession.setActiveAccount(null); // yerel veri kapsamı kapanır (silinmez)
    await SessionEndCache.clear(); // kullanıcı çıkışı neden yazmaz/temizler (O1)
    if (ref.mounted) ref.read(sessionEndReasonProvider.notifier).set(null);
    state = const AsyncData(null);
  }
}

/// Giriş ekranında bir kez gösterilecek "oturum sona erdi" nedeni (O1).
/// `sessionExpired` set eder; giriş ekranı gösterince, başarılı giriş ve
/// kullanıcı çıkışı temizler.
class SessionEndReasonNotifier extends Notifier<SessionEndReason?> {
  @override
  SessionEndReason? build() => null;
  void set(SessionEndReason? r) => state = r;
}

final sessionEndReasonProvider =
    NotifierProvider<SessionEndReasonNotifier, SessionEndReason?>(
        SessionEndReasonNotifier.new);

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
