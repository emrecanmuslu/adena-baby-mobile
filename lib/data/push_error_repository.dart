import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../features/auth/auth_controller.dart';
import 'baby_repository.dart';
import 'cycle_repository.dart';
import 'health_repository.dart';
import 'local/app_database.dart';
import 'memory_repository.dart';
import 'mom_repository.dart';
import 'sync_merge.dart';

/// Kalıcı reddedilmiş (`pushError` dolu) yerel değişiklikler — K-1
/// (TASARIM-SENKRON.md §6b): sayaç (banner), liste (sheet), "geri al".
enum PushErrorKind { baby, memory, mom, cycleEntry, cycleSettings, health }

class PushErrorItem {
  final PushErrorKind kind;
  /// Satır kimliği; sağlıkta `kind/itemKey`.
  final String id;
  final String? babyId;
  final String title;
  final String? subtitle;
  final String error;
  final bool isDeleted;
  const PushErrorItem({
    required this.kind,
    required this.id,
    required this.babyId,
    required this.title,
    required this.error,
    this.subtitle,
    this.isDeleted = false,
  });
}

class PushErrorRepository {
  final AppDatabase _db;
  final BabyRepository _babies;
  final MemoryRepository _memories;
  final MomRepository _mom;
  final CycleRepository _cycle;
  final HealthRepository _health;
  PushErrorRepository(
      this._db, this._babies, this._memories, this._mom, this._cycle, this._health);

  static const _countSql = '''
SELECT
  (SELECT COUNT(*) FROM babies WHERE push_error IS NOT NULL AND account_id = ?1)
+ (SELECT COUNT(*) FROM memories m JOIN babies b ON b.id = m.baby
     WHERE m.push_error IS NOT NULL AND b.account_id = ?1)
+ (SELECT COUNT(*) FROM mom_entries m JOIN babies b ON b.id = m.baby
     WHERE m.push_error IS NOT NULL AND b.account_id = ?1)
+ (SELECT COUNT(*) FROM cycle_entries WHERE push_error IS NOT NULL AND account_id = ?1)
+ (SELECT COUNT(*) FROM cycle_settings_table WHERE push_error IS NOT NULL AND id = ?1)
+ (SELECT COUNT(*) FROM health_statuses h JOIN babies b ON b.id = h.baby
     WHERE h.push_error IS NOT NULL AND b.account_id = ?1) AS c''';

  /// Aktif hesabın gönderilemeyen değişiklik sayısı (reaktif; 6 tablo).
  Stream<int> watchCount(String accountId) => _db
      .customSelect(_countSql, variables: [Variable.withString(accountId)], readsFrom: {
        _db.babies,
        _db.memories,
        _db.momEntries,
        _db.cycleEntries,
        _db.cycleSettingsTable,
        _db.healthStatuses,
      })
      .watchSingle()
      .map((r) => r.read<int>('c'));

