import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/record_repository.dart';
import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/features/records/record_controller.dart';
import 'package:adena_baby/models/record.dart';

class MockRecordRepository extends Mock implements RecordRepository {}

class MockBabyRepository extends Mock implements BabyRepository {}

class MockSyncService extends Mock implements SyncService {}

/// O27 (uyku negatif süre), O28 (duraklatılmış emzirmede hayalet dakika),
/// O13 (gün değişince "Bugün" özeti).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Record(
        id: 'x', baby: 'b', type: RecordType.feed, ts: DateTime(2026), data: const {}));
  });

  late MockRecordRepository repo;
  late MockBabyRepository babyRepo;
  late MockSyncService sync;
  final saved = <Record>[];

  setUp(() {
    repo = MockRecordRepository();
    babyRepo = MockBabyRepository();
    sync = MockSyncService();
    saved.clear();
    when(() => repo.upsertLocal(any())).thenAnswer((inv) async {
      saved.add(inv.positionalArguments.first as Record);
    });
    when(() => repo.presentTypes(any())).thenAnswer((_) async => <RecordType>{});
    when(() => repo.watchOngoingSleep(any()))
        .thenAnswer((_) => Stream<Record?>.value(null));
    when(() => repo.watchOngoingBreast(any()))
        .thenAnswer((_) => Stream<Record?>.value(null));
    when(() => babyRepo.familySettings(any()))
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => sync.syncAll(sharedOnly: any(named: 'sharedOnly')))
        .thenAnswer((_) async {});
  });

  ProviderContainer container({StreamController<DateTime>? dayCtrl}) {
    final c = ProviderContainer(overrides: [
      recordRepositoryProvider.overrideWithValue(repo),
      babyRepositoryProvider.overrideWithValue(babyRepo),
      syncServiceProvider.overrideWithValue(sync),
      isPremiumProvider.overrideWithValue(true),
      if (dayCtrl != null)
        currentDayProvider.overrideWith((ref) => dayCtrl.stream),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('O27 — uyku bitiş < başlangıç', () {
    test('stopSleepWithTimes: bitiş başlangıca çekilir, süre 0 (negatif yok)', () async {
      final c = container();
      final r = Record(
          id: 's1',
          baby: 'b1',
          type: RecordType.sleep,
          ts: DateTime(2026, 6, 1, 22),
          data: {'start_ts': DateTime(2026, 6, 1, 22).toUtc().toIso8601String()});
      await c.read(recordActionsProvider).stopSleepWithTimes(
          r, DateTime(2026, 6, 1, 22), DateTime(2026, 6, 1, 21, 30));
      expect(saved.single.data['duration'], 0);
      expect(DateTime.parse(saved.single.data['end_ts'] as String).toLocal(),
          DateTime(2026, 6, 1, 22));
    });

    test('stopSleep: başlangıç gelecekteyse (saat sapması) süre 0', () async {
      final c = container();
      final future = DateTime.now().add(const Duration(hours: 2));
      final r = Record(
          id: 's2',
          baby: 'b1',
          type: RecordType.sleep,
          ts: future,
          data: {'start_ts': future.toUtc().toIso8601String()});
      await c.read(recordActionsProvider).stopSleep(r);
      expect(saved.single.data['duration'], 0);
    });
  });

  group('O28 — duraklatılmış emzirmede meme değiştirip kaydetme', () {
    test('duraklatma süresi eklenmez: kaydedilen dakika = duraklamadan önce biriken',
        () async {
      final c = container();
      final actions = c.read(recordActionsProvider);
      final startedAgo = DateTime.now().subtract(const Duration(minutes: 5));
      final running = Record(
          id: 'br1',
          baby: 'b1',
          type: RecordType.feed,
          ts: startedAgo,
          data: {
            'sub': 'breast',
            'start_ts': startedAgo.toUtc().toIso8601String(),
            'side': 'left',
            'seg_start_ts': startedAgo.toUtc().toIso8601String(),
            'left_ms': 0,
            'right_ms': 0,
          });
      await actions.pauseBreast(running); // 5 dk sola yazıldı, seg null
      final paused = saved.last;
      expect(paused.data['paused'], isTrue);
      expect(paused.data['seg_start_ts'], isNull);

      // Duraklatılmışken sağa geç (Devam et'e basılmadı).
      await actions.switchBreastSide(paused, 'right');
      final switched = saved.last;
      expect(switched.data['seg_start_ts'], isNull,
          reason: 'duraklatılmışken segment yeniden başlamamalı');
      expect(switched.data['paused'], isTrue);

      // Sunucu/cihaz zamanı ilerledi gibi: hemen kaydet.
      await actions.stopBreast(switched);
      final done = saved.last;
      final total = (done.data['left_min'] as num) + (done.data['right_min'] as num);
      expect(total, 5, reason: 'duraklama süresi hayalet dakika olarak eklenmez');
    });
  });

  group('O13 — "Bugün" gün değişince yenilenir', () {
    test('currentDayProvider ilerleyince todayRecordsProvider yeni günle yeniden sorgular',
        () async {
      final dayCtrl = StreamController<DateTime>.broadcast();
      addTearDown(dayCtrl.close);
      final asked = <DateTime>[];
      when(() => repo.watchSince(any(), any())).thenAnswer((inv) {
        asked.add(inv.positionalArguments[1] as DateTime);
        return Stream<List<Record>>.value(const []);
      });
      final c = container(dayCtrl: dayCtrl);
      c.listen(todayRecordsProvider('b1'), (_, _) {});
      c.listen(currentDayProvider, (_, _) {});
      dayCtrl.add(DateTime(2026, 6, 1));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(asked.last, DateTime(2026, 6, 1));

      dayCtrl.add(DateTime(2026, 6, 2)); // gece yarısı geçti
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(asked.last, DateTime(2026, 6, 2),
          reason: 'dünkü kayıtlar artık "Bugün"de sayılmamalı');
    });
  });

  group('D23 — süren kayıt varken başlatma', () {
    test('startSleep: süren uyku varsa ikinci kayıt oluşturulmaz', () async {
      final running = Record(
          id: 'sl', baby: 'b1', type: RecordType.sleep, ts: DateTime(2026, 6, 1),
          data: const {'start_ts': '2026-06-01T10:00:00Z', 'end_ts': null});
      when(() => repo.watchOngoingSleep('b1'))
          .thenAnswer((_) => Stream<Record?>.value(running));
      final c = container();
      await c.read(recordActionsProvider).startSleep('b1');
      expect(saved, isEmpty, reason: 'çift dokunuşta iki süren uyku olmasın');
    });

    test('startBreast: süren emzirme varsa ikinci kayıt oluşturulmaz', () async {
      final running = Record(
          id: 'br', baby: 'b1', type: RecordType.feed, ts: DateTime(2026, 6, 1),
          data: const {'sub': 'breast', 'end_ts': null, 'side': 'left'});
      when(() => repo.watchOngoingBreast('b1'))
          .thenAnswer((_) => Stream<Record?>.value(running));
      final c = container();
      await c.read(recordActionsProvider).startBreast('b1', 'right');
      expect(saved, isEmpty);
    });
  });
}
