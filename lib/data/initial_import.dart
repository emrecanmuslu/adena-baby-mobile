import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'baby_repository.dart';
import 'cycle_repository.dart';
import 'local_session.dart';
import 'memory_repository.dart';
import 'mom_repository.dart';
import 'record_repository.dart';

/// Tek-seferlik **cloud→local import** (mevcut kullanıcı göçü). Local-first'e
/// geçişten ÖNCE veri yalnız sunucudaydı (uygulama login zorunluydu). İlk
/// güncel sürümde, oturum açık kullanıcının sunucudaki verisi (bebek + kayıt +
/// anı + anne + adet) bir kez yerele indirilir; sonra herkes local-first çalışır.
/// Premium'dan bağımsız çalışır — yalnızca bir defalık göç okuması.
class InitialImportService {
  final Ref _ref;
  InitialImportService(this._ref);

  Future<void> runIfNeeded() async {
    final acct = LocalSession.activeAccountId;
    if (acct == null) return; // oturum yok
    if (LocalSession.importedForAccount(acct)) return; // bu hesap zaten indirildi
    await _import(acct);
  }

  /// Bayraktan bağımsız zorunlu cloud→yerel indirme. Kullanıcı-tetikli "bulut
  /// yedeğini sil" öncesi güvenlik: cloud'da olup yerelde olmayan bir şey kalmasın.
  Future<void> forceImport() async {
    final acct = LocalSession.activeAccountId;
    if (acct == null) return;
    await _import(acct);
  }

  Future<void> _import(String acct) async {
    try {
      final babyRepo = _ref.read(babyRepositoryProvider);
      // Bebekleri indir (yerelde olmayan + dirty olmayanları reconcile eder;
      // free'de yerel oluşturulmuş dirty bebekler korunur, silinmez).
      await babyRepo.pullFromServer();
      final babies = await babyRepo.getAll();
      for (final b in babies) {
        try {
          // Kayıtları salt-okuma GET ile çek (free, premium-gated /sync'e yazamaz).
          await _ref.read(recordRepositoryProvider).importFromCloud(b.id);
        } catch (_) {}
        try {
          await _ref.read(memoryRepositoryProvider).importFromCloud(b.id);
        } catch (_) {}
        try {
          await _ref.read(momRepositoryProvider).importFromCloud(b.id);
        } catch (_) {}
      }
      try {
        await _ref.read(cycleRepositoryProvider).importFromCloud();
      } catch (_) {}
      await LocalSession.markImportedForAccount(acct);
    } catch (_) {
      // Çevrimdışı/hata → bayrak set EDİLMEZ; sonraki açılışta tekrar denenir.
    }
  }
}

final initialImportProvider =
    Provider<InitialImportService>((ref) => InitialImportService(ref));
