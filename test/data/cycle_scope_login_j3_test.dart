import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/guest_migration.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_prefs.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/models/user.dart';

class _FakeAuth extends AuthController {
  @override
  Future<User?> build() async => null;
  void setUser(User? u) => state = AsyncData(u);
}

/// INCELEME-2 J3 — adet provider'ları hesap kapsamını statik
/// `LocalSession.activeAccountId`'den alıyordu; login'de `activeAccountIdProvider`
/// state ile ÖNCE değişir, statik `_postLogin`'de (prefs yazımından) SONRA set
/// edilir → stream eski kapsama (null/misafir) bağlanıp bir daha kurulmazdı:
/// giriş sonrası adet sekmesi varsayılan ayar/sihirbaz gösteriyordu. Artık
/// provider'lar kapsamı AÇIKÇA geçirir (BabyController deseni).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
    SharedPreferences.setMockInitialValues({});
    LocalPrefs.resetForTests();
    LocalSession.resetForTests();
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      authControllerProvider.overrideWith(_FakeAuth.new),
      loggedInProvider.overrideWithValue(false),
      isPremiumProvider.overrideWithValue(false),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

  test('çıkış → giriş: provider u1 iken statik kapsam gecikmeli set edilir → '
      'stream u1 ayarını gösterir', () async {
    LocalSession.setActiveAccount(null);
    final c = container();
    final sub = c.listen(cycleSettingsProvider, (_, _) {});
    addTearDown(sub.close);
    final subE = c.listen(cycleEntriesProvider, (_, _) {});
    addTearDown(subE.close);
    await c.read(authControllerProvider.future);
    await settle();

    // login(): state = AsyncData(user) → _postLogin: exit() (prefs) → setActiveAccount
    (c.read(authControllerProvider.notifier) as _FakeAuth)
        .setUser(const User(id: 'u1', email: 'a@b.c', name: 'A'));
    await settle(); // prefs gecikmesi: statik hâlâ null
    LocalSession.setActiveAccount('u1');
    await db.into(db.cycleSettingsTable).insert(CycleSettingsTableCompanion.insert(
        id: const Value('u1'), breastfeeding: const Value('mixed')));
    await db.into(db.cycleEntries).insert(CycleEntriesCompanion.insert(
        id: 'e1', accountId: const Value('u1'), date: DateTime(2026, 9, 1)));
    await settle();

    expect(c.read(cycleSettingsProvider).asData?.value.breastfeeding?.name, 'mixed',
        reason: 'u1 satırı görünmeli (stream yanlış kapsama bağlı kalmamalı)');
    expect(c.read(cycleEntriesProvider).asData?.value.map((e) => e.id), ['e1']);
  });

  test('misafir → hesap "Aktar": kurulmuş misafir ayarı taşındıktan sonra sihirbaz AÇILMAZ',
      () async {
    await LocalSession.enterGuest();
    final guestId = LocalSession.userId;
    expect(guestId, isNotEmpty);
    await db.into(db.cycleSettingsTable).insert(CycleSettingsTableCompanion.insert(
        id: Value(guestId), breastfeeding: const Value('mixed')));
    final c = container();
    final sub = c.listen(cycleSettingsProvider, (_, _) {});
    addTearDown(sub.close);
    await c.read(authControllerProvider.future);
    await settle();
    expect(c.read(activeAccountIdProvider), guestId);
    expect(c.read(cycleSettingsProvider).asData?.value.breastfeeding?.name, 'mixed');

    // Giriş: provider u1'e geçer; statik önce misafirde kalır, sonra u1 olur.
    (c.read(authControllerProvider.notifier) as _FakeAuth)
        .setUser(const User(id: 'u1', email: 'a@b.c', name: 'A'));
    await settle();
    await LocalSession.exitGuest();
    LocalSession.setActiveAccount('u1');
    // "Aktar" → misafir satırı u1'e taşınır, misafir satırı silinir.
    await GuestMigration.migrateData(db, guestId, 'u1');
    await settle();

    expect(c.read(cycleSettingsProvider).asData?.value.breastfeeding?.name, 'mixed',
        reason: 'taşınan ayar görünmeli; "kurulmamış" sanılıp sihirbaz açılmamalı');
  });
}