  Future<List<PushErrorItem>> list(String accountId) async {
    final out = <PushErrorItem>[];
    final babies = await (_db.select(_db.babies)
          ..where((b) => b.accountId.equals(accountId)))
        .get();
    final babyIds = babies.map((b) => b.id).toList();
    final nameOf = {for (final b in babies) b.id: b.name};
    for (final b in babies.where((b) => b.pushError != null)) {
      out.add(PushErrorItem(
          kind: PushErrorKind.baby,
          id: b.id,
          babyId: b.id,
          title: b.name,
          error: b.pushError!,
          isDeleted: b.isDeleted));
    }
    if (babyIds.isNotEmpty) {
      for (final m in await (_db.select(_db.memories)
            ..where((m) => m.baby.isIn(babyIds) & m.pushError.isNotNull()))
          .get()) {
        out.add(PushErrorItem(
            kind: PushErrorKind.memory,
            id: m.id,
            babyId: m.baby,
            title: m.title.isEmpty ? (nameOf[m.baby] ?? '') : m.title,
            subtitle: _ymd(m.date),
            error: m.pushError!,
            isDeleted: m.isDeleted));
      }
      for (final m in await (_db.select(_db.momEntries)
            ..where((m) => m.baby.isIn(babyIds) & m.pushError.isNotNull()))
          .get()) {
        out.add(PushErrorItem(
            kind: PushErrorKind.mom,
            id: m.id,
            babyId: m.baby,
            title: m.title?.isNotEmpty == true ? m.title! : m.kind,
            subtitle: _ymd(m.date),
            error: m.pushError!,
            isDeleted: m.isDeleted));
      }
      for (final h in await (_db.select(_db.healthStatuses)
            ..where((h) => h.baby.isIn(babyIds) & h.pushError.isNotNull()))
          .get()) {
        out.add(PushErrorItem(
            kind: PushErrorKind.health,
            id: '${h.kind}/${h.itemKey}',
            babyId: h.baby,
            title: h.itemKey,
            subtitle: nameOf[h.baby],
            error: h.pushError!));
      }
    }
    for (final e in await (_db.select(_db.cycleEntries)
          ..where((e) => e.accountId.equals(accountId) & e.pushError.isNotNull()))
        .get()) {
      out.add(PushErrorItem(
          kind: PushErrorKind.cycleEntry,
          id: e.id,
          babyId: null,
          title: _ymd(e.date),
          error: e.pushError!,
          isDeleted: e.isDeleted));
    }
    final cs = await (_db.select(_db.cycleSettingsTable)
          ..where((s) => s.id.equals(accountId) & s.pushError.isNotNull()))
        .getSingleOrNull();
    if (cs != null) {
      out.add(PushErrorItem(
          kind: PushErrorKind.cycleSettings,
          id: cs.id,
          babyId: null,
          title: 'cycle_settings',
          error: cs.pushError!));
    }
    return out;
  }

  /// "Değişikliği geri al": sunucu kopyasını GET edip uygula (dirty=false,
  /// pushError=null). Sunucuda yoksa `notOnServer` (çağıran onayla `discard`).
  Future<RevertResult> revert(PushErrorItem it) {
    switch (it.kind) {
      case PushErrorKind.baby:
        return _babies.revertToServer(it.id);
      case PushErrorKind.memory:
        return _memories.revertToServer(it.babyId!, it.id);
      case PushErrorKind.mom:
        return _mom.revertToServer(it.babyId!, it.id);
      case PushErrorKind.cycleEntry:
        return _cycle.revertEntryToServer(it.id);
      case PushErrorKind.cycleSettings:
        return _cycle.revertSettingsToServer();
      case PushErrorKind.health:
        final i = it.id.indexOf('/');
        return _health.revertToServer(
            it.babyId!, it.id.substring(0, i), it.id.substring(i + 1));
    }
  }

  /// Sunucuda olmayan (yerelde oluşturulmuş) satırı KULLANICI ONAYIYLA yerelden
  /// siler. Bebek için silme yapılmaz: satır yerelde temiz bırakılır
  /// (KARAR-BEKLEYEN.md) — tombstone bebek ise satır kaldırılır.
  Future<void> discard(PushErrorItem it) {
    switch (it.kind) {
      case PushErrorKind.baby:
        return _babies.keepLocalOnly(it.id);
      case PushErrorKind.memory:
        return _memories.discardLocal(it.id);
      case PushErrorKind.mom:
        return _mom.discardLocal(it.id);
      case PushErrorKind.cycleEntry:
        return _cycle.discardEntry(it.id);
      case PushErrorKind.cycleSettings:
      case PushErrorKind.health:
        return Future.value(); // sunucuda her zaman var; buraya düşmez
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final pushErrorRepositoryProvider = Provider<PushErrorRepository>((ref) =>
    PushErrorRepository(
        ref.watch(databaseProvider),
        ref.watch(babyRepositoryProvider),
        ref.watch(memoryRepositoryProvider),
        ref.watch(momRepositoryProvider),
        ref.watch(cycleRepositoryProvider),
        ref.watch(healthRepositoryProvider)));

/// Aktif hesabın gönderilemeyen değişiklik sayısı (banner). Oturum yoksa 0.
final pushErrorCountProvider = StreamProvider<int>((ref) {
  final acct = ref.watch(activeAccountIdProvider);
  if (acct == null) return Stream.value(0);
  return ref.watch(pushErrorRepositoryProvider).watchCount(acct);
});
