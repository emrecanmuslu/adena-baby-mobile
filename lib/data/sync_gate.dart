import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/babies/baby_controller.dart';
import 'subscription_repository.dart';

/// Oturum açık mı? Bulut işlemlerinin tabanı (bebek listesi pull, paylaşılan bebek
/// sync). Premium gerektirmez — paylaşılan bebek erişimi/sync'i sahibin premium'una
/// bağlıdır, üyenin kendi premium'una değil (bkz. [babyCloudSyncedProvider]).
final loggedInProvider = Provider<bool>((ref) =>
    ref.watch(authControllerProvider).asData?.value != null);

/// Kişisel bulut yedeği açık mı: **oturum açık VE KENDİ premium'um**. Bu BEBEK-BAĞIMSIZ
/// global bayrak yalnız kişisel/sahip verileri kapsar (cycle = annenin adet takibi,
/// ve sahip olduğum bebeklerin kişisel yedeği). Free kullanıcı yerel-önce çalışır.
///
/// Paylaşılan bebek için BUNU KULLANMA → [babyCloudSyncedProvider] (per-baby).
/// İstisnalar (her zaman cloud, bu bayrağa tabi DEĞİL): topluluk, içerik/çeviri/medya.
final cloudSyncEnabledProvider = Provider<bool>((ref) {
  return ref.watch(loggedInProvider) && ref.watch(isPremiumProvider);
});

/// Belirli bir bebek bulut senkronuna tabi mi? **Seçenek 2 — sahip-finanse, per-baby
/// efektif premium.**
/// - Paylaşılan bebek (myRole = parent/caregiver): veri SAHİBİN bulutunda yaşar; sahip
///   premium olduğu için zaten paylaşıldı → üyenin KENDİ premium'undan BAĞIMSIZ
///   senkronlanır (oturum yeterli). Davetli üye free olsa da kayıt/anı/anne takibini
///   okur ve katkı yapar — sahibin satın aldığı aile paylaşımı üyeyi de kapsar.
/// - Kendi bebeğim (owner / myRole null): kişisel bulut yedeği → KENDİ premium'um.
/// Bu OTURUMDA bulut yazımı reddedilen (403) paylaşılan bebekler. Sahibin premium'u
/// bitince (grace) üyenin /sync'i 403 döner → bebek bu sete eklenir → o bebek için
/// push/sync denemesi durur (403 spam'i önlenir); veri yerel salt-okunur mirror olarak
/// kalır. Restart'ta temizlenir → sahip yeniden abone olursa senkron kendiliğinden döner.
class _CloudReadonlyBabies extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};
  void add(String babyId) {
    if (state.contains(babyId)) return;
    state = {...state, babyId};
  }

  /// Geçici 403'ten kurtulma: bebek sync'i sonradan BAŞARIRSA bu işaret kaldırılır
  /// (eskiden yalnız uygulama restart'ında temizlenirdi → katılıştaki anlık 403,
  /// bebeği oturum boyu "salt-okunur" yapıp senkronu durduruyor + sahte banner
  /// gösteriyordu). Artık her başarılı sync'te kendi kendine iyileşir.
  void remove(String babyId) {
    if (!state.contains(babyId)) return;
    state = {...state}..remove(babyId);
  }
}

final cloudReadonlyBabiesProvider =
    NotifierProvider<_CloudReadonlyBabies, Set<String>>(_CloudReadonlyBabies.new);

/// Bebek bulut-UYGUN mu (rol/premium) — oturum-içi readonly (403) işaretini YOK
/// SAYAR. `SyncService.syncAll` bunu kapı olarak kullanır: readonly bebeği de bir
/// kez DAHA dener; başarırsa readonly'den çıkarıp iyileştirir (geçici 403'ten
/// kurtulma). Görüntü/push gating için [babyCloudSyncedProvider] (readonly'yi sayar).
final babyCloudEligibleProvider = Provider.family<bool, String>((ref, babyId) {
  if (!ref.watch(loggedInProvider)) return false;
  final babies = ref.watch(babyControllerProvider).asData?.value ?? const [];
  String? role;
  for (final b in babies) {
    if (b.id == babyId) {
      role = b.myRole;
      break;
    }
  }
  final shared = role == 'parent' || role == 'caregiver';
  if (shared) return true;
  return ref.watch(isPremiumProvider);
});

final babyCloudSyncedProvider = Provider.family<bool, String>((ref, babyId) {
  // Bu oturumda 403 alındıysa (sahip premium bitti / grace) → salt-okunur say.
  if (ref.watch(cloudReadonlyBabiesProvider).contains(babyId)) return false;
  return ref.watch(babyCloudEligibleProvider(babyId));
});
