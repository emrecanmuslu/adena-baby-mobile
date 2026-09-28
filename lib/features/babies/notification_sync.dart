import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/age.dart';
import '../../core/i18n.dart';
import '../../core/leaps.dart';
import '../../core/live_activity_service.dart';
import '../../core/notification_service.dart';
import '../../core/widget_service.dart';
import '../../data/feed_reminder_cache.dart';
import '../../data/health_repository.dart';
import '../../data/leap_repository.dart';
import '../../data/leap_weeks.dart';
import '../../data/notification_prefs.dart';
import '../../models/baby.dart';
import '../../models/feed_reminder.dart';
import '../../models/quiet_hours.dart';
import '../../models/record.dart';
import '../babies/family_settings.dart';
import '../records/record_controller.dart';
import '../settings/notification_prefs_controller.dart';
import 'baby_controller.dart';

/// TÜM bebekler için süren sayaç (uyku/emzirme) + beslenme hatırlatıcısı
/// bildirimlerini cihazla eşitler — yalnız aktif bebek değil. Böylece iki bebekte
/// biri uyurken diğerine geçince sayaç kaybolmaz; her bildirimin id'si bebek
/// slotuna göre ayrık (çakışmaz) ve başlığı bebek adıyla başlar.
///
/// Görünmez; uygulama ağacında bir kez (MaterialApp.builder) render edilir.
class FamilyNotificationSync extends ConsumerWidget {
  const FamilyNotificationSync({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babies = ref.watch(babyControllerProvider).asData?.value ?? const [];
    // Her bebek için ayrı bir izleyici alt-widget (kendi provider'larını dinler).
    return Stack(
      children: [
        for (final b in babies) _BabyNotifSync(baby: b, key: ValueKey(b.id)),
        // Özel/randevu hatırlatıcıları: açılışta sunucudan çek + global planla.
        for (final b in babies) _ReminderSync(baby: b, key: ValueKey('rem-${b.id}')),
        // Aşı/atak/büyüme/gebelik haftası/gelişim/diş hatırlatıcıları.
        for (final b in babies) _HealthNotifSync(baby: b, key: ValueKey('health-${b.id}')),
        // Ana ekran widget'ı aktif bebeğin son beslenmesini gösterir.
        const _WidgetSync(),
        // iOS Live Activity (süren sayaç — kilit ekranı + Dynamic Island).
        const _LiveActivitySync(),
      ],
    );
  }
}

/// Aktif bebeğin son beslenmesini ana ekran widget'ına yansıtır (uygulama
/// açıkken reaktif: yeni beslenme kaydı geldikçe widget güncellenir).
class _WidgetSync extends ConsumerWidget {
  const _WidgetSync();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Çok-bebek: her widget kendi bebeğini gösterebildiği için TÜM (doğmuş)
    // bebeklerin sonraki-beslenme verisini yaz. Sonraki beslenme = hatırlatıcı
    // açıksa onun aralığı, değilse varsayılan (ana sayfa kartıyla aynı mantık).
    final babies = ref.watch(babyControllerProvider).asData?.value ?? const [];
    final born = babies.where((b) => !b.isExpecting).toList();
    if (born.isEmpty) return const SizedBox.shrink();
    final widgetBabies = <WidgetBaby>[];
    var allKnown = true;
    for (final b in born) {
      final recs = ref.watch(recentRecordsProvider(b.id)).asData?.value ?? const [];
      // Ayar henüz yerelden okunmadıysa `effectiveForEstimate` VARSAYILANA (2 saat)
      // düşer; o tahmini widget'a yazmak "3 saat yerine 2 saat"in ta kendisidir.
      if (!ref.watch(feedReminderKnownProvider(b.id))) allKnown = false;
      final effCfg = ref.watch(feedReminderProvider(b.id)).effectiveForEstimate;
      final next = nextFeedEstimate(effCfg, recs);
      final last = lastFeedAt(effCfg, recs);
      widgetBabies
          .add(WidgetBaby(id: b.id, name: b.name, nextFeed: next, lastFeed: last));
    }
    final activeId = ref.watch(activeBabyProvider)?.id ?? born.first.id;
    // build içinde yan-etki: bu ekran zaten görünmez senkron katmanı.
    // Bayat ama DOĞRU değer, taze ama yanlış değerden iyidir → ayar bilinene dek
    // widget'a dokunma (bir sonraki build'de, ms'ler içinde, doğrusuyla yazılır).
    if (allKnown) WidgetService.publishAll(widgetBabies, activeId);
    return const SizedBox.shrink();
  }
}

