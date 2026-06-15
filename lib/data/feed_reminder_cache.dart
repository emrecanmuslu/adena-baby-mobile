import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/quiet_hours.dart';

/// Beslenme hatırlatıcısının ARKA PLAN isolate'ından (FCM push) yeniden
/// planlanabilmesi için gereken parametrelerin cihaz-yerel anlık görüntüsü.
///
/// Sorun: hatırlatıcı her cihazda YEREL hesaplanır (nextFeedEstimate, drift
/// kayıtlarından). Başka bir aile üyesi beslenme girince push gelir ama arka
/// plan isolate'ının drift'e/Riverpod'a erişimi yoktur. Bu snapshot ön planda
/// (FamilyNotificationSync._syncFeed) yazılır; push handler okuyup hatırlatıcıyı
/// yeni "son beslenme" zamanına göre yeniden kurar — drift'e hiç dokunmadan,
/// tıpkı widget'ın push'tan güncellenmesi gibi.
class FeedReminderSnapshot {
  final int slot; // bebek bildirim slotu (id çakışmasını önler)
  final bool enabled;
  final int intervalMin;
  final String baseType; // 'all' | 'breast' | 'formula'
  final int preMin;
  final bool sound;
  final QuietHours quiet;

  const FeedReminderSnapshot({
    required this.slot,
    required this.enabled,
    required this.intervalMin,
    required this.baseType,
    required this.preMin,
    required this.sound,
    required this.quiet,
  });

  /// Eklenen beslenmenin alt türü ([sub]) bu hatırlatıcının baz türüyle uyuşuyor
  /// mu? nextFeedEstimate'teki filtreyle birebir aynı mantık.
  bool matchesBase(String? sub) => switch (baseType) {
        'breast' => sub == 'breast',
        'formula' => sub == 'formula',
        _ => true,
      };

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'enabled': enabled,
        'interval_min': intervalMin,
        'base_type': baseType,
        'pre_min': preMin,
        'sound': sound,
        'quiet': quiet.toMap(),
      };

  factory FeedReminderSnapshot.fromJson(Map<String, dynamic> m) =>
      FeedReminderSnapshot(
        slot: (m['slot'] as num?)?.toInt() ?? 0,
        enabled: m['enabled'] as bool? ?? false,
        intervalMin: (m['interval_min'] as num?)?.toInt() ?? 120,
        baseType: m['base_type'] as String? ?? 'all',
        preMin: (m['pre_min'] as num?)?.toInt() ?? 0,
        sound: m['sound'] as bool? ?? false,
        quiet: QuietHours.fromMap((m['quiet'] as Map?)?.cast<String, dynamic>()),
      );
}

/// Snapshot'ı bebek başına saklar (ActivityNotifCache deseniyle aynı storage).
class FeedReminderCache {
  static const _storage = FlutterSecureStorage();
  static String _key(String babyId) => 'feed_reminder_snap_$babyId';
  // _syncFeed her build'de save çağırır; aynı içeriği tekrar tekrar keystore'a
  // yazmamak için son yazılan JSON'u bellekte tut, değişmedikçe atla.
  static final Map<String, String> _lastWritten = {};

  Future<void> save(String babyId, FeedReminderSnapshot snap) async {
    final json = jsonEncode(snap.toJson());
    if (_lastWritten[babyId] == json) return; // değişmemiş → yazma
    _lastWritten[babyId] = json;
    try {
      await _storage.write(key: _key(babyId), value: json);
    } catch (_) {
      _lastWritten.remove(babyId); // yazılamadıysa tekrar denensin
    }
  }

  Future<FeedReminderSnapshot?> read(String babyId) async {
    try {
      final s = await _storage.read(key: _key(babyId));
      if (s == null || s.isEmpty) return null;
      return FeedReminderSnapshot.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
