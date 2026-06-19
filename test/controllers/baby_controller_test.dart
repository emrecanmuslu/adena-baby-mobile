import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/models/baby.dart';

class MockBabyRepository extends Mock implements BabyRepository {}

Baby _baby({String id = 'b1', String name = 'Bebek'}) =>
    Baby(id: id, name: name, status: BabyStatus.born, myRole: 'owner');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_baby());
  });

  late MockBabyRepository repo;
  late StreamController<List<Baby>> watchCtrl;

  setUp(() {
    repo = MockBabyRepository();
    watchCtrl = StreamController<List<Baby>>.broadcast();
    when(() => repo.watchAll()).thenAnswer((_) => watchCtrl.stream);
    when(() => repo.getAll()).thenAnswer((_) async => const <Baby>[]);
    when(() => repo.pushDirty()).thenAnswer((_) async {});
    when(() => repo.pullFromServer()).thenAnswer((_) async => const <Baby>[]);
    // Active account must be set so the controller is scoped to a session.
    LocalSession.setActiveAccount('acct1');
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await watchCtrl.close();
  });

  /// Pull artık OTURUMA bağlı (premium şart değil — Seçenek 2: paylaşılan bebek
  /// profili sahibin bulutundan gelir). pushDirty (kendi bebeğimi yükleme) ise
  /// kendi premium'uma (cloudSync) bağlı. Premium daima oturum açık demektir →
  /// loggedIn verilmezse cloudSync'i izler.
  ProviderContainer makeContainer({bool cloudSync = false, bool? loggedIn}) {
    final c = ProviderContainer(overrides: [
      babyRepositoryProvider.overrideWithValue(repo),
      loggedInProvider.overrideWithValue(loggedIn ?? cloudSync),
      cloudSyncEnabledProvider.overrideWithValue(cloudSync),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('build (initial state)', () {
    test('resolves to repo.getAll() result', () async {
      when(() => repo.getAll())
          .thenAnswer((_) async => [_baby(id: 'x'), _baby(id: 'y')]);

      final c = makeContainer();
      final list = await c.read(babyControllerProvider.future);

      expect(list.map((b) => b.id), ['x', 'y']);
      verify(() => repo.getAll()).called(1);
    });

    test('cloudSync OFF → does not pull from server', () async {
      final c = makeContainer(cloudSync: false);
      await c.read(babyControllerProvider.future);
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => repo.pullFromServer());
    });

    test('cloudSync ON → pulls (reconcile) in background', () async {
      final c = makeContainer(cloudSync: true);
      await c.read(babyControllerProvider.future);
      await Future<void>.delayed(Duration.zero);

      verify(() => repo.pushDirty()).called(greaterThanOrEqualTo(1));
      verify(() => repo.pullFromServer()).called(1);
    });

    test('logged in + free → pulls (paylaşılan bebek tazelemesi) ama pushDirty YOK',
        () async {
      // Seçenek 2: free üye de oturum açıksa sunucudan çeker (paylaşılan bebeğin
      // gebelik→doğdu/üyelik değişikliği gelsin) — ama kendi verisini yüklemez.
      final c = makeContainer(loggedIn: true, cloudSync: false);
      await c.read(babyControllerProvider.future);
      await Future<void>.delayed(Duration.zero);

      verify(() => repo.pullFromServer()).called(1);
      verifyNever(() => repo.pushDirty());
    });

    test('local watch stream updates state', () async {
      final c = makeContainer();
      await c.read(babyControllerProvider.future);

      // Keep the provider alive so the listen() subscription is active.
      final sub = c.listen(babyControllerProvider, (_, _) {});
      addTearDown(sub.close);

      watchCtrl.add([_baby(id: 'streamed')]);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(babyControllerProvider).value!.single.id, 'streamed');
    });
  });

  group('create', () {
    test('delegates to repo.create with a client-generated baby', () async {
      final created = _baby(id: 'created');
      when(() => repo.create(any())).thenAnswer((_) async => created);

      final c = makeContainer();
      await c.read(babyControllerProvider.future);
      final ctrl = c.read(babyControllerProvider.notifier);

      final out = await ctrl.create(name: 'Yeni', status: BabyStatus.born);

      expect(out.id, 'created');
      final captured = verify(() => repo.create(captureAny())).captured.single
          as Baby;
      expect(captured.name, 'Yeni');
      expect(captured.status, BabyStatus.born);
      expect(captured.myRole, 'owner');
      expect(captured.id, isNotEmpty); // UUID generated client-side
    });

    test('cloudSync OFF → no pushDirty after create', () async {
      when(() => repo.create(any())).thenAnswer((_) async => _baby());

      final c = makeContainer(cloudSync: false);
      await c.read(babyControllerProvider.future);
      await ctrlOf(c).create(name: 'N', status: BabyStatus.born);
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => repo.pushDirty());
    });

    test('cloudSync ON → pushDirty after create', () async {
      when(() => repo.create(any())).thenAnswer((_) async => _baby());

      final c = makeContainer(cloudSync: true);
      await c.read(babyControllerProvider.future);
      // Drain the build()-time pull so we only assert the create push.
      await Future<void>.delayed(Duration.zero);
      clearInteractions(repo);
      when(() => repo.create(any())).thenAnswer((_) async => _baby());

      await ctrlOf(c).create(name: 'N', status: BabyStatus.born);
      await Future<void>.delayed(Duration.zero);

      verify(() => repo.pushDirty()).called(1);
    });
  });

  group('updateBaby', () {
    test('delegates field map to repo.update and returns result', () async {
      final updated = _baby(id: 'b1', name: 'Güncel');
      when(() => repo.update('b1', any())).thenAnswer((_) async => updated);

      final c = makeContainer();
      await c.read(babyControllerProvider.future);

      final out = await ctrlOf(c).updateBaby('b1', {'name': 'Güncel'});

      expect(out.name, 'Güncel');
      verify(() => repo.update('b1', {'name': 'Güncel'})).called(1);
    });
  });

  group('deleteBaby', () {
    test('delegates to repo.delete', () async {
      when(() => repo.delete('b1')).thenAnswer((_) async {});

      final c = makeContainer();
      await c.read(babyControllerProvider.future);

      await ctrlOf(c).deleteBaby('b1');

      verify(() => repo.delete('b1')).called(1);
    });
  });

  group('refresh', () {
    test('cloudSync ON → pushDirty + pullFromServer', () async {
      final c = makeContainer(cloudSync: true);
      await c.read(babyControllerProvider.future);
      await Future<void>.delayed(Duration.zero);
      clearInteractions(repo);
      when(() => repo.pushDirty()).thenAnswer((_) async {});
      when(() => repo.pullFromServer()).thenAnswer((_) async => const []);

      await ctrlOf(c).refresh();

      verify(() => repo.pushDirty()).called(1);
      verify(() => repo.pullFromServer()).called(1);
    });

    test('cloudSync OFF → no-op (no network)', () async {
      final c = makeContainer(cloudSync: false);
      await c.read(babyControllerProvider.future);
      await Future<void>.delayed(Duration.zero);
      clearInteractions(repo);

      await ctrlOf(c).refresh();

      verifyNever(() => repo.pullFromServer());
    });
  });

  group('activeBabyIdProvider / activeBabyProvider', () {
    test('falls back to first baby when no id selected', () async {
      when(() => repo.getAll())
          .thenAnswer((_) async => [_baby(id: 'first'), _baby(id: 'second')]);

      final c = makeContainer();
      await c.read(babyControllerProvider.future);
      final sub = c.listen(babyControllerProvider, (_, _) {});
      addTearDown(sub.close);

      expect(c.read(activeBabyProvider)!.id, 'first');
    });

    test('selecting an id makes that the active baby', () async {
      when(() => repo.getAll())
          .thenAnswer((_) async => [_baby(id: 'first'), _baby(id: 'second')]);

      final c = makeContainer();
      await c.read(babyControllerProvider.future);
      final sub = c.listen(babyControllerProvider, (_, _) {});
      addTearDown(sub.close);

      c.read(activeBabyIdProvider.notifier).set('second');
      expect(c.read(activeBabyProvider)!.id, 'second');
    });

    test('null when there are no babies', () async {
      final c = makeContainer();
      await c.read(babyControllerProvider.future);
      expect(c.read(activeBabyProvider), isNull);
    });
  });
}

BabyController ctrlOf(ProviderContainer c) =>
    c.read(babyControllerProvider.notifier);