/// Tek aktif uyku/emzirme sayacını iOS Live Activity'sine yansıtır (kilit ekranı
/// + Dynamic Island). Çok bebekte ilk aktif sayaç (önce emzirme, sonra uyku)
/// gösterilir. Android/iOS<16.1'de no-op. Görünmez senkron katmanı.
class _LiveActivitySync extends ConsumerWidget {
  const _LiveActivitySync();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babies = ref.watch(babyControllerProvider).asData?.value ?? const [];
    final en = I18n.instance.locale == 'en';
    final born = babies.where((b) => !b.isExpecting).toList();

    // Tüm provider'ları KOŞULSUZ izle (Riverpod tutarlılığı), sonra ilk aktifi seç.
    Record? chosenBreast;
    Baby? chosenBreastBaby;
    Record? chosenSleep;
    Baby? chosenSleepBaby;
    for (final b in born) {
      final breast = ref.watch(ongoingBreastProvider(b.id));
      final sleep = ref.watch(ongoingSleepProvider(b.id));
      if (breast != null && chosenBreast == null) {
        chosenBreast = breast;
        chosenBreastBaby = b;
      }
      if (sleep != null && chosenSleep == null) {
        chosenSleep = sleep;
        chosenSleepBaby = b;
      }
    }

    if (chosenBreast != null) {
      final d = chosenBreast.data;
      final paused = d['paused'] == true;
      final side = d['side'] == 'right' ? 'right' : 'left';
      var ms = (((d['left_ms'] as num?) ?? 0) + ((d['right_ms'] as num?) ?? 0)).toInt();
      final seg = DateTime.tryParse(d['seg_start_ts'] as String? ?? '')?.toLocal();
      if (seg != null && !paused) {
        ms += DateTime.now().difference(seg).inMilliseconds.clamp(0, 24 * 3600 * 1000);
      }
      LiveActivityService.sync(
        kind: 'breast',
        babyName: chosenBreastBaby!.name,
        effectiveStart: DateTime.now().subtract(Duration(milliseconds: ms)),
        paused: paused,
        pausedSeconds: ms ~/ 1000,
        side: side,
        en: en,
      );
    } else if (chosenSleep != null) {
      final start =
          DateTime.tryParse(chosenSleep.data['start_ts'] as String? ?? '')?.toLocal() ??
              chosenSleep.ts;
      LiveActivityService.sync(
        kind: 'sleep',
        babyName: chosenSleepBaby!.name,
        effectiveStart: start,
        paused: false,
        pausedSeconds: 0,
        side: '',
        en: en,
      );
    } else {
      LiveActivityService.end();
    }
    return const SizedBox.shrink();
  }
}

/// Süren uyku sayacının cihaz bildirimini eşitler ([r] yoksa iptal eder).
/// Üst seviye → hem reaktif sync hem resume'da yeniden-post aynı mantığı kullanır.
/// [enabled] false (Bildirimler ayarından kapatıldı) → sayaç bildirimi hiç
/// gösterilmez; sayacın KENDİSİ çalışmaya devam eder (yalnız görünürlük kapanır).
void syncSleepTimer(Baby baby, Record? r, {bool enabled = true}) {
  final slot = baby.notifSlot;
  if (r == null || !enabled) {
    NotificationService.instance.cancelTimer(NotificationService.sleepIdFor(slot));
    return;
  }
  final start =
      DateTime.tryParse(r.data['start_ts'] as String? ?? '')?.toLocal() ?? r.ts;
  NotificationService.instance.showTimer(
    id: NotificationService.sleepIdFor(slot),
    title: '${baby.name} · ${tr('Uyku sürüyor')}',
    body: tr('Bebeğiniz uyuyor · dokun ve bitir'),
    since: start,
    running: true,
  );
}

