import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/notification_prefs.dart';

/// Bildirim görünürlüğü tercihlerinin reaktif durumu (cihaz-yerel).
/// [FeedReminderNotifier] deseniyle aynı: tek notifier bir harita tutar; ayrı
/// ayrı family-notifier yerine tek yerden okunur/yazılır.
final notifPrefsProvider =
    NotifierProvider<NotifPrefsNotifier, Map<String, bool>>(
        NotifPrefsNotifier.new);

class NotifPrefsNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() {
    _load();
    // Yüklenene kadar hepsi AÇIK kabul edilir (varsayılanla aynı) → ilk
    // frame'de kapalıymış gibi görünüp bildirimi düşürmeyiz.
    return {for (final k in NotificationPrefs.all) k: true};
  }

  Future<void> _load() async {
    state = await NotificationPrefs.instance.readAll();
  }

  Future<void> set(String key, bool v) async {
    state = {...state, key: v};
    await NotificationPrefs.instance.setEnabled(key, v);
  }
}

/// Tek bir bildirim tercihi (varsayılan AÇIK).
final notifPrefProvider = Provider.family<bool, String>(
    (ref, key) => ref.watch(notifPrefsProvider)[key] ?? true);
