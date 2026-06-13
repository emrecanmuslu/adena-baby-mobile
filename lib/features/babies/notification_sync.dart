import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/widget_service.dart';
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
    final baby = ref.watch(activeBabyProvider);
    if (baby == null || baby.isExpecting) return const SizedBox.shrink();
    final recs =
        ref.watch(recentRecordsProvider(baby.id)).asData?.value ?? const [];
    DateTime? last;
    for (final r in recs) {
      if (r.type == RecordType.feed && !r.isOngoingBreast) {
        if (last == null || r.ts.isAfter(last)) last = r.ts;
      }
    }
    // build içinde yan-etki: bu ekran zaten görünmez senkron katmanı
    // (_BabyNotifSync de NotificationService'i build'de çağırıyor).
    WidgetService.updateLastFeed(babyName: baby.name, lastFeed: last);
    return const SizedBox.shrink();
  }
}

class _BabyNotifSync extends ConsumerWidget {
  final Baby baby;
  const _BabyNotifSync({required this.baby, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bekleme (gebelik) modunda kayıt/sayaç/beslenme uyarısı yok.
    if (!baby.isExpecting) {
      _syncSleep(ref.watch(ongoingSleepProvider(baby.id)));
      _syncBreast(ref.watch(ongoingBreastProvider(baby.id)));
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

  void _syncSleep(Record? r) {
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

  void _syncBreast(Record? r) {
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

  void _syncFeed(FeedReminderConfig cfg, List<Record> recs, QuietHours quiet) {
    final slot = baby.notifSlot;
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