/// Süren emzirme sayacının cihaz bildirimini eşitler ([r] yoksa iptal eder).
/// [enabled] için bkz. [syncSleepTimer].
void syncBreastTimer(Baby baby, Record? r, {bool enabled = true}) {
  final slot = baby.notifSlot;
  if (r == null || !enabled) {
    NotificationService.instance.cancelTimer(NotificationService.breastIdFor(slot));
    return;
  }
  final d = r.data;
  final paused = d['paused'] == true;
  final side = d['side'] == 'right' ? tr('Sağ') : tr('Sol');
  var ms = (((d['left_ms'] as num?) ?? 0) + ((d['right_ms'] as num?) ?? 0)).toInt();
  final seg = DateTime.tryParse(d['seg_start_ts'] as String? ?? '')?.toLocal();
  if (seg != null && !paused) {
    ms += DateTime.now().difference(seg).inMilliseconds.clamp(0, 24 * 3600 * 1000);
  }
  final since = DateTime.now().subtract(Duration(milliseconds: ms));
  NotificationService.instance.showTimer(
    id: NotificationService.breastIdFor(slot),
    title: paused
        ? '${baby.name} · ${tr('Emzirme duraklatıldı')}'
        : '${baby.name} · ${tr('Emzirme sürüyor')}',
    body: paused
        ? trp('{side} meme · {min} dk (duraklatıldı)',
            {'side': side, 'min': ms ~/ 60000})
        : trp('{side} memeden emziriyor · dokun ve bitir', {'side': side}),
    since: since,
    running: !paused,
  );
}

/// Tüm bebeklerin aktif uyku/emzirme sayacı bildirimini YENİDEN post eder.
/// Uygulama öne gelince (resume) çağrılır: kullanıcı bildirim iznini sistem
/// ayarlarından SONRADAN açtıysa, devam eden sayacın bildirimi yeniden belirir
/// (reaktif sync provider durumu değişmediğinden tetiklenmez). İzin hâlâ kapalıysa
/// `showTimer` sessizce no-op olur — zararsız ve tekrar etmesi güvenli (onlyAlertOnce).
void repostActiveTimers(WidgetRef ref) {
  final babies = ref.read(babyControllerProvider).asData?.value ?? const [];
  final timersOn = ref.read(notifPrefProvider(NotificationPrefs.timers));
  for (final b in babies) {
    if (b.isExpecting) continue;
    syncSleepTimer(b, ref.read(ongoingSleepProvider(b.id)), enabled: timersOn);
    syncBreastTimer(b, ref.read(ongoingBreastProvider(b.id)), enabled: timersOn);
  }
}

