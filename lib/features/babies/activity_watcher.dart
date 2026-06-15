import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../data/activity_notif_cache.dart';
import '../../data/sharing_repository.dart';
import '../../models/activity_event.dart';
import '../auth/auth_controller.dart';
import 'baby_controller.dart';

/// Aile etkinlik bildirimi tercihi (cihaz-yerel, opt-in). Varsayılan kapalı.
class ActivityNotifEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ActivityNotifCache().enabled();

  Future<void> set(bool v) async {
    await ActivityNotifCache().setEnabled(v);
    state = AsyncData(v);
    // Açar açmaz YALNIZ cursor'u kur, geçmişi bildirme. silent şart: kapalıyken
    // birikmiş olaylar yüzünden cursor bayatlamıştır; silent olmadan tekrar açış
    // o birikimin tamamını tek seferde bildirir (flood). bkz. _pollBaby.
    if (v) ref.read(familyActivityWatcherProvider).poll(silent: true);
  }
}

final activityNotifEnabledProvider =
    AsyncNotifierProvider<ActivityNotifEnabled, bool>(ActivityNotifEnabled.new);

/// Aktivite akışını yoklayıp (polling, Yol A) başka üyelerin eklediği kayıtlar
/// için yerel bildirim basar. Push yok — uygulama açık/öne gelince çalışır.
/// Kullanıcının ERİŞTİĞİ TÜM bebekler yoklanır; her bildirimin başlığı bebek adı
/// olduğundan çok bebekte hangisinden geldiği ayırt edilir.
class FamilyActivityWatcher {
  final Ref ref;
  bool _busy = false;
  FamilyActivityWatcher(this.ref);

  /// [silent] true ise olaylar bildirilmez; yalnız cursor en yeni damgaya çekilir.
  /// Bildirimi açar açmaz çağrılır — bayat cursor'un birikmiş geçmişi flood
  /// etmesini önler (yeni eşik olarak "şimdi"yi kurar).
  Future<void> poll({bool silent = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await ActivityNotifCache().enabled()) return;
      final me = ref.read(authControllerProvider).asData?.value;
      final babies = ref.read(babyControllerProvider).asData?.value ?? [];
      if (me == null || babies.isEmpty) return;
      final repo = ref.read(sharingRepositoryProvider);
      final cache = ActivityNotifCache();
      for (final baby in babies) {
        // Tek üyeli (paylaşımsız) bebekte başka aktör yok → yoklama gereksiz.
        if (!baby.isShared) continue;
        await _pollBaby(repo, cache, baby.id, baby.name, me.id, silent: silent);
      }
    } catch (_) {
      // Polling hatası sessiz — UI/uygulama akışını etkilemesin.
    } finally {
      _busy = false;
    }
  }

  Future<void> _pollBaby(SharingRepository repo, ActivityNotifCache cache,
      String babyId, String babyName, String myId, {bool silent = false}) async {
    try {
      final since = await cache.lastSeen(babyId);
      final events = await repo.activity(babyId, since: since);
      if (events.isEmpty) return;
      // Cursor'u DAİMA en yeni damgaya çek — sunucu sıralamasına güvenme (sırasız
      // dönerse cursor geri çekilip aynı olaylar tekrar bildirilir). Bildirimleri
      // de kronolojik (eski→yeni) bas.
      final ordered = [...events]..sort((a, b) => a.ts.compareTo(b.ts));
      final newest = ordered.last.ts;
      // İlk çalıştırmada (since==null) ya da açılış sessiz turunda geçmişi bildirme;
      // yalnız cursor kur. silent: kapalıyken biriken olayların flood'unu önler.
      if (since != null && !silent) {
        for (final e in ordered) {
          if (e.actor == null || e.actor!.id == myId) continue; // kendi eylemim hariç
          // Push aynı olayı zaten göstermiş olabilir → olay-id dedup (çift önleme).
          if (!await cache.markNotifiedIfNew(e.id)) continue;
          await NotificationService.instance
              .showActivity(title: babyName, body: activityMessage(e));
        }
      }
      await cache.setLastSeen(babyId, newest);
    } catch (_) {
      // tek bebek başarısız olsa diğerleri devam etsin
    }
  }
}

final familyActivityWatcherProvider =
    Provider<FamilyActivityWatcher>((ref) => FamilyActivityWatcher(ref));

/// "{kim}, {ne} kaydı ekledi" gibi okunur metin. action ör: created_feed,
/// created_diaper, started_sleep.
String activityMessage(ActivityEvent e) {
  final who = e.actor?.displayName ?? tr('Bir üye');
  final a = e.action;
  if (a.startsWith('created_')) {
    return trp('{who}, {what} kaydı ekledi',
        {'who': who, 'what': _recordTypeLabel(a.substring(8))});
  }
  if (a.startsWith('started_')) {
    return trp('{who}, {what} başlattı',
        {'who': who, 'what': _recordTypeLabel(a.substring(8))});
  }
  return who;
}

String _recordTypeLabel(String type) => switch (type) {
      'diaper' => tr('bez'),
      'breast' => tr('emzirme'),
      'formula' => tr('mama'),
      'pumped' => tr('biberon'),
      'solid' => tr('ek gıda'),
      'pumping' => tr('süt sağma'),
      'feed' => tr('beslenme'),
      'sleep' => tr('uyku'),
      'growth' => tr('büyüme'),
      'temperature' => tr('ateş'),
      'medication' => tr('ilaç'),
      'bath' => tr('banyo'),
      'appointment' => tr('randevu'),
      _ => tr('kayıt'),
    };
