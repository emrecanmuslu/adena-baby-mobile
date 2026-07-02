import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../features/babies/baby_controller.dart';
import 'baby_repository.dart';
import 'health_repository.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'memory_repository.dart';
import 'migration_service.dart';
import 'mom_repository.dart';
import 'record_repository.dart';
import 'sync_gate.dart';

/// Misafir ("kayıt olmadan devam et") verisini gerçek hesaba bağlar.
///
/// Misafir modda yerel veri device-UUID (`LocalSession.userId`) kapsamına yazılır
/// (`babies.account_id` / `cycle_entries.account_id` = guestId). Kullanıcı giriş/
/// kayıt yapınca aktif hesap gerçek `user.id`'ye geçtiği için bu veri "kaybolur"
/// (repo'lar yeni hesaba göre kapsamlar). Burada, kullanıcı ONAYLARSA, kapsam
/// gerçek hesaba REBIND edilir. Kayıt/anı/anne/sağlık tabloları bebek FK üzerinden
/// (account_id taşımaz) otomatik taşınır. Premium ise buluta tam yükleme tetiklenir.
class GuestMigration {
  /// Gerçek hesaba AİT OLMAYAN (misafir kapsamındaki) yerel bebek verisi var mı?
  /// login sonrası "kayıtlarını aktaralım mı?" sorusunu tetikler.
  static Future<bool> hasData(AppDatabase db, String selfAccountId) async {
    final guestId = LocalSession.userId;
    if (guestId.isEmpty || guestId == selfAccountId) return false;
    try {
      final row = await db.customSelect(
        'SELECT COUNT(*) AS c FROM babies WHERE account_id = ? AND is_deleted = 0',
        variables: [Variable<String>(guestId)],
      ).getSingle();
      return row.read<int>('c') > 0;
    } catch (_) {
      return false;
    }
  }

  /// Misafir verisini gerçek hesaba taşır. [ref] = AdenaApp WidgetRef.
  static Future<void> migrate(WidgetRef ref, String newAccountId) async {
    final db = ref.read(databaseProvider);
    final guestId = LocalSession.userId;
    if (guestId.isEmpty || guestId == newAccountId) return;
    final now = DateTime.now().toUtc();

    // Bebekler: kapsamı yeni hesaba taşı + dirty (premium'da buluta yüklensin).
    await (db.update(db.babies)..where((b) => b.accountId.equals(guestId))).write(
      BabiesCompanion(
        accountId: Value(newAccountId),
        dirty: const Value(true),
        clientUpdatedAt: Value(now),
      ),
    );
    // Adet kayıtları: aynı şekilde.
    await (db.update(db.cycleEntries)..where((e) => e.accountId.equals(guestId)))
        .write(
      CycleEntriesCompanion(
        accountId: Value(newAccountId),
        dirty: const Value(true),
        clientUpdatedAt: Value(now),
      ),
    );
    // Adet ayarı (tekil satır; id = hesap id). Yeni hesapta ayar yoksa misafirinkini
    // taşı; varsa (buluttan indi) yeni hesabınki korunur, misafirinki silinir.
    final guestS = await (db.select(db.cycleSettingsTable)
          ..where((s) => s.id.equals(guestId)))
        .getSingleOrNull();
    if (guestS != null) {
      final newS = await (db.select(db.cycleSettingsTable)
            ..where((s) => s.id.equals(newAccountId)))
          .getSingleOrNull();
      if (newS == null) {
        await db.into(db.cycleSettingsTable).insertOnConflictUpdate(
              CycleSettingsTableCompanion(
                id: Value(newAccountId),
                baby: Value(guestS.baby),
                birthDate: Value(guestS.birthDate),
                breastfeeding: Value(guestS.breastfeeding),
                firstPeriodDate: Value(guestS.firstPeriodDate),
                reminders: Value(guestS.reminders),
                showFertilityWarning: Value(guestS.showFertilityWarning),
                enabled: Value(guestS.enabled),
                expectedCycleLength: Value(guestS.expectedCycleLength),
                periodLength: Value(guestS.periodLength),
                lutealPhaseLength: Value(guestS.lutealPhaseLength),
                smartPrediction: Value(guestS.smartPrediction),
                weekStartsSunday: Value(guestS.weekStartsSunday),
                clientUpdatedAt: Value(now),
                dirty: const Value(true),
              ),
            );
      }
      await (db.delete(db.cycleSettingsTable)..where((s) => s.id.equals(guestId)))
          .go();
    }

    // Yerel akışları tazele → bebek listesi/kayıtlar yeni hesap altında görünsün.
    // babyController'ın drift stream'i ESKİ hesap kapsamına (misafir id) bağlı kalmış
    // olabilir: register anında rebuild olurken statik activeAccountId henüz gerçek
    // hesaba geçmemişti. refresh() (=cloud pull) yerel stream'i yeniden kurmaz → tam
    // invalidate ile temiz yeniden kur; yeni watchAll güncel hesabı sorgular ve rebound
    // bebeği görür (aksi halde onboarding'de takılı kalır).
    db.refreshSyncedStreams();
    ref.invalidate(babyControllerProvider);

    // Premium ise buluta tam yükleme (overlay ile). Free ise veri yerelde hesap
    // altında kalır; kullanıcı sonradan premium olursa migrasyon zaten yükler.
    if (ref.read(cloudSyncEnabledProvider)) {
      await LocalSession.clearPremiumSyncedForAccount(newAccountId);
      await ref.read(migrationControllerProvider.notifier).run();
    }
  }

  /// "Hayır" (aktarmayı reddet) + silme onayı sonrası: misafir kapsamındaki TÜM
  /// yerel veriyi KALICI siler. babies + kayıt/anı/anne/sağlık/hatırlatıcı (bebek
  /// FK) + adet (guestId kapsamı). Yalnız yerel; sunucuya hiç gitmemişti.
  static Future<void> discard(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final guestId = LocalSession.userId;
    if (guestId.isEmpty) return;
    final babies =
        await ref.read(babyRepositoryProvider).getAll(accountId: guestId);
    for (final b in babies) {
      try {
        await ref.read(recordRepositoryProvider).purgeBaby(b.id);
        await ref.read(memoryRepositoryProvider).purgeBaby(b.id);
        await ref.read(momRepositoryProvider).purgeBaby(b.id);
        await ref.read(healthRepositoryProvider).purgeBaby(b.id);
      } catch (_) {}
    }
    await (db.delete(db.babies)..where((b) => b.accountId.equals(guestId))).go();
    await (db.delete(db.cycleEntries)..where((e) => e.accountId.equals(guestId)))
        .go();
    await (db.delete(db.cycleSettingsTable)..where((s) => s.id.equals(guestId)))
        .go();
    db.refreshSyncedStreams();
    ref.invalidate(babyControllerProvider);
  }
}
