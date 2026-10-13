import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/core/widget_pin_service.dart';
import 'package:adena_baby/features/settings/widget_pin_item.dart';

/// Ayarlar → "Ana ekrana widget ekle" (Android requestPinAppWidget, Xiaomi
/// seçici sorunu için). Native kanal `adena/widget` mock'lanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(WidgetPinService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late bool supported;
  late bool requestResult;

  setUp(() {
    calls = [];
    supported = true;
    requestResult = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isPinSupported':
          return supported;
        case 'requestPin':
          return requestResult;
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> pump(WidgetTester t, {required bool isAndroid}) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        widgetPinServiceProvider.overrideWithValue(
            WidgetPinService(isAndroid: isAndroid, channel: channel)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: WidgetPinMenuItem()),
      ),
    ));
    await t.pump();
  }

  /// Native tarafın launcher onayından sonra yaptığı `pinned(id)` çağrısı.
  Future<void> nativePinned(int id) async {
    await messenger.handlePlatformMessage(
      WidgetPinService.channelName,
      const StandardMethodCodec().encodeMethodCall(MethodCall('pinned', id)),
      (_) {},
    );
  }

  testWidgets('iOS: satır görünmez, kanal hiç çağrılmaz', (t) async {
    await pump(t, isAndroid: false);
    expect(find.text('Ana ekrana widget ekle'), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('Android, launcher desteklemiyor: satır görünmez', (t) async {
    supported = false;
    await pump(t, isAndroid: true);
    expect(calls, ['isPinSupported']);
    expect(find.text('Ana ekrana widget ekle'), findsNothing);
  });

  testWidgets('Android, destekleniyor: satır görünür; basınca requestPin, '
      'eklenince onay mesajı', (t) async {
    await pump(t, isAndroid: true);
    expect(find.text('Ana ekrana widget ekle'), findsOneWidget);
    expect(find.text('Sonraki beslenme saatini ana ekranda gör'), findsOneWidget);

    await t.tap(find.text('Ana ekrana widget ekle'));
    await t.pump();
    expect(calls, ['isPinSupported', 'requestPin']);
    expect(find.text('Widget ana ekrana eklendi'), findsNothing); // henüz onay yok

    await nativePinned(42);
    await t.pump();
    expect(find.text('Widget ana ekrana eklendi'), findsOneWidget);
    await t.pump(const Duration(seconds: 5)); // toast zamanlayıcısı
  });

  testWidgets('requestPin reddedilirse hata mesajı', (t) async {
    requestResult = false;
    await pump(t, isAndroid: true);
    await t.tap(find.text('Ana ekrana widget ekle'));
    await t.pump();
    expect(find.text('Widget eklenemedi'), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
  });

  group('WidgetPinService', () {
    test('iOS: kanal çağrılmadan false', () async {
      final s = WidgetPinService(isAndroid: false, channel: channel);
      expect(await s.isSupported(), isFalse);
      expect(await s.requestPin(), isFalse);
      expect(calls, isEmpty);
    });

    test('Android: kanal hatası false döner (çökmez)', () async {
      messenger.setMockMethodCallHandler(
          channel, (call) async => throw PlatformException(code: 'x'));
      final s = WidgetPinService(isAndroid: true, channel: channel);
      expect(await s.isSupported(), isFalse);
      expect(await s.requestPin(), isFalse);
    });
  });
}
