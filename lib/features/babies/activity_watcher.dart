import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activity_notif_cache.dart';
import '../../data/auth_repository.dart';

/// Aile etkinlik bildirimi tercihi (cihaz-yerel, varsayılan AÇIK). Tercih hem
/// istemcinin ön plan in-app banner'ını hem SUNUCUNUN push görünürlüğünü yönetir:
/// backend opt-out üyelere iOS'ta GÖRÜNÜR alert yerine SESSİZ push gönderir.
///
/// NOT: Aile etkinliği bildirimi artık YALNIZ push ile gelir (yerel aktivite
/// polling'i kaldırıldı — çift bildirim üretiyordu). Push ön planda in-app banner,
/// arka planda OS bildirimi olarak gösterilir.
class ActivityNotifEnabled extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ActivityNotifCache().enabled();

  Future<void> set(bool v) async {
    await ActivityNotifCache().setEnabled(v);
    state = AsyncData(v);
    // Tercihi SUNUCUYA bildir: backend opt-out üyelere iOS'ta GÖRÜNÜR alert yerine
    // SESSİZ push gönderir (banner çıkmaz, Android gibi). Opt-in'lere alert + NSE.
    try {
      await ref.read(authRepositoryProvider)
          .updateSettings({'notification_prefs': {'family_activity': v}});
    } catch (_) {
      // Çevrimdışı/oturum yok → açılışta (registerToken) tekrar senkronlanır.
    }
  }
}

final activityNotifEnabledProvider =
    AsyncNotifierProvider<ActivityNotifEnabled, bool>(ActivityNotifEnabled.new);
