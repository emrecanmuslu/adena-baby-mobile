import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Uygulama içinden ana ekrana "sonraki beslenme" widget'ı ekleme (Android
/// `AppWidgetManager.requestPinAppWidget`). Bazı launcher'larda (Xiaomi) widget
/// seçicide bulunamıyor; bu yol seçiciyi atlar. iOS'ta karşılığı yok → hep
/// desteklenmez sayılır.
///
/// Kanal: MainActivity'deki `adena/widget` — `isPinSupported`, `requestPin`;
/// native taraf widget yerleşince `pinned(widgetId)` çağırır.
class WidgetPinService {
  WidgetPinService({bool? isAndroid, MethodChannel? channel})
      : _isAndroid = isAndroid ?? Platform.isAndroid,
        _channel = channel ?? const MethodChannel(channelName) {
    if (_isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'pinned') _pinned.add(call.arguments as int? ?? -1);
      });
    }
  }

  static const channelName = 'adena/widget';

  final bool _isAndroid;
  final MethodChannel _channel;
  final _pinned = StreamController<int>.broadcast();

  /// Launcher widget'ı ana ekrana yerleştirdiğinde (widget id ile) yayar.
  Stream<int> get pinned => _pinned.stream;

  /// Bu cihazın launcher'ı uygulama içinden sabitlemeyi destekliyor mu?
  Future<bool> isSupported() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isPinSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sistem onay penceresini açar. true = istek launcher'a iletildi (kullanıcı
  /// henüz onaylamadı; asıl ekleme [pinned] ile gelir). [babyId] widget'ın
  /// bağlanacağı bebek (native taraf geri çağrıda ya da açılışta eşler).
  Future<bool> requestPin({String? babyId}) async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPin', {'babyId': babyId}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

final widgetPinServiceProvider =
    Provider<WidgetPinService>((ref) => WidgetPinService());

/// Ayarlar'daki "Ana ekrana widget ekle" satırı yalnız bu true iken görünür.
final widgetPinSupportedProvider = FutureProvider<bool>(
    (ref) => ref.watch(widgetPinServiceProvider).isSupported());
