import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/analytics_service.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../data/activity_notif_cache.dart';
import '../../data/baby_repository.dart';
import '../../data/health_repository.dart';
import '../../data/memory_repository.dart';
import '../../data/mom_repository.dart';
import '../../data/record_repository.dart';
import '../../data/sync_gate.dart';
import '../../models/baby.dart';
import '../auth/auth_controller.dart';

const _uuid = Uuid();

/// Kullanıcının bebekleri — **local-first**. Yerel drift akışını dinler; premium
/// + oturum açıkken sunucudan da çeker (reconcile). Free'de yalnız yerel.
class BabyController extends AsyncNotifier<List<Baby>> {
  BabyRepository get _repo => ref.read(babyRepositoryProvider);

  @override
  Future<List<Baby>> build() async {
    // Hesap değişince controller yeniden kurulsun (yerel veri aktif hesaba göre
    // kapsamlanır → farklı hesaba girişte doğru bebek listesi gelir). KRİTİK:
    // watchAll/getAll'ı statik LocalSession.activeAccountId yerine BU provider
    // değeriyle çağır — login/logout geçişinde statik henüz güncellenmemişken
    // (setActiveAccount _postLogin'de) rebuild olursa stream YANLIŞ hesabı sorgulayıp
    // bebeği kaybediyordu (onboarding'e atıyordu, intermittent). Provider = rebuild
    // tetikçisi → aynı değerle sorgu daima tutarlı.
    final acct = ref.watch(activeAccountIdProvider);
    // Yerel akışı dinle: yerel yazımlar (create/update/delete) state'i otomatik
    // günceller — çıkışta bile veri kalır (local her zaman birincil).
    final sub = _repo.watchAll(accountId: acct).listen((list) {
      state = AsyncData(list);
    });
    ref.onDispose(sub.cancel);
    // Oturum açıksa sunucuyla reconcile et. Premium ŞART DEĞİL: paylaşılan bebeğin
    // profili (ör. gebelik→doğdu) + üyelik değişiklikleri sahibin bulutundan gelir →
    // free üye de bunu çekmeli (Seçenek 2). Kendi bebeklerimi YÜKLEMEK ise _pull
    // içinde kendi premium'uma bağlı kalır.
    if (ref.watch(loggedInProvider)) {
      unawaited(_pull(acct));
    }
    return _repo.getAll(accountId: acct);
  }

  /// Onboarding'den yeni bebek oluşturur (istemci-üretimli UUID, yerele yazılır).
  Future<Baby> create({
    required String name,
    required BabyStatus status,
    BabyGender gender = BabyGender.unknown,
    DateTime? birthDate,
    DateTime? dueDate,
    DateTime? lastMenstrualDate,
    int? gestationalWeeks,
    int gestationalDays = 0,
  }) async {
    final baby = Baby(
      id: _uuid.v4(),
      name: name,
      gender: gender,
      status: status,
      birthDate: birthDate,
      dueDate: dueDate,
      lastMenstrualDate: lastMenstrualDate,
      gestationalWeeks: gestationalWeeks,
      gestationalDays: gestationalDays,
      myRole: 'owner',
    );
    final created = await _repo.create(baby);
    unawaited(AnalyticsService.instance.log('baby_created', {
      'baby_status': status.name,
    }));
    _pushSoon();
    return created;
  }

  /// Bebek alanlarını günceller (ad/cinsiyet/tarih, "doğdu" geçişi).
  Future<Baby> updateBaby(String id, Map<String, dynamic> fields) async {
    final updated = await _repo.update(id, fields);
    _pushSoon();
    return updated;
  }

  Future<void> deleteBaby(String id) async {
    await _repo.delete(id);
    _pushSoon();
  }

