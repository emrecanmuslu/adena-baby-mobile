import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/features/cycle/cycle_loss.dart';
import 'package:adena_baby/models/cycle.dart';

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => null;
  @override
  Future<String?> get refreshToken async => null;
  @override
  Future<bool> get hasSession async => false;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

/// O23 — gebelik modundan "Adet takibine dön": bekleyen bebek yetim kalmaz
/// (kaldırılır), ayardaki `baby` bağı kopar, mod tracking; çapa korunur (KB-5).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const acct = 'acct-o23';

  late ApiClient api;
  late AppDatabase db;
  late CycleRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = ApiClient(_FakeTokens());
    db = AppDatabase(NativeDatabase.memory());
    repo = CycleRepository(db, api, () => false);
    LocalSession.setActiveAccount(acct);
    await db.into(db.babies).insert(BabiesCompanion.insert(
        id: 'preg-1',
        name: 'Bebek',
        accountId: const Value(acct),
        status: const Value('expecting'),
        dueDate: Value(DateTime(2027, 3, 1))));
    await repo.patchSettings({
      'lifecycle_mode': 'pregnant',
      'baby': 'preg-1',
      'first_period_date': '2026-05-01',
    });
  });

  tearDown(() async {
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  Future<void> withRef(
      WidgetTester tester, Future<void> Function(WidgetRef ref) body) async {
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
        cloudSyncEnabledProvider.overrideWithValue(false),
        activeAccountIdProvider.overrideWithValue(acct),
        loggedInProvider.overrideWithValue(false),
      ],
      child: Consumer(builder: (_, ref, child) {
        captured = ref;
        return const SizedBox.shrink();
      }),
    ));
    await tester.runAsync(() async {
      await body(captured);
      // Drift stream'leri fake-async dışında kapansın (bekleyen timer kalmasın).
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  }

  testWidgets('bekleyen bebek kaldırılır, baby=null, mod tracking, çapa sıfırlanır (KB-5 b)',
      (tester) async {
    await withRef(tester, (ref) async {
      final babies = await ref.read(babyControllerProvider.future);
      expect(babies.map((b) => b.id), ['preg-1']);
      final settings = await ref.read(cycleRepositoryProvider).getSettings();
      expect(settings.lifecycleMode, CycleLifecycleMode.pregnant);

      await returnToTrackingFromPregnancy(ref, settings);

      final row = await (db.select(db.babies)..where((b) => b.id.equals('preg-1')))
          .getSingle();
      expect(row.isDeleted, isTrue, reason: 'yetim expecting bebek kalmaz');
      final after = await ref.read(cycleRepositoryProvider).getSettings();
      expect(after.lifecycleMode, CycleLifecycleMode.tracking);
      expect(after.babyId, isNull);
      expect(after.predictionsHidden, isFalse);
      expect(after.firstPeriodDate, isNull, reason: 'KB-5 (b): çapa sıfırlanır, bekleme moduna dönülür');
    });
  });
}
