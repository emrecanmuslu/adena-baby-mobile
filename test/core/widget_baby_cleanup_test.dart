import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/push_service.dart';
import 'package:adena_baby/core/widget_service.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/features/babies/notification_sync.dart';
import 'package:adena_baby/models/baby.dart';

/// WIDGET-COKLU-BEBEK A4 (K4): listeden çıkan bebeğin widget anahtarları silinir;
/// widget "Bebek bulunamadı" gösterir, eski ad/saat ASLA kalmaz.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('home_widget');
  late Map<String, Object?> store;
  late List<String> calls;

  setUp(() {
    store = {};
    calls = [];
    WidgetService.resetForTest();
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final a = call.arguments as Map?;
      switch (call.method) {
        case 'saveWidgetData':
          final id = a!['id'] as String;
          if (a['data'] == null) {
            store.remove(id);
          } else {
            store[id] = a['data'];
          }
          return true;
        case 'getWidgetData':
          return store[a!['id']] ?? a['defaultValue'];
      }
      return true;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  List<String> listedIds() => [
        for (final m in jsonDecode(store['babies_json'] as String) as List)
          (m as Map)['id'] as String
      ];

  test('publishAll: listeden çıkan bebeğin ad/saat anahtarları silinir', () async {
    await WidgetService.publishAll(const [
      WidgetBaby(id: 'a', name: 'Ada'),
      WidgetBaby(id: 'b', name: 'Bora'),
    ], 'a');
    expect(store['name_b'], 'Bora');

    await WidgetService.publishAll(const [WidgetBaby(id: 'a', name: 'Ada')], 'a');
    expect(listedIds(), ['a']);
    expect(store.containsKey('name_b'), isFalse);
    expect(store.containsKey('next_b'), isFalse);
    expect(store.containsKey('last_b'), isFalse);
    expect(store['name_a'], 'Ada');
  });

  test('removeBaby: listeden çıkarır, anahtarları siler, aktifse aktifi değiştirir',
      () async {
    await WidgetService.publishAll(const [
      WidgetBaby(id: 'a', name: 'Ada'),
      WidgetBaby(id: 'b', name: 'Bora'),
    ], 'b');
    calls.clear();

    await WidgetService.removeBaby('b');
    expect(listedIds(), ['a']);
    expect(store.containsKey('name_b'), isFalse);
    expect(store['active_id'], 'a');
    expect(store['baby_name'], 'Ada');
    expect(calls, contains('updateWidget'));

    await WidgetService.removeBaby('a');
    expect(listedIds(), isEmpty);
    expect(store['active_id'], '');
    expect(store.containsKey('baby_name'), isFalse);
  });

  test('access_removed push: bebek widget listesinden hemen çıkar', () async {
    await WidgetService.publishAll(const [
      WidgetBaby(id: 'a', name: 'Ada'),
      WidgetBaby(id: 'b', name: 'Bora'),
    ], 'a');
    appInForeground = true; // ağır bg yeniden kurmayı atla
    addTearDown(() => appInForeground = false);

    await handlePushMessage(const RemoteMessage(
        data: {'type': 'access_removed', 'baby_id': 'b', 'body': ''}));
    expect(listedIds(), ['a']);
    expect(store.containsKey('name_b'), isFalse);
  });

  group('WidgetSync', () {
    Future<void> pumpSync(WidgetTester t, BabyController Function() ctrl) async {
      await t.pumpWidget(ProviderScope(
        overrides: [babyControllerProvider.overrideWith(ctrl)],
        child: const Directionality(
            textDirection: TextDirection.ltr, child: WidgetSync()),
      ));
      await t.pump();
      await t.pump();
    }

    testWidgets('doğmuş bebek kalmadıysa (çıkış / son bebek silindi) boş liste yayınlanır',
        (t) async {
      store['babies_json'] = jsonEncode([
        {'id': 'a', 'name': 'Ada'}
      ]);
      store['name_a'] = 'Ada';
      await t.runAsync(() async {
        await pumpSync(t, () => _FakeBabies(const [
              Baby(id: 'p', name: 'Gebe', status: BabyStatus.expecting),
            ]));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(listedIds(), isEmpty);
      expect(store.containsKey('name_a'), isFalse);
    });

    testWidgets('bebek listesi yüklenirken hiçbir şey yazılmaz', (t) async {
      store['babies_json'] = jsonEncode([
        {'id': 'a', 'name': 'Ada'}
      ]);
      await pumpSync(t, () => _LoadingBabies());
      expect(calls.where((c) => c == 'saveWidgetData'), isEmpty);
      expect(listedIds(), ['a']);
    });
  });
}

class _FakeBabies extends BabyController {
  _FakeBabies(this.list);
  final List<Baby> list;
  @override
  Future<List<Baby>> build() async => list;
}

class _LoadingBabies extends BabyController {
  @override
  Future<List<Baby>> build() => Completer<List<Baby>>().future;
}
