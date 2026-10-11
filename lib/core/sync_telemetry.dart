import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

/// Senkron görünürlük olayları — Crashlytics **non-fatal** (INCELEME I1 telemetri,
/// §5.6 R4 koruması). Davranışı DEĞİŞTİRMEZ; saha ölçümü içindir:
///  • `health_pull_cleared_done`: pull temiz `done=true` satıra sunucunun
///    "pending"ini yazdı (K-4 "sunucu kazanır" gerçekleşti).
///  • `stale_delete_skipped`: R4 silmesi K-2 korumasıyla atlandı (boş liste /
///    oran / güvenilmez yanıt).
/// Firebase hazır değilse sessiz. Testler [override] ile yakalar.
class SyncTelemetry {
  SyncTelemetry._();

  @visibleForTesting
  static Future<void> Function(String event, Map<String, Object?> info)? override;

  static Future<void> report(String event, Map<String, Object?> info) async {
    final o = override;
    if (o != null) {
      await o(event, info);
      return;
    }
    final desc = info.entries.map((e) => '${e.key}=${e.value}').join(' ');
    debugPrint('[sync-telemetry] $event $desc');
    try {
      final c = FirebaseCrashlytics.instance;
      c.log('[sync] $event $desc');
      await c.recordError('sync:$event $desc', null, reason: 'sync-telemetry', fatal: false);
    } catch (_) {
      // Firebase yok (test/çok erken çağrı) → konsola basıldı, yeter.
    }
  }
}
