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

  /// D10: guard ile `state=running` arasındaki await'lerde ikinci `run()`
  /// (GuestMigration + localToCloudMigrationProvider) paralel tam yükleme
  /// başlatmasın.
  bool _starting = false;

  Future<void> run() async {
    if (state.phase == MigrationPhase.running || _starting) return;
    _starting = true;
    try {
      await _run();
    } finally {
      _starting = false;
    }
  }

  Future<void> _run() async {
    final ref = this.ref;

    final acct = LocalSession.activeAccountId;
    if (acct == null) return;
    // Bu hesabın yereli daha önce tam yüklendiyse migrasyon/overlay tekrar ÇALIŞMAZ.
    // Sebep: cloudSync her uygulama açılışında false→true olur (premium çözülünce)
    // → bu kontrol olmadan "buluta yükleniyor" ekranı HER girişte çıkardı. Bayrak
    // YALNIZ cloud gerçekten silinince (purge damgası, subscription_repository) temizlenir
    // → grace-içi lapse/yeniden-abonelikte zaten cloud'da olan veri tekrar yüklenmez.
    if (LocalSession.premiumSyncedForAccount(acct)) {
      // I1: premium bitip (lapse) yeniden abone olundu → sunucu kümesi bayat,
      // yerelde v14'ten kalma TEMİZ tikler olabilir. Tam yeniden yükleme (foto/
      // kayıt) gerekmez; yalnız sağlık TAM kümesi (yerel = doğru kaynak) bir kez
      // gönderilir, sonra bayrak düşer ve sağlık pull kapısı açılır. Overlay yok.
      if (LocalSession.healthReseedPending(acct)) await _reseedHealth(acct);
      return;
    }

    final db = ref.read(databaseProvider);
    final babyRepo = ref.read(babyRepositoryProvider);

    // J1: tüm repo çağrıları BAŞTA yakalanan `acct` ile yapılır; göç sırasında
    // kapsam değişirse (çıkış/başka hesap) sonunda bayrak yazılmaz.
    final babies = await babyRepo.getAll(accountId: acct);

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
    await babyRepo.markAllDirty(accountId: acct);
    for (final b in owned) {
      await ref.read(recordRepositoryProvider).markAllDirty(b.id);
      await ref.read(memoryRepositoryProvider).markAllDirty(b.id);
      await ref.read(momRepositoryProvider).markAllDirty(b.id);
    }
    await ref.read(cycleRepositoryProvider).markAllDirty(accountId: acct);

    // Adımları + sayıları önceden hesapla — HESAP-KAPSAMLI (çoklu yerel hesapta başka
    // hesabın dirty satırları overlay'i yanlışlıkla tetiklemesin). Bebek tablosu
    // account_id; kayıt/anı/anne bebek üzerinden transitif.
    const inOwnBabies =
        'baby IN (SELECT id FROM babies WHERE account_id=?)';
    final counts = <String, int?>{
      'babies': await _dirtyCount(db, 'babies WHERE dirty=1 AND account_id=?', acct),
      'records':
          await _dirtyCount(db, 'records WHERE dirty=1 AND $inOwnBabies', acct),
      'memories':
          await _dirtyCount(db, 'memories WHERE dirty=1 AND $inOwnBabies', acct),
      'mom':
          await _dirtyCount(db, 'mom_entries WHERE dirty=1 AND $inOwnBabies', acct),
      'cycle': await _dirtyCount(
          db, 'cycle_entries WHERE dirty=1 AND account_id=?', acct),
      // Sağlık durumu (aşı/gelişim/diş işaretleri) — local-first; push = tüm küme.
      'health': await _dirtyCount(db, 'health_statuses WHERE $inOwnBabies', acct),
    };
    // J1: sayım hatası "bilinmiyor"dur — "veri yok" kısayolu alınmaz ve göç
    // sonunda bayrak yazılmaz (sonraki açılışta yeniden denenir).
    final countsUnknown = counts.values.any((c) => c == null);
    final steps = [
      for (final e in counts.entries)
        MigrationStep(e.key, e.value ?? 0, StepStatus.pending),
    ];
    // Yüklenecek yerel (dirty) veri yoksa overlay'i hiç gösterme — mevcut premium
    // kullanıcıda boş yanıp sönmesin. Yalnız gerçek free→premium göçünde görünür.
    if (!countsUnknown && steps.every((s) => s.count == 0)) {
      // I1: kaybedilecek yerel veri yok (yeni cihaz / boş hesap) → hesap
      // "senkron" sayılır; sağlık pull kapısı (healthPullAllowed) açılsın.
      // Yerel sağlık satırı da yok → yeniden-tohumlama bekleyecek bir şey yok (J8).
      await LocalSession.markPremiumSyncedForAccount(acct);
      await LocalSession.clearHealthReseedForAccount(acct);
      return;
    }
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

    await step('babies', () async {
      await babyRepo.pushDirty(accountId: acct);
      await babyRepo.pushSettings(accountId: acct); // O4: ayar ayrı bayrakla
    });
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
    await step('cycle',
        () => ref.read(cycleRepositoryProvider).migrateToCloud(accountId: acct));
    // J1: sağlık tam kümesi TÜM sahip bebeklerde başarıyla gitmedikçe hesap
    // "senkron" sayılmaz (kapı `healthPullAllowed` kapalı kalır) — aksi hâlde
    // bir sonraki pull sunucunun boş/lazy kümesini temiz v14 tiklerine yazardı.
    var healthOk = true;
    await step('health', () async {
      for (final b in owned) {
        try {
          await ref.read(healthRepositoryProvider).pushAll(b.id);
        } catch (_) {
          healthOk = false;
        }
      }
    });

    state = MigrationState(MigrationPhase.done, state.steps);
    // J1: kapsam değiştiyse (çıkış / başka hesap) hiçbir bayrak yazılmaz —
    // eski hesap için bir sonraki girişte göç yeniden değerlendirilir.
    if (LocalSession.activeAccountId != acct) return;
    if (healthOk && !countsUnknown) {
      // Tam yükleme turu tamamlandı → bir daha overlay gösterme (kalan dirty
      // satırlar normal senkronla gider). Purge'te bu bayrak temizlenir.
      // J8: sağlık tam kümesi gitti → lapse kalıntısı reseed bayrağı düşer.
      await LocalSession.markPremiumSyncedForAccount(acct);
      await LocalSession.clearHealthReseedForAccount(acct);
    } else {
      // Sağlık yüklenemedi → yeniden-tohumlama beklesin; sonraki false→true
      // geçişinde (her açılış) `run()` yeniden dener, kapı o zamana dek kapalı.
      await LocalSession.markHealthReseedForAccount(acct);
    }
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
  /// I1: lapse sonrası yeniden abonelikte sahip bebeklerin sağlık işaretlerini
  /// gönderir; HEPSİ başarılıysa bayrağı düşürür (biri düşerse bir sonraki
  /// cloudSync false→true geçişinde — her açılışta olur — yeniden denenir).
  /// J2 / KB-12: tam küme DEĞİL, birleşim (`pushReseed`: done=true + damgalı
  /// satırlar) — damgasız done=false diğer cihazın işaretlerini ezmesin.
  Future<void> _reseedHealth(String acct) async {
    final ref = this.ref;
    final babies = await ref.read(babyRepositoryProvider).getAll(accountId: acct);
    final owned = babies.where((b) => b.myRole == null || b.myRole == 'owner');
    var allOk = true;
    for (final b in owned) {
      try {
        await ref.read(healthRepositoryProvider).pushReseed(b.id);
      } catch (_) {
        allOk = false;
      }
    }
    if (allOk) await LocalSession.clearHealthReseedForAccount(acct);
  }

  /// Döner: sayı; DB hatasında `null` ("bilinmiyor", J1 — 0 sayılmaz).
  static Future<int?> _dirtyCount(
      AppDatabase db, String fromWhere, String acct) async {
    try {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $fromWhere',
              variables: [Variable<String>(acct)])
          .getSingle();
      return row.read<int>('c');
    } catch (_) {
      return null;
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
      return;
    }
    // I1: premium bitti (lapse) — oturum hâlâ açıkken. Çıkış/zorunlu çıkışta
    // kapsam (activeAccountId) bu geçişten ÖNCE kapandığı için burada null →
    // bayrak kurulmaz. premiumSynced bilerek korunur (tam yeniden yükleme yok);
    // yeniden abonelikte yalnız sağlık tam kümesi gönderilir (_reseedHealth).
    if ((prev ?? false) && !next) {
      final acct = LocalSession.activeAccountId;
      if (acct != null) unawaited(LocalSession.markHealthReseedForAccount(acct));
    }
  });
});
