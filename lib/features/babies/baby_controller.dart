import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../data/activity_notif_cache.dart';
import '../../data/baby_repository.dart';
import '../../data/record_repository.dart';
import '../../models/baby.dart';
import '../auth/auth_controller.dart';

const _uuid = Uuid();

/// Kullanıcının erişebildiği bebekler. Oturum değişince yeniden yüklenir.
class BabyController extends AsyncNotifier<List<Baby>> {
  BabyRepository get _repo => ref.read(babyRepositoryProvider);

  @override
  Future<List<Baby>> build() async {
    // Oturuma bağımlı: çıkış yapılınca boş liste, giriş yapılınca yeniden çek.
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) return [];
    return _repo.list();
  }

  /// Onboarding'den yeni bebek oluşturur (istemci-üretimli UUID).
  Future<Baby> create({
    required String name,
    required BabyStatus status,
    BabyGender gender = BabyGender.unknown,
    DateTime? birthDate,
    DateTime? dueDate,
  }) async {
    final baby = Baby(
      id: _uuid.v4(),
      name: name,
      gender: gender,
      status: status,
      birthDate: birthDate,
      dueDate: dueDate,
    );
    final created = await _repo.create(baby);
    state = AsyncData([...(state.asData?.value ?? []), created]);
    return created;
  }

  /// Bebek alanlarını günceller (ad/cinsiyet/tarih, "doğdu" geçişi).
  Future<Baby> updateBaby(String id, Map<String, dynamic> fields) async {
    final updated = await _repo.update(id, fields);
    state = AsyncData([
      for (final b in state.asData?.value ?? []) b.id == id ? updated : b,
    ]);
    return updated;
  }

  Future<void> deleteBaby(String id) async {
    await _repo.delete(id);
    state = AsyncData([
      for (final b in state.asData?.value ?? []) if (b.id != id) b,
    ]);
  }

  /// Bebek listesini sunucudan tazeler ve erişimi kaldırılan (artık üyesi olmadığın)
  /// bebekleri tespit eder: yerel verisini temizler + "erişimin kaldırıldı" bildirimi.
  /// Öne gelince/açılışta çağrılır (push yok → değişiklik böyle yakalanır).
  Future<void> refresh() async {
    if (ref.read(authControllerProvider).asData?.value == null) return;
    final prev = state.asData?.value ?? const [];
    final List<Baby> fresh;
    try {
      fresh = await _repo.list();
    } catch (_) {
      return; // çevrimdışı/hata → mevcut listeyi koru
    }
    state = AsyncData(fresh);
    if (prev.isEmpty) return;
    final freshIds = fresh.map((b) => b.id).toSet();
    for (final b in prev.where((b) => !freshIds.contains(b.id))) {
      try {
        await ref.read(recordRepositoryProvider).purgeBaby(b.id); // eski veriyi sil
      } catch (_) {}
      await ActivityNotifCache().clearSeen(b.id);
      // Sayaç/beslenme bildirimini de kapat (slot artık o bebeğe ait değil).
      final slot = b.notifSlot;
      NotificationService.instance.cancelTimer(NotificationService.sleepIdFor(slot));
      NotificationService.instance.cancelTimer(NotificationService.breastIdFor(slot));
      NotificationService.instance.scheduleFeedReminder(
          enabled: false, nextTime: null, preMin: 0, slot: slot, babyName: b.name);
      NotificationService.instance.showActivity(
          title: b.name, body: tr('Bu bebeğe erişimin kaldırıldı'));
    }
  }
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
