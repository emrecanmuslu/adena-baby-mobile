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

/// SyncService is a concrete class wiring connectivity + a polling timer in its
/// constructor (native plugins). We never want those in unit tests, so we mock
/// the whole service and assert RecordActions delegates syncAll() to it.
class MockSyncService extends Mock implements SyncService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Record(
      id: 'f',
      baby: 'f',
      type: RecordType.feed,
      ts: DateTime(2026),
    ));
  });

  late MockRecordRepository repo;
  late MockBabyRepository babyRepo;
  late MockSyncService sync;

  setUp(() {
    repo = MockRecordRepository();
    babyRepo = MockBabyRepository();
    sync = MockSyncService();

    when(() => repo.upsertLocal(any())).thenAnswer((_) async {});
    when(() => repo.softDeleteLocal(any())).thenAnswer((_) async {});
    when(() => repo.presentTypes(any())).thenAnswer((_) async => <RecordType>{});
    // _suppressAd reads the ongoing-counter streams; keep them empty.
    when(() => repo.watchOngoingSleep(any()))
        .thenAnswer((_) => Stream<Record?>.value(null));
    when(() => repo.watchOngoingBreast(any()))
        .thenAnswer((_) => Stream<Record?>.value(null));
    // quietHoursProvider reads family settings.
    when(() => babyRepo.familySettings(any()))
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => sync.syncAll(sharedOnly: any(named: 'sharedOnly')))
        .thenAnswer((_) async {});
  });

  ProviderContainer makeContainer({bool premium = true}) {
    final c = ProviderContainer(overrides: [
      recordRepositoryProvider.overrideWithValue(repo),
      babyRepositoryProvider.overrideWithValue(babyRepo),
      syncServiceProvider.overrideWithValue(sync),
      // premium → AdService.onRecordSaved is a no-op (keeps native ad code out).
      isPremiumProvider.overrideWithValue(premium),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  RecordActions actions(ProviderContainer c) => c.read(recordActionsProvider);

  group('upsert', () {
    test('writes locally then triggers syncAll', () async {
      final c = makeContainer();
      final rec = Record(
        id: 'r1',
        baby: 'b1',
        type: RecordType.growth,
        ts: DateTime(2026, 6, 1),
        data: const {'weight': 5.2},
      );

      await actions(c).upsert(rec);
      await Future<void>.delayed(Duration.zero);

      final captured =
          verify(() => repo.upsertLocal(captureAny())).captured.single as Record;
      expect(captured.id, 'r1');
      expect(captured.data['weight'], 5.2);
      verify(() => sync.syncAll()).called(1);
    });
  });

  group('addDiaper', () {
    test('creates a diaper record with sub + delegates to repo', () async {
      final c = makeContainer();

      await actions(c).addDiaper('b1', 'wet');
      await Future<void>.delayed(Duration.zero);

      final r =
          verify(() => repo.upsertLocal(captureAny())).captured.single as Record;
      expect(r.baby, 'b1');
      expect(r.type, RecordType.diaper);
      expect(r.data['sub'], 'wet');
      expect(r.id, isNotEmpty);
      verify(() => sync.syncAll()).called(1);
    });
  });

  group('addFeed', () {
    test('creates a feed record carrying the data map', () async {
      final c = makeContainer();

      await actions(c).addFeed('b1', {'sub': 'formula', 'amount': 120});
      await Future<void>.delayed(Duration.zero);

      final r =
          verify(() => repo.upsertLocal(captureAny())).captured.single as Record;
      expect(r.type, RecordType.feed);
      expect(r.data['sub'], 'formula');
      expect(r.data['amount'], 120);
    });
  });

  group('startSleep / stopSleep', () {
    test('startSleep creates an ongoing sleep (end_ts null)', () async {
      final c = makeContainer();

      await actions(c).startSleep('b1');
      await Future<void>.delayed(Duration.zero);

      final r =
          verify(() => repo.upsertLocal(captureAny())).captured.single as Record;
      expect(r.type, RecordType.sleep);
      expect(r.data['end_ts'], isNull);
      expect(r.data['start_ts'], isNotNull);
      expect(r.isOngoingSleep, isTrue);
    });

    test('stopSleep sets end_ts + duration on the existing record', () async {
      final c = makeContainer();
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      final sleep = Record(
        id: 's1',
        baby: 'b1',
        type: RecordType.sleep,
        ts: start,
        data: {'start_ts': start.toUtc().toIso8601String(), 'end_ts': null},
      );

      await actions(c).stopSleep(sleep);
      await Future<void>.delayed(Duration.zero);

      final r =
          verify(() => repo.upsertLocal(captureAny())).captured.single as Record;
      expect(r.id, 's1');
      expect(r.data['end_ts'], isNotNull);
      expect(r.data['duration'], greaterThanOrEqualTo(29));
    });
  });

  group('breast counter', () {
    test('startBreast creates an ongoing breast feed', () async {
      final c = makeContainer();

      await actions(c).startBreast('b1', 'left');
      await Future<void>.delayed(Duration.zero);

      final r =
          verify(() => repo.upsertLocal(captureAny())).captured.single as Record;
      expect(r.type, RecordType.feed);
      expect(r.data['sub'], 'breast');
      expect(r.data['side'], 'left');
      expect(r.data['end_ts'], isNull);
      expect(r.isOngoingBreast, isTrue);
    });

    test('stopBreast finalizes minutes and end_ts', () async {
      final c = makeContainer();
      final start = DateTime.now().subtract(const Duration(minutes: 10));
      final breast = Record(
        id: 'br1',
        baby: 'b1',
        type: RecordType.feed,
        ts: start,
        data: {
          'sub': 'breast',
          'start_ts': start.toUtc().toIso8601String(),
          'seg_start_ts': start.toUtc().toIso8601String(),
          'side': 'left',
          'left_ms': 0,
          'right_ms': 0,
          'end_ts': null,
        },
      );

      await actions(c).stopBreast(breast);
      await Future<void>.delayed(Duration.zero);

      final r =
          verify(() => repo.upsertLocal(captureAny())).captured.single as Record;
      expect(r.data['end_ts'], isNotNull);
      expect(r.data.containsKey('left_min'), isTrue);
      expect(r.data.containsKey('paused'), isFalse);
    });

    test('switchBreastSide is a no-op when side unchanged', () async {
      final c = makeContainer();
      final breast = Record(
        id: 'br2',
        baby: 'b1',
        type: RecordType.feed,
        ts: DateTime.now(),
        data: const {'sub': 'breast', 'side': 'left', 'start_ts': 'x', 'end_ts': null},
      );

      await actions(c).switchBreastSide(breast, 'left');
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => repo.upsertLocal(any()));
    });
  });

  group('delete', () {
    test('soft-deletes locally then triggers syncAll', () async {
      final c = makeContainer();

      await actions(c).delete('r9');
      await Future<void>.delayed(Duration.zero);

      verify(() => repo.softDeleteLocal('r9')).called(1);
      verify(() => sync.syncAll()).called(1);
    });
  });
}
