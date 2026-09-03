// ╔══════════════════════════════════════════════════════════════════════════╗
// ║ 🧹 TANI-GEÇİCİ — "sonraki beslenme 3 saat yerine 2 saat" sorunu çözülünce  ║
// ║ TÜM bu dosya silinecek. Kaldırma listesi:                                 ║
// ║  • bu dosya + `FwTrace.` çağrıları (push_service, background_sync,        ║
// ║    notification_sync, main.dart)                                          ║
// ║  • NotificationService.swift'teki `appendTrace` + çağrısı                 ║
// ║  • backend: accounts.FeedWidgetTrace modeli/görünümü/admin'i + migration  ║
// ╚══════════════════════════════════════════════════════════════════════════╝
import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';

/// Ana ekran widget'ının "sonraki beslenme" değerine yazan TÜM yolların izi.
///
/// Sorun: kullanıcının ayarı "son mama sonrası her 3 saat" olmasına rağmen widget
/// ara ara "son beslenme + 2 saat" gösteriyor. Widget'a beş ayrı yol yazabiliyor
/// (ön plan aynası, FCM push handler, arka plan sync, iOS NSE, publishAll) ve her
/// biri ayarı FARKLI bir aynadan okuyor (prefs snapshot / App Group). v1.4.17 bu
/// yolları tek kurala bağladı ama saha tekrarı sürüyor → hangi yolun HANGİ
/// aralıkla yazdığını (ya da hiç yazmayıp widget'ı bayat bıraktığını) görmeliyiz.
///
/// Depo: App Group / home_widget deposu (SharedPreferences DEĞİL). Sebep: izi
/// yazan yollar üç ayrı isolate'ta koşuyor (ön plan, FCM arka plan handler'ı,
/// workmanager sync isolate'i) ve SharedPreferences her isolate'ta kendi
/// belleğinde önbellekliyor → biri diğerinin yazdığını görmüyordu. home_widget
/// her çağrıda native tarafa gidiyor, yani isolate'lar arası tutarlı.
/// NSE ayrı bir ANAHTARA yazar ([_nseKey]) → aynı anda koşan NSE ile Dart
/// birbirinin satırını ezmez.
class FwTrace {
  static const _appGroupId = 'group.com.adenababy.adenaBaby';
  static const _appKey = 'fw_trace_app'; // Dart yolları (ön plan/push/bg sync)
  static const _nseKey = 'fw_trace_nse'; // iOS NSE (Swift tarafı yazar)
  static const _max = 40;

  /// Ön plan aynası her rebuild'de koşar → aynı satırı tekrar tekrar yazmamak
  /// için son yazılan imza. Yalnız DEĞİŞİM iz bırakır (halka dolmasın).
  static String? _lastSig;

  /// Bir yazım denemesini kaydeder. [action]: `write` (widget'a yazıldı) veya
  /// `skip_*` (neden yazılmadı — bayat widget'ın kanıtı).
  static Future<void> add({
    required String source, // 'push' | 'bgsync' | 'fg'
    required String action, // 'write' | 'skip_nosnap' | 'skip_base' | 'skip_nolast'
    String? babyId,
    String? eventId,
    String? feedSub,
    bool? enabled,
    int? interval,
    String? base,
    DateTime? last,
    DateTime? next,
  }) async {
    final sig = '$source|$babyId|$enabled|$interval|$base|$action';
    if (source == 'fg') {
      if (sig == _lastSig) return; // ön plan: yalnız değişince yaz
      _lastSig = sig;
    }
    final row = <String, dynamic>{
      'ran_at': DateTime.now().toUtc().toIso8601String(),
      'source': source,
      'action': action,
      'baby_id': ?babyId,
      'event_id': ?eventId,
      'feed_sub': ?feedSub,
      'enabled': ?enabled,
      'interval': ?interval,
      'base': ?base,
      if (last != null) 'last_ms': '${last.millisecondsSinceEpoch}',
      if (next != null) 'next_ms': '${next.millisecondsSinceEpoch}',
    };
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      final raw = await HomeWidget.getWidgetData<String>(_appKey);
      final list = _decode(raw)..add(row);
      if (list.length > _max) list.removeRange(0, list.length - _max);
      await HomeWidget.saveWidgetData<String>(_appKey, jsonEncode(list));
    } catch (_) {
      // Widget/App Group yok → tanı izi de yok; asıl akışı ASLA bozma.
    }
  }

  /// Biriken izleri (Dart + NSE) backend'e gönderir ve depoyu boşaltır.
  /// Ön plana her gelişte çağrılır; iz yoksa sessizce çıkar.
  static Future<void> upload(ApiClient api) async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      final appRaw = await HomeWidget.getWidgetData<String>(_appKey);
      final nseRaw = await HomeWidget.getWidgetData<String>(_nseKey);
      final rows = [..._decode(appRaw), ..._decode(nseRaw)];
      if (rows.isEmpty) return;
      // Zaman sırası: NSE ile Dart yolları ayrı anahtarlarda birikiyor; sunucuda
      // "kim en son yazdı" sorusunu yanıtlayabilmek için cihaz saatine göre sırala.
      rows.sort((a, b) =>
          (a['ran_at'] as String? ?? '').compareTo(b['ran_at'] as String? ?? ''));
      final info = await PackageInfo.fromPlatform();
      await api.dio.post('/auth/feed-widget-trace', data: {
        'app_version': '${info.version}+${info.buildNumber}',
        'traces': rows.take(50).toList(),
      });
      // Yalnız GÖNDERİM BAŞARILI olunca temizle (offline'da iz kaybolmasın).
      await HomeWidget.saveWidgetData<String>(_appKey, '');
      await HomeWidget.saveWidgetData<String>(_nseKey, '');
    } catch (_) {
      // ağ/oturum yok → bir sonraki ön plana gelişte tekrar denenir
    }
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final d = jsonDecode(raw);
      if (d is! List) return [];
      return [
        for (final e in d)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return [];
    }
  }
}
