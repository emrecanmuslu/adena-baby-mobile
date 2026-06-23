import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// iOS Live Activity köprüsü (süren emzirme/uyku sayacı — kilit ekranı + Dynamic
/// Island). Tek aktif sayaç gösterilir. Android'de ve iOS<16.1'de no-op
/// (native taraf sessizce yok sayar). Sayaç cihaz-tarafı sayar (push'suz).
class LiveActivityService {
  LiveActivityService._();

  static const MethodChannel _ch = MethodChannel('adena/live_activity');
  static bool _active = false;
  static String? _lastSig;

  /// Aktif sayacı başlat/güncelle. [effectiveStart] = sayacın etkin başlangıcı
  /// (geçen süre = now - effectiveStart); native `Text(_:style:.timer)` buradan sayar.
  static Future<void> sync({
    required String kind, // "sleep" | "breast"
    required String babyName,
    required DateTime effectiveStart,
    required bool paused,
    required int pausedSeconds,
    required String side, // "left" | "right" | ""
    required bool en,
  }) async {
    if (!Platform.isIOS) return;
    final sig = '$kind|$babyName|${effectiveStart.millisecondsSinceEpoch}|$paused|$side|$en';
    if (_active && sig == _lastSig) return; // gereksiz güncelleme yok
    _lastSig = sig;
    try {
      await _ch.invokeMethod('startOrUpdate', {
        'kind': kind,
        'babyName': babyName,
        'startEpoch': effectiveStart.millisecondsSinceEpoch / 1000.0,
        'paused': paused,
        'pausedSeconds': pausedSeconds,
        'side': side,
        'en': en,
      });
      _active = true;
    } catch (_) {
      // Live Activity izni yok / desteklenmiyor → sessiz.
    }
  }

  /// Aktif Live Activity'yi bitir (sayaç durunca).
  static Future<void> end() async {
    if (!Platform.isIOS || !_active) return;
    _lastSig = null;
    try {
      await _ch.invokeMethod('end');
      _active = false;
    } catch (_) {}
  }
}
