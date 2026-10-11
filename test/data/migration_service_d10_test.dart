import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_prefs.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/migration_service.dart';
import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/models/baby.dart';

class _MockCycle extends Mock implements CycleRepository {}

class _NoBabies extends BabyController {
  @override
  Future<List<Baby>> build() async => const [];
}

/// D10 — `MigrationController.run()` guard'ı: `state=running` yazılmadan önceki
/// await'lerde gelen ikinci `run()` (GuestMigration + localToCloudMigration)
/// paralel ikinci bir tam yükleme başlatmasın.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paralel iki run() → göç gövdesi (markAllDirty) BİR kez', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
    SharedPreferences.setMockInitialValues({});
    LocalPrefs.resetForTests();
    LocalSession.resetForTests();
    LocalSession.setActiveAccount('u1');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cycle = _MockCycle();
    var calls = 0;
    when(() => cycle.markAllDirty()).thenAnswer((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      loggedInProvider.overrideWithValue(true),
      isPremiumProvider.overrideWithValue(true),
      activeAccountIdProvider.overrideWithValue('u1'),
      babyControllerProvider.overrideWith(_NoBabies.new),
      cycleRepositoryProvider.overrideWithValue(cycle),
    ]);
    addTearDown(c.dispose);
    final ctrl = c.read(migrationControllerProvider.notifier);

    await Future.wait([ctrl.run(), ctrl.run()]);

    expect(calls, 1, reason: 'ikinci run guard\'a takılmalı');
  });
}
