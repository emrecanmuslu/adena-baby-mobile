import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'baby_repository.dart';
import 'cycle_repository.dart';
import 'health_repository.dart';
import 'local/app_database.dart';
import 'local_session.dart';
import 'memory_repository.dart';
import 'mom_repository.dart';
import 'record_repository.dart';
import 'subscription_repository.dart';
import 'sync_gate.dart';

/// Migrasyon yönü: yerel→bulut yükleme (premium açılışı) ya da bulut→yerel indirip
/// bulut yedeğini kalıcı silme (premium bitince "İndir ve sil"). Overlay metinleri
/// buna göre değişir; akış mekaniği (adım-adım ilerleme) ortaktır.
enum MigrationKind { upload, purge }

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
  final MigrationKind kind;
  const MigrationState(this.phase, this.steps,
      {this.kind = MigrationKind.upload});

  const MigrationState.idle()
      : phase = MigrationPhase.idle,
        steps = const [],
        kind = MigrationKind.upload;

  /// Tamamlanan / toplam adım (ilerleme çubuğu için).
  double get progress {
    if (steps.isEmpty) return 0;
    final done = steps.where((s) => s.status == StepStatus.done).length;
    return done / steps.length;
  }

  MigrationState withStep(String key, StepStatus status) => MigrationState(
        phase,
        [for (final s in steps) s.key == key ? s.copyWith(status: status) : s],
        kind: kind,
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

    final acct = LocalSession.activeAccountId;
    if (acct == null) return;
    // Bu hesabın yereli daha önce tam yüklendiyse migrasyon/overlay tekrar ÇALIŞMAZ.
    // Sebep: cloudSync her uygulama açılışında false→true olur (premium çözülünce)
    // → bu kontrol olmadan "buluta yükleniyor" ekranı HER girişte çıkardı. Bayrak
    // YALNIZ cloud gerçekten silinince (purge damgası, subscription_repository) temizlenir
    // → grace-içi lapse/yeniden-abonelikte zaten cloud'da olan veri tekrar yüklenmez.
    if (LocalSession.premiumSyncedForAccount(acct)) return;

    final db = ref.read(databaseProvider);
    final babyRepo = ref.read(babyRepositoryProvider);

    final babies = await babyRepo.getAll();

    // TAM yükleme garanti et: aktif hesabın tüm yerel satırlarını dirty işaretle.
    // Sebep: push yolları yalnız dirty satırları gönderir. Grace dolup cloud kopyası
    // silindiyse (ya da kullanıcı "buluttan sil" dediyse) eski satırlar dirty=0
    // olduğundan yeniden yüklenmez → geçmiş cloud'da/yeni cihazda eksik kalırdı.
    // İstemci-UUID upsert idempotent → grace-içi yeniden abonelikte cloud'daki
    // satırlar zararsızca güncellenir, çift kayıt olmaz.
    // YALNIZ sahip olunan bebekler: paylaşımlı bebek sahibine ait, üye onu
    // yüklemez (aksi halde 403 + gereksiz "yedekleniyor" overlay'i).
    final owned =
        babies.where((b) => b.myRole == null || b.myRole == 'owner').toList();
    await babyRepo.markAllDirty();
    for (final b in owned) {
      await ref.read(recordRepositoryProvider).markAllDirty(b.id);
      await ref.read(memoryRepositoryProvider).markAllDirty(b.id);
      await ref.read(momRepositoryProvider).markAllDirty(b.id);
    }
    await ref.read(cycleRepositoryProvider).markAllDirty();

    // Adımları + sayıları önceden hesapla — HESAP-KAPSAMLI (çoklu yerel hesapta başka
    // hesabın dirty satırları overlay'i yanlışlıkla tetiklemesin). Bebek tablosu
    // account_id; kayıt/anı/anne bebek üzerinden transitif.
    const inOwnBabies =
        'baby IN (SELECT id FROM babies WHERE account_id=?)';
    final steps = [
      MigrationStep('babies',
          await _dirtyCount(db, 'babies WHERE dirty=1 AND account_id=?', acct),
          StepStatus.pending),
      MigrationStep('records',
          await _dirtyCount(db, 'records WHERE dirty=1 AND $inOwnBabies', acct),
          StepStatus.pending),
      MigrationStep('memories',
          await _dirtyCount(db, 'memories WHERE dirty=1 AND $inOwnBabies', acct),
          StepStatus.pending),
      MigrationStep('mom',
          await _dirtyCount(db, 'mom_entries WHERE dirty=1 AND $inOwnBabies', acct),
          StepStatus.pending),
      MigrationStep('cycle',
          await _dirtyCount(db, 'cycle_entries WHERE dirty=1 AND account_id=?', acct),
          StepStatus.pending),
      // Sağlık durumu (aşı/gelişim/diş işaretleri) — local-first; push = tüm küme.
      MigrationStep('health',
          await _dirtyCount(db, 'health_statuses WHERE $inOwnBabies', acct),
          StepStatus.pending),
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
    await step('health', () async {
      for (final b in owned) {
        await ref.read(healthRepositoryProvider).pushAll(b.id);
      }
    });

    // Tam yükleme turu tamamlandı → bir daha overlay gösterme (kalan dirty satırlar
    // normal senkronla gider). Lapse'te bu bayrak temizlenir.
    await LocalSession.markPremiumSyncedForAccount(acct);
    state = MigrationState(MigrationPhase.done, state.steps);
  }

  /// Premium bitince kullanıcı-tetikli "İndir ve sil": önce buluttaki TÜM veriyi
  /// yerele indirir (güvenlik — cloud'da olup yerelde olmayan bir şey kalmasın),
  /// sonra bulut yedeğini kalıcı siler. İlerleme yükleme overlay'i ile AYNI
  /// tam-ekranda adım-adım gösterilir; indirme tam sayfalama olduğundan süreç
  /// yükleme kadar uzun sürebilir → kullanıcı boş spinner yerine ne olduğunu görür.
  Future<void> runPurge() async {
    if (state.phase == MigrationPhase.running) return;
    final ref = this.ref;
    final acct = LocalSession.activeAccountId;
    if (acct == null) return;
    final babyRepo = ref.read(babyRepositoryProvider);

    final steps = [
      const MigrationStep('babies', 0, StepStatus.pending),
      const MigrationStep('records', 0, StepStatus.pending),
      const MigrationStep('memories', 0, StepStatus.pending),
      const MigrationStep('mom', 0, StepStatus.pending),
      const MigrationStep('cycle', 0, StepStatus.pending),
      const MigrationStep('health', 0, StepStatus.pending),
      const MigrationStep('purge', 0, StepStatus.pending),
    ];
    state = MigrationState(MigrationPhase.running, steps,
        kind: MigrationKind.purge);

    Future<void> step(String key, Future<void> Function() work) async {
      state = state.withStep(key, StepStatus.active);
      try {
        await work();
      } catch (_) {
        // tekil adım hatası tüm akışı düşürmesin
      }
      state = state.withStep(key, StepStatus.done);
    }

    // 1) Buluttaki her şeyi yerele indir (salt-okuma GET, tam sayfalama).
    await step('babies', () => babyRepo.pullFromServer());
    final babies = await babyRepo.getAll();
    await step('records', () async {
      for (final b in babies) {
        try {
          await ref.read(recordRepositoryProvider).importFromCloud(b.id);
        } catch (_) {}
      }
    });
    await step('memories', () async {
      for (final b in babies) {
        try {
          await ref.read(memoryRepositoryProvider).importFromCloud(b.id);
        } catch (_) {}
      }
    });
    await step('mom', () async {
      for (final b in babies) {
        try {
          await ref.read(momRepositoryProvider).importFromCloud(b.id);
        } catch (_) {}
      }
    });
    await step('cycle', () async {
      try {
        await ref.read(cycleRepositoryProvider).importFromCloud();
      } catch (_) {}
    });
    await step('health', () async {
      for (final b in babies) {
        try {
          await ref.read(healthRepositoryProvider).importFromCloud(b.id);
        } catch (_) {}
      }
    });
    // İndirme tamamlandı → açılışta otomatik import tekrar denenmesin.
    await LocalSession.markImportedForAccount(acct);

    // 2) Bulut yedeğini kalıcı sil (backend cloud_purged_at damgalar →
    // SubscriptionRepository._store premiumSynced bayrağını temizler).
    await step('purge', () async {
      await ref.read(subscriptionRepositoryProvider).purgeCloudData();
    });
    ref.invalidate(subscriptionProvider);
    state = MigrationState(MigrationPhase.done, state.steps,
        kind: MigrationKind.purge);
  }

  /// Overlay'i kapatır (kullanıcı "Bitti" deyince ya da otomatik).
  void dismiss() => state = const MigrationState.idle();

  /// `fromWhere` = "tablo WHERE ..." (tek `?` parametresi = aktif hesap id).
  static Future<int> _dirtyCount(
      AppDatabase db, String fromWhere, String acct) async {
    try {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $fromWhere',
              variables: [Variable<String>(acct)])
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
