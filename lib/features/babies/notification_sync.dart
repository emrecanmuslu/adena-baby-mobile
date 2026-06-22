import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/widget_service.dart';
import '../../data/feed_reminder_cache.dart';
import '../../models/baby.dart';
import '../../models/feed_reminder.dart';
import '../../models/quiet_hours.dart';
import '../../models/record.dart';
import '../babies/family_settings.dart';
import '../records/record_controller.dart';
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
        // Ana ekran widget'ı aktif bebeğin son beslenmesini gösterir.
        const _WidgetSync(),
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
    for (final b in born) {
      final recs = ref.watch(recentRecordsProvider(b.id)).asData?.value ?? const [];
      final cfg = ref.watch(feedReminderProvider(b.id));
      final next =
          nextFeedEstimate(cfg.enabled ? cfg : const FeedReminderConfig(), recs);
      widgetBabies.add(WidgetBaby(id: b.id, name: b.name, nextFeed: next));
    }
    final activeId = ref.watch(activeBabyProvider)?.id ?? born.first.id;
    // build içinde yan-etki: bu ekran zaten görünmez senkron katmanı.
    WidgetService.publishAll(widgetBabies, activeId);
    return const SizedBox.shrink();
  }
}

/// Süren uyku sayacının cihaz bildirimini eşitler ([r] yoksa iptal eder).
/// Üst seviye → hem reaktif sync hem resume'da yeniden-post aynı mantığı kullanır.
void syncSleepTimer(Baby baby, Record? r) {
  final slot = baby.notifSlot;
  if (r == null) {
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
void syncBreastTimer(Baby baby, Record? r) {
  final slot = baby.notifSlot;
  if (r == null) {
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
  for (final b in babies) {
    if (b.isExpecting) continue;
    syncSleepTimer(b, ref.read(ongoingSleepProvider(b.id)));
    syncBreastTimer(b, ref.read(ongoingBreastProvider(b.id)));
  }
}

class _BabyNotifSync extends ConsumerWidget {
  final Baby baby;
  const _BabyNotifSync({required this.baby, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bekleme (gebelik) modunda kayıt/sayaç/beslenme uyarısı yok.
    if (!baby.isExpecting) {
      syncSleepTimer(baby, ref.watch(ongoingSleepProvider(baby.id)));
      syncBreastTimer(baby, ref.watch(ongoingBreastProvider(baby.id)));
      _syncFeed(
        ref.watch(feedReminderProvider(baby.id)),
        ref.watch(recentRecordsProvider(baby.id)).asData?.value ?? const [],
        ref.watch(quietHoursProvider(baby.id)),
      );
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
      ),
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
    );
  }
}
