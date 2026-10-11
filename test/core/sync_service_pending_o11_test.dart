import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/features/records/record_controller.dart';
import 'package:adena_baby/models/baby.dart';

class _MockCycle extends Mock implements CycleRepository {}

class _NoBabies extends BabyController {
  @override
  Future<List<Baby>> build() async => const [];
}

/// O11 — tur sürerken gelen `syncAll` çağrısı, kuyruğa alınan TAKİP turu
/// bitene kadar beklesin ("Kaydet → sunucu onayını bekle" sözü tutulsun).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ikinci syncAll takip turu bitince döner; takip turu gerçekten koşar', () async {
    final cycle = _MockCycle();
    final gate = Completer<void>();
    var cycleCalls = 0;
    when(() => cycle.syncIfCloud()).thenAnswer((_) async {
      cycleCalls++;
      if (cycleCalls == 1) await gate.future; // ilk tur askıda
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      loggedInProvider.overrideWithValue(true),
      babyControllerProvider.overrideWith(_NoBabies.new),
      cycleRepositoryProvider.overrideWithValue(cycle),
    ]);
    addTearDown(c.dispose);
    await c.read(babyControllerProvider.future);
    final svc = c.read(syncServiceProvider);

    final first = svc.syncAll();
    await Future<void>.delayed(Duration.zero);
    expect(cycleCalls, 1);

    var secondDone = false;
    final second = svc.syncAll().then((_) => secondDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(secondDone, isFalse, reason: 'kuyruktaki çağrı hemen dönmemeli');

    gate.complete();
    await first;
    await second;
    expect(secondDone, isTrue);
    expect(cycleCalls, 2, reason: 'takip turu koştu');
  });
}