  /// Yerel dirty bebekleri arka planda sunucuya gönderir. Kendi (sahip) bebeklerimin
  /// yüklenmesi KENDİ premium'uma bağlı (free = yerel-önce); paylaşımlı (myRole=
  /// 'parent') bebeklerin profil/foto değişikliği ise sahibin bulutuna bağlı olduğundan
  /// kendi premium'umdan BAĞIMSIZ her zaman gönderilir — aksi halde üye taraflı foto/ad
  /// değişikliği hiç buluta çıkmaz, bir sonraki pull'da sessizce yerelden silinir.
  void _pushSoon() {
    if (!ref.read(loggedInProvider)) return;
    unawaited(
        _repo.pushDirty(includeOwned: ref.read(cloudSyncEnabledProvider)));
  }

  /// Sunucudan çekip yereli reconcile eder; erişimi kaldırılan (paylaşımdan düşen)
  /// bebeklerin yerel verisini temizler + bildirim. Oturum açıkken anlamlı.
  ///
  /// [acct] build()'ın reaktif `activeAccountIdProvider` değeri — repo'ya AÇIKÇA
  /// geçirilir çünkü statik `LocalSession.activeAccountId` login geçişinde bu
  /// çağrıdan sonra set edilebilir (bkz. BabyRepository.pullFromServer dokümanı).
  Future<void> _pull(String? acct) async {
    if (!ref.read(loggedInProvider)) return;
    List<Baby> removed;
    try {
      // Kendi (sahip) bebeklerimi buluta yüklemek KENDİ premium'uma bağlı (local-first:
      // free'de kendi verim telefonda kalır); paylaşımlı (parent) bebeğin profil/foto
      // değişikliği ise sahibin bulutuna bağlı → oturum yeterli, premium'um şart değil.
      // pullFromServer her oturumda koşar → paylaşılan bebek profilini/üyeliği tazeler.
      await _repo.pushDirty(
          accountId: acct, includeOwned: ref.read(cloudSyncEnabledProvider));
      removed = await _repo.pullFromServer(accountId: acct);
    } catch (_) {
      return; // çevrimdışı/hata → yerel korunur
    }
    for (final b in removed) {
      // Erişim kaldırıldı (paylaşımdan düşme / sahibin premium'u bitti): bu bebeğin
      // TÜM yerel verisini temizle. Veri sahibe aitti, cihazda kalmamalı:
      // kayıt + anı + anne + SAĞLIK (aşı/gelişim/diş) + hatırlatıcılar. Bebek
      // satırının kendisi pullFromServer'da zaten silinir.
      try {
        await ref.read(recordRepositoryProvider).purgeBaby(b.id);
        await ref.read(memoryRepositoryProvider).purgeBaby(b.id);
        await ref.read(momRepositoryProvider).purgeBaby(b.id);
        await ref.read(healthRepositoryProvider).purgeBaby(b.id);
      } catch (_) {}
      await ActivityNotifCache().clearSeen(b.id);
      final slot = b.notifSlot;
      NotificationService.instance
          .cancelTimer(NotificationService.sleepIdFor(slot));
      NotificationService.instance
          .cancelTimer(NotificationService.breastIdFor(slot));
      NotificationService.instance.scheduleFeedReminder(
          enabled: false, nextTime: null, preMin: 0, slot: slot, babyName: b.name);
      NotificationService.instance.showActivity(
          title: b.name, body: tr('Bu bebeğe erişimin kaldırıldı'));
    }
  }

  /// Öne gelince/açılışta çağrılır. Premium'da sunucuyla reconcile; free'de no-op.
  Future<void> refresh() => _pull(ref.read(activeAccountIdProvider));
}

final babyControllerProvider =
    AsyncNotifierProvider<BabyController, List<Baby>>(BabyController.new);

/// Seçili (aktif) bebeğin id'si. null → ilk bebek varsayılır.
class ActiveBabyIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final activeBabyIdProvider =
    NotifierProvider<ActiveBabyIdNotifier, String?>(ActiveBabyIdNotifier.new);

/// Aktif bebek nesnesi — seçili id geçersizse ilk bebeğe düşer.
final activeBabyProvider = Provider<Baby?>((ref) {
  final babies = ref.watch(babyControllerProvider).asData?.value ?? [];
  if (babies.isEmpty) return null;
  final id = ref.watch(activeBabyIdProvider);
  return babies.where((b) => b.id == id).firstOrNull ?? babies.first;
});
