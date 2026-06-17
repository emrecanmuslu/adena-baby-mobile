import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'baby_repository.dart';
import 'cycle_repository.dart';
import 'local/app_database.dart';
import 'memory_repository.dart';
import 'mom_repository.dart';
import 'record_repository.dart';
import 'sync_gate.dart';

/// Migrasyon adımının durumu.
enum StepStatus { pending, active, done }

/// Tek bir migrasyon adımı (ör. "Bebekler", "Kayıtlar").
class MigrationStep {
  final String key;
  final int count; // yüklenecek öğe sayısı (0 = adım atlanır görünümü)
  final StepStatus status;
  const MigrationStep(this.key, this.count, this.status);

  MigrationStep copyWith({StepStatus? status}) =>
      MigrationStep(key, count, status ?? this.status);
}

enum MigrationPhase { idle, running, done, error }

/// free→premium yükleme akışının genel durumu (overlay bunu dinler).
class MigrationState {
  final MigrationPhase phase;
  final List<MigrationStep> steps;
  const MigrationState(this.phase, this.steps);

  const MigrationState.idle()
      : phase = MigrationPhase.idle,
        steps = const [];

  /// Tamamlanan / toplam adım (ilerleme çubuğu için).
  double get progress {
    if (steps.isEmpty) return 0;
    final done = steps.where((s) => s.status == StepStatus.done).length;
    return done / steps.length;
  }

  MigrationState withStep(String key, StepStatus status) => MigrationState(
        phase,
        [for (final s in steps) s.key == key ? s.copyWith(status: status) : s],
      );
}

/// free→premium **big-bang migrasyonu** durum kontrolcüsü. Cloud senkron açıldığı
/// an yereldeki TÜM dirty veri sunucuya idempotent (istemci-UUID) yüklenir ve
/// ilerleme adım-adım yayınlanır → kullanıcı süreci tam-ekran görür.
class MigrationController extends Notifier<MigrationState> {
  @override
  MigrationState build() => const MigrationState.idle();

  Future<void> run() async {
    if (state.phase == MigrationPhase.running) return;
    final ref = this.ref;
    final db = ref.read(databaseProvider);
    final babyRepo = ref.read(babyRepositoryProvider);

    // Adımları + sayıları önceden hesapla (boş adımlar da gösterilir, çabuk biter).
    final babies = await babyRepo.getAll();
    final steps = [
      MigrationStep('babies', await _dirtyCount(db, 'babies'), StepStatus.pending),
      MigrationStep('records', await _dirtyCount(db, 'records'), StepStatus.pending),
      MigrationStep('memories', await _dirtyCount(db, 'memories'), StepStatus.pending),
      MigrationStep('mom', await _dirtyCount(db, 'mom_entries'), StepStatus.pending),
      MigrationStep('cycle', await _dirtyCount(db, 'cycle_entries'), StepStatus.pending),
    ];
    // Yüklenecek yerel (dirty) veri yoksa overlay'i hiç gösterme — mevcut premium
    // kullanıcıda boş yanıp sönmesin. Yalnız gerçek free→premium göçünde görünür.
    if (steps.every((s) => s.count == 0)) return;
    state = MigrationState(MigrationPhase.running, steps);

    Future<void> step(String key, Future<void> Function() work) async {
      state = state.withStep(key, StepStatus.active);
      try {
        await work();
      } catch (_) {
        // tekil adım hatası tüm akışı düşürmesin — dirty kalır, sonra denenir
      }
      state = state.withStep(key, StepStatus.done);
    }

    await step('babies', () => babyRepo.pushDirty());
    await step('records', () async {
      for (final b in babies) {
        await ref.read(recordRepositoryProvider).sync(b.id);
      }
    });
    await step('memories', () async {
      for (final b in babies) {
        await ref.read(memoryRepositoryProvider).pushDirty(b.id);
      }
    });
    await step('mom', () async {
      for (final b in babies) {
        await ref.read(momRepositoryProvider).pushDirty(b.id);
      }
    });
    await step('cycle', () => ref.read(cycleRepositoryProvider).migrateToCloud());

    state = MigrationState(MigrationPhase.done, state.steps);
  }

  /// Overlay'i kapatır (kullanıcı "Bitti" deyince ya da otomatik).
  void dismiss() => state = const MigrationState.idle();

  static Future<int> _dirtyCount(AppDatabase db, String table) async {
    try {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $table WHERE dirty = 1')
          .getSingle();
      return row.read<int>('c');
    } catch (_) {
      return 0;
    }
  }
}

final migrationControllerProvider =
    NotifierProvider<MigrationController, MigrationState>(
        MigrationController.new);

/// Cloud senkron açıldığı an (oturum + premium) migrasyonu tetikler. Kökte
/// (AdenaApp) `ref.watch` edilir ki dinleyici canlı kalsın.
final localToCloudMigrationProvider = Provider<void>((ref) {
  ref.listen<bool>(cloudSyncEnabledProvider, (prev, next) {
    final became = (prev ?? false) == false && next == true;
    if (became) {
      unawaited(ref.read(migrationControllerProvider.notifier).run());
    }
  });
});