/// Özel/randevu hatırlatıcılarını GLOBAL katmanda cihaz bildirimleriyle eşitler
/// (önceden yalnız Hatırlatıcılar ekranı açıkken planlanıyordu — ekran hiç
/// açılmasa da açılışta planlar kurulur). Hatırlatıcılar KİŞİSELDİR (karar
/// 2026-07-07): aile paylaşımına dahil değildir, sunucuyla senkronlanmaz;
/// kaynak yalnız bu cihazdaki Drift.
/// Aşı/gelişim atağı/büyüme/gebelik haftası/gelişim basamağı/diş çıkarma
/// hatırlatıcılarını bebek verisinden hesaplayıp cihazla eşitler. Kullanıcı
/// yalnız Bildirimler ekranından aç/kapa yapar — zamanlama hep otomatiktir.
/// Görünmez; her veri değiştiğinde (aşı işaretlenince, yeni ölçüm girilince…)
/// yeniden hesaplanıp gerekirse yeni tarihe kayar.
class _HealthNotifSync extends ConsumerWidget {
  final Baby baby;
  const _HealthNotifSync({required this.baby, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = baby.notifSlot;
    final vaccineOn = ref.watch(notifPrefProvider(NotificationPrefs.vaccine));
    final leapOn = ref.watch(notifPrefProvider(NotificationPrefs.leap));
    final growthOn = ref.watch(notifPrefProvider(NotificationPrefs.growth));
    final pregOn = ref.watch(notifPrefProvider(NotificationPrefs.pregnancyWeek));
    final milestoneOn = ref.watch(notifPrefProvider(NotificationPrefs.milestone));
    final toothOn = ref.watch(notifPrefProvider(NotificationPrefs.tooth));
    final medicationOn = ref.watch(notifPrefProvider(NotificationPrefs.medication));

    // İlaç/vitamin — her aktif planın kendi günlük saatlerinde. Bebek
    // durumundan bağımsız hesaplanır (bekleme moduna dönerse de temizlensin
    // diye enabled'a !isExpecting eklenir, plan listesi zaten yalnız
    // doğmuş bebekte oluşturulabilir).
    final medPlans = ref.watch(medicationPlansProvider(baby.id)).asData?.value;
    if (medPlans != null) {
      for (final p in medPlans) {
        NotificationService.instance.syncMedicationPlan(
          enabled: medicationOn && p.active && !baby.isExpecting,
          planId: p.id,
          name: p.name,
          times: p.times,
          babyName: baby.name,
        );
      }
    }

    if (baby.isExpecting) {
      // Gebelik haftası — hafta değişince (09:00) tek seferlik.
      final due = baby.dueDate;
      final at = due == null ? null : nextPregnancyWeekBoundary(due);
      final week = due == null ? 0 : pregnancyWeeks(due) + 1;
      NotificationService.instance.syncPregnancyWeekReminder(
          enabled: pregOn, at: at, week: week, slot: slot, babyName: baby.name);
      // Doğmuş-bebek hatırlatıcıları bekleme modunda anlamsız → temizle.
      NotificationService.instance
          .syncVaccineReminder(enabled: false, dueDate: null, slot: slot);
      NotificationService.instance.syncLeapReminder(enabled: false, at: null, slot: slot);
      NotificationService.instance.syncGrowthReminder(enabled: false, at: null, slot: slot);
      NotificationService.instance.syncMilestoneCheckReminder(enabled: false, slot: slot);
      NotificationService.instance.syncToothCheckReminder(enabled: false, slot: slot);
      return const SizedBox.shrink();
    }

    // Doğmuş bebekte gebelik haftası hatırlatıcısı anlamsız → temizle.
    NotificationService.instance
        .syncPregnancyWeekReminder(enabled: false, at: null, slot: slot);

    // Aşı — en yakın (zorunlu, yapılmamış) aşının tarihinde.
    final vaccines = ref.watch(vaccinesProvider(baby.id)).asData?.value;
    if (vaccines != null) {
      final pending = vaccines.where((v) => !v.done && !v.optional).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
      final next = pending.firstOrNull;
      NotificationService.instance.syncVaccineReminder(
          enabled: vaccineOn,
          dueDate: next?.dueDate,
          vaccineName: next?.name ?? '',
          slot: slot,
          babyName: baby.name);
    }

    // Gelişim atağı — bir sonraki atağın huzursuz öncesi penceresi başlarken.
    final leaps = ref.watch(leapsProvider).asData?.value;
    final weeks = correctedAgeWeeks(baby);
    if (leaps != null) {
      LeapInfo? nextLeap;
      DateTime? at;
      if (weeks != null) {
        for (final l in leaps) {
          if (leapPhase(weeks, l.weekStart, l.fussyWeeksBefore) == LeapPhase.future) {
            nextLeap = l;
            break;
          }
        }
        if (nextLeap != null) {
          final anchor = baby.birthDate!.add(Duration(days: prematureEarlyDays(baby)));
          at = leapReminderDate(anchor, nextLeap.weekStart, nextLeap.fussyWeeksBefore);
        }
      }
      NotificationService.instance.syncLeapReminder(
          enabled: leapOn,
          at: at,
          leapTitle: nextLeap?.title ?? '',
          leapIndex: nextLeap?.index ?? 0,
          slot: slot,
          babyName: baby.name);
    }

    // Gelişim basamakları — yaşa yakın/işaretlenmemiş basamak varken periyodik
    // dürtme (ana sayfa "Gelişim" bölümüyle aynı "yakınlık" kuralı: ≤ yaş+2 ay).
    final milestones = ref.watch(milestonesProvider(baby.id)).asData?.value;
    if (milestones != null) {
      final age = correctedAgeMonths(baby);
      final pending = milestones.where((m) => !m.achieved);
      final relevant =
          age == null ? pending : pending.where((m) => m.expectedMonth <= age + 2);
      NotificationService.instance.syncMilestoneCheckReminder(
          enabled: milestoneOn && relevant.isNotEmpty, slot: slot);
    }

    // Diş çıkarma — bebek en erken tipik diş ayına ulaşınca, işaretlenmemiş
    // yakın diş varken periyodik dürtme.
    final teeth = ref.watch(teethProvider(baby.id)).asData?.value;
    if (teeth != null) {
      final age = correctedAgeMonths(baby);
      final minTypical =
          teeth.isEmpty ? null : teeth.map((t) => t.typicalMonth).reduce((a, b) => a < b ? a : b);
      final started = age != null && minTypical != null && age >= minTypical;
      final pending = teeth.where((t) => !t.erupted);
      final relevant =
          age == null ? pending : pending.where((t) => t.typicalMonth <= age + 2);
      NotificationService.instance.syncToothCheckReminder(
          enabled: toothOn && started && relevant.isNotEmpty, slot: slot);
    }

    // Büyüme ölçümü — son ölçümden (yoksa doğumdan) ~30 gün sonra.
    final latest = ref.watch(latestByTypeProvider(baby.id)).asData?.value;
    if (latest != null) {
      final anchor = latest[RecordType.growth]?.ts ?? baby.birthDate;
      DateTime? at;
      if (anchor != null) {
        final d = anchor.add(const Duration(days: 30));
        at = DateTime(d.year, d.month, d.day, 9);
      }
      NotificationService.instance.syncGrowthReminder(
          enabled: growthOn, at: at, slot: slot, babyName: baby.name);
    }

    return const SizedBox.shrink();
  }
}

class _ReminderSync extends ConsumerWidget {
  final Baby baby;
  const _ReminderSync({required this.baby, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Liste değiştikçe (ilk yükleme dahil) cihaz planlarını eşitle. Yalnız bu
    // provider izlendiğinden rebuild = liste değişimi; sync idempotenttir.
    // Yenileme (invalidate) sırasında asData ESKİ listeyi taşır — silinmiş bir
    // hatırlatıcıyı yeniden kurmamak için yalnız oturmuş veriyle çalış.
    final async = ref.watch(remindersProvider(baby.id));
    final list = async.isLoading ? null : async.asData?.value;
    if (list != null) NotificationService.instance.sync(list);
    return const SizedBox.shrink();
  }
}

class _BabyNotifSync extends ConsumerWidget {
  final Baby baby;
  const _BabyNotifSync({required this.baby, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // GEÇİŞ TOHUMU (kalıcı): beslenme hatırlatıcı aralığı artık cihaz-yerel
    // (feedReminderStoreProvider). Eski PAYLAŞIMLI sunucu değeri (familySettings)
    // yüklenince, yerelde bu bebek için kayıt YOKSA bir kez yerele yaz. Böylece
    // sonraki açılışlarda provider sunucuyu beklemeden yerelden döner ve _syncFeed
    // snapshot/App Group/widget/hatırlatıcıyı İLK ön planda doğru aralıkla yazar.
    final loadedFs = ref.watch(familySettingsProvider(baby.id)).asData?.value;
    if (loadedFs != null) {
      final feed = loadedFs['feed_reminder'];
      final seeded = FeedReminderConfig.fromMap(
          feed is Map ? Map<String, dynamic>.from(feed) : null);
      // "Yerelde kayıt var mı?" kontrolü notifier'ın İÇİNDE, yerel yükleme
      // bittikten SONRA yapılır — burada `containsKey` ile bakmak yarış
      // oluşturuyor ve cihazın kendi ayarını diskte eziyordu (bkz. seedIfMissing).
      // build sırasında provider durumu değiştirme → microtask'a ertele.
      Future.microtask(() => ref
          .read(feedReminderStoreProvider.notifier)
          .seedIfMissing(baby.id, seeded));
    }

    // Süren sayaç bildirimi kullanıcı tercihiyle kapatılabilir (cihaz-yerel).
    final timersOn = ref.watch(notifPrefProvider(NotificationPrefs.timers));

    // Bekleme (gebelik) modunda kayıt/sayaç/beslenme uyarısı yok.
    if (!baby.isExpecting) {
      syncSleepTimer(baby, ref.watch(ongoingSleepProvider(baby.id)),
          enabled: timersOn);
      syncBreastTimer(baby, ref.watch(ongoingBreastProvider(baby.id)),
          enabled: timersOn);
      // Provider'ları KOŞULSUZ izle (Riverpod bağımlılıkları sabit kalsın), sonra
      // aynayı yalnız ayar KESİN bilinirken yaz. Açılışta yerel depo diskten
      // okunana kadar `feedReminderProvider` VARSAYILANI (kapalı · 120 dk)
      // döndürüyor; o pencerede snapshot + App Group'a bunu yazarsak arka plan
      // yolları (push/bg sync/iOS NSE) 3 saatlik ayar yerine 2 saati okur.
      final frKnown = ref.watch(feedReminderKnownProvider(baby.id));
      final frCfg = ref.watch(feedReminderProvider(baby.id));
      final frRecs =
          ref.watch(recentRecordsProvider(baby.id)).asData?.value ?? const <Record>[];
      final frQuiet = ref.watch(quietHoursProvider(baby.id));
      if (frKnown) {
        _syncFeed(frCfg, frRecs, frQuiet);
      }
    } else {
      // Bebek bekleme moduna alındıysa eski planları/sayacı temizle.
      final slot = baby.notifSlot;
      NotificationService.instance.cancelTimer(NotificationService.sleepIdFor(slot));
      NotificationService.instance.cancelTimer(NotificationService.breastIdFor(slot));
      NotificationService.instance.scheduleFeedReminder(
          enabled: false, nextTime: null, preMin: 0, slot: slot, babyName: baby.name);
    }
    return const SizedBox.shrink();
  }

  void _syncFeed(FeedReminderConfig cfg, List<Record> recs, QuietHours quiet) {
    final slot = baby.notifSlot;
    // Arka plan (FCM push) yeniden planlaması için parametreleri sakla — başka
    // üye beslenme girince, uygulama kapalıyken bile hatırlatıcı kayabilsin.
    FeedReminderCache().save(
      baby.id,
      FeedReminderSnapshot(
        slot: slot,
        enabled: cfg.enabled,
        intervalMin: cfg.intervalMin,
        baseType: cfg.baseType,
        preMin: cfg.preMin,
        sound: cfg.soundEnabled,
        quiet: quiet,
        forgot: cfg.forgotEnabled,
      ),
    );
    // iOS force-quit'te NSE'nin bildirimi yeniden planlayabilmesi için aynı
    // parametreleri (locale'e çözülmüş metinlerle) App Group'a da aynala.
    WidgetService.publishFeedReminderConfig(
      babyId: baby.id,
      enabled: cfg.enabled,
      intervalMin: cfg.intervalMin,
      preMin: cfg.preMin,
      slot: slot,
      sound: cfg.soundEnabled,
      baseType: cfg.baseType,
      quiet: quiet,
      mainTitle: tr('Beslenme zamanı'),
      mainBody: tr('Tahmini beslenme vakti geldi 🍼'),
      preTitle: trp('Beslenmeye {n} dk kaldı', {'n': cfg.preMin}),
      preBody: trp('Yaklaşık {n} dk sonra beslenme zamanı', {'n': cfg.preMin}),
      forgotTitle: tr('Kaydı unuttun mu?'),
      forgotBody: tr('Beslenme saatinin üzerinden 30 dk geçti, henüz kayıt eklenmedi 🍼'),
      forgotEnabled: cfg.forgotEnabled,
    );
    if (!cfg.enabled) {
      NotificationService.instance.scheduleFeedReminder(
          enabled: false, nextTime: null, preMin: 0, slot: slot, babyName: baby.name);
      return;
    }
    NotificationService.instance.scheduleFeedReminder(
      enabled: true,
      nextTime: nextFeedEstimate(cfg, recs),
      preMin: cfg.preMin,
      slot: slot,
      babyName: baby.name,
      sound: cfg.soundEnabled,
      quiet: quiet,
      forgot: cfg.forgotEnabled,
    );
  }
}
