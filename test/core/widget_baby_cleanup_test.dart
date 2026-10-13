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
import 'package:adena_baby/data/feed_reminder_cache.dart';
import 'package:adena_baby/models/quiet_hours.dart';
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

  // ── A3 / I3: her widget kendi bebeğinin BEBEK-BAŞI anahtarlarını okur; ──
  // ön plan tüm bebekler için, arka plan (FCM, uygulama kapalı) o bebek için yazar.
  test('publishAll tüm doğmuş bebeklerin bebek-başı anahtarlarını yazar', () async {
    await WidgetService.publishAll([
      WidgetBaby(id: 'a', name: 'Ada', nextFeed: DateTime(2026, 1, 1, 10), lastFeed: DateTime(2026, 1, 1, 7)),
      WidgetBaby(id: 'b', name: 'Bora', nextFeed: DateTime(2026, 1, 1, 11), lastFeed: DateTime(2026, 1, 1, 8)),
    ], 'a');
    for (final id in ['a', 'b']) {
      expect(store['name_$id'], isNotNull);
      expect(int.parse(store['next_$id'] as String), greaterThan(0));
      expect(int.parse(store['last_$id'] as String), greaterThan(0));
    }
    expect(listedIds(), ['a', 'b']);
  });

  test('uygulama kapalıyken iki ayrı bebeğe gelen kayıt her birinin kendi anahtarına yazılır',
      () async {
    const snap = FeedReminderSnapshot(
        slot: 0, enabled: false, intervalMin: 180, baseType: 'all',
        preMin: 0, sound: false, quiet: QuietHours());
    await FeedReminderCache().save('a', snap);
    await FeedReminderCache().save('b', snap);
    appInForeground = true; // bildirim gösterme dalını atla (widget yazımı koşulsuz)
    addTearDown(() => appInForeground = false);

    final tsA = DateTime.now().subtract(const Duration(minutes: 30)).toUtc();
    final tsB = DateTime.now().subtract(const Duration(minutes: 90)).toUtc();
    for (final (id, ts) in [('a', tsA), ('b', tsB)]) {
      await handlePushMessage(RemoteMessage(data: {
        'type': 'family_activity', 'baby_id': id, 'baby_name': id == 'a' ? 'Ada' : 'Bora',
        'last_feed_ts': ts.toIso8601String(), 'feed_sub': 'formula',
        'widget_update': 'feed', 'body': '',
      }));
    }
    expect(store['last_a'], '${tsA.millisecondsSinceEpoch}');
    expect(store['last_b'], '${tsB.millisecondsSinceEpoch}');
    // Ön planla aynı kural: hatırlatıcı kapalıysa tahmin varsayılan aralığa düşer.
    final interval = Duration(minutes: snap.toConfig().effectiveForEstimate.intervalMin);
    expect(store['next_a'], '${tsA.add(interval).millisecondsSinceEpoch}');
    expect(store['next_b'], '${tsB.add(interval).millisecondsSinceEpoch}');
    expect(store['name_b'], 'Bora');
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
