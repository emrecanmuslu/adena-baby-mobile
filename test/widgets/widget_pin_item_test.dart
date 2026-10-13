import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/core/widget_pin_service.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/features/settings/widget_pin_item.dart';
import 'package:adena_baby/models/baby.dart';

/// Ayarlar → "Ana ekrana widget ekle" (Android requestPinAppWidget, Xiaomi
/// seçici sorunu için). Native kanal `adena/widget` mock'lanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(WidgetPinService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<Object?> pinArgs;
  late bool supported;
  late bool requestResult;

  setUp(() {
    calls = [];
    pinArgs = [];
    supported = true;
    requestResult = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isPinSupported':
          return supported;
        case 'requestPin':
          pinArgs.add((call.arguments as Map?)?['babyId']);
          return requestResult;
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const ada = Baby(id: 'a', name: 'Ada');
  const bora = Baby(id: 'b', name: 'Bora');
  const gebe = Baby(id: 'p', name: 'Gebe', status: BabyStatus.expecting);

  Future<void> pump(WidgetTester t,
      {required bool isAndroid, List<Baby> babies = const [ada]}) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        widgetPinServiceProvider.overrideWithValue(
            WidgetPinService(isAndroid: isAndroid, channel: channel)),
        babyControllerProvider.overrideWith(() => _FakeBabies(babies)),
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

  // ── K1: çoklu bebekte eklemeden ÖNCE "Hangi bebek için?" ──
  testWidgets('tek (doğmuş) bebek: soru yok, istek o bebekle gider', (t) async {
    await pump(t, isAndroid: true, babies: const [ada, gebe]);
    await t.tap(find.text('Ana ekrana widget ekle'));
    await t.pump();
    expect(find.text('Hangi bebek için?'), findsNothing);
    expect(pinArgs, ['a']);
    await t.pump(const Duration(minutes: 3)); // bekleyen "eklendi" zaman aşımı
  });

  testWidgets('iki bebek: önce seçim sorulur, seçilen bebekle istek gider', (t) async {
    await pump(t, isAndroid: true, babies: const [ada, bora, gebe]);
    await t.tap(find.text('Ana ekrana widget ekle'));
    await t.pumpAndSettle();
    expect(find.text('Hangi bebek için?'), findsOneWidget);
    expect(find.text('Gebe'), findsNothing); // gebelik modundaki bebek listede yok
    expect(pinArgs, isEmpty); // seçimden önce istek yok

    await t.tap(find.text('Bora'));
    await t.pumpAndSettle();
    expect(pinArgs, ['b']);
    await t.pump(const Duration(minutes: 3)); // bekleyen "eklendi" zaman aşımı
  });

  testWidgets('seçim kapatılırsa istek gitmez', (t) async {
    await pump(t, isAndroid: true, babies: const [ada, bora]);
    await t.tap(find.text('Ana ekrana widget ekle'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10)); // sayfanın dışı → kapat
    await t.pumpAndSettle();
    expect(find.text('Hangi bebek için?'), findsNothing);
    expect(pinArgs, isEmpty);
  });

  testWidgets('iki ardışık ekleme: her istek kendi bebeğiyle gider', (t) async {
    await pump(t, isAndroid: true, babies: const [ada, bora]);
    for (final name in ['Ada', 'Bora']) {
      await t.tap(find.text('Ana ekrana widget ekle'));
      await t.pumpAndSettle();
      await t.tap(find.text(name));
      await t.pumpAndSettle();
    }
    expect(pinArgs, ['a', 'b']);
    await t.pump(const Duration(minutes: 3)); // bekleyen "eklendi" zaman aşımları
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

class _FakeBabies extends BabyController {
  _FakeBabies(this.list);
  final List<Baby> list;
  @override
  Future<List<Baby>> build() async => list;
}
