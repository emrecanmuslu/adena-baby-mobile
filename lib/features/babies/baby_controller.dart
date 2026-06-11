import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/baby_repository.dart';
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
