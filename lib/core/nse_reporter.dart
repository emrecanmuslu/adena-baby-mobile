// ╔══════════════════════════════════════════════════════════════════════════╗
// ║ 🧹 TANI-GEÇİCİ — widget/NSE sorunu çözülünce TÜM bu dosya silinecek.        ║
// ║ Kaldırma: bu dosyayı sil + main.dart'taki NseReporter import & çağrısını   ║
// ║ kaldır. Tam checklist: hafıza [[push-log-tanilama]] / [[widget-nse-tani]]. ║
// ╚══════════════════════════════════════════════════════════════════════════╝
import 'package:home_widget/home_widget.dart';

import 'api_client.dart';

/// iOS Notification Service Extension'ın (NSE) bıraktığı tanılama izini App Group'tan
/// okuyup backend'e raporlar — production cihazda /dev sayfası görünmediğinden
/// "NSE gerçekten koştu mu, ne gördü" Django admin'den (NseReport) izlenir.
///
/// NSE her push'ta App Group'a `nse_last_ts` (+ baby/active/fallback/next/event) yazar.
/// Bu sınıf ön plana her gelişte çağrılır; iz YENİYSE (nse_last_ts değişmiş) tek sefer
/// gönderir. Android'de App Group anahtarları boş döner → sessiz no-op.
class NseReporter {
  static const _appGroupId = 'group.com.adenababy.adenaBaby';
  static String? _lastReported;

  static Future<void> reportIfNew(ApiClient api) async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      final ts = await HomeWidget.getWidgetData<String>('nse_last_ts');
      if (ts == null || ts.isEmpty || ts == _lastReported) return;
      final event = await HomeWidget.getWidgetData<String>('nse_last_event');
      final baby = await HomeWidget.getWidgetData<String>('nse_last_baby');
      final active = await HomeWidget.getWidgetData<String>('nse_active_seen');
      final fallback = await HomeWidget.getWidgetData<String>('nse_wrote_fallback');
      final next = await HomeWidget.getWidgetData<String>('nse_next_ms');
      await api.dio.post('/auth/nse-report', data: {
        'ran_at': ts,
        'event_id': event ?? '',
        'baby_id': baby ?? '',
        'active_seen': active ?? '',
        'wrote_fallback': fallback == '1',
        'next_ms': next ?? '',
      });
      _lastReported = ts; // tek sefer; sonraki push izi değişince yeniden gönderilir
    } catch (_) {
      // ağ/oturum yok / Android / App Group desteklenmiyor → yoksay
    }
  }
}
