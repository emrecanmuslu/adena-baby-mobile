import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/background_sync.dart';
import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/core/providers.dart';
import 'package:adena_baby/data/baby_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/record_repository.dart';
import 'package:adena_baby/data/subscription_repository.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/babies/baby_controller.dart';
import 'package:adena_baby/models/baby.dart';
import 'package:adena_baby/models/record.dart';
import 'package:adena_baby/models/user.dart';

/// O36 (BULGULAR.md): arka plan turu BabyController._pull'u unawaited
/// başlatıyor, container.dispose() bu iş bitmeden geliyordu; zaman aşımı
/// damgası yoktu. Artık tur gövdesi (runBackgroundSyncWith) bebek listesini
/// yerel repo'dan okur, dispose her durumda EN SONDA, damga
/// 'bitti' | 'hata' | 'zaman aşımı'.
class MockBabyRepository extends Mock implements BabyRepository {}

class _CancelSpy implements FlutterLocalNotificationsPlugin {
  final cancelled = <int>[];
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;
  @override
  T? resolvePlatformSpecificImplementation<T extends FlutterLocalNotificationsPlatform>() => null;
  @override
  Future<void> cancel({required int id, String? tag}) async => cancelled.add(id);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class MockRecordRepository extends Mock implements RecordRepository {}

class _StubAuth extends AuthController {
  @override
  Future<User?> build() async {
    LocalSession.setActiveAccount('u1');
    return const User(id: 'u1', email: 'a@b.com', name: 'A');
  }
}

Baby _baby(String id, {int members = 2, BabyStatus status = BabyStatus.born}) =>
    Baby(id: id, name: 'B$id', status: status, memberCount: members, myRole: 'parent');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MockBabyRepository babies;
  late MockRecordRepository records;
  late bool disposed;

  /// Dispose sırasını gözlemek için container'a bir "sonda" provider'ı.
  final probe = Provider<int>((ref) {
    ref.onDispose(() => disposed = true);
    return 0;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({}); // FeedReminderCache → snapshot yok
    db = AppDatabase(NativeDatabase.memory());
    babies = MockBabyRepository();
    records = MockRecordRepository();
    disposed = false;
    when(() => babies.getAll(accountId: any(named: 'accountId')))
        .thenAnswer((_) async => [_baby('shared'), _baby('solo', members: 1)]);
    when(() => records.watchRecent(any()))
        .thenAnswer((_) => Stream.value(const <Record>[]));
    // İlaç v2 adımı bu dosyanın genel testlerinde etkisiz (ağ/eklenti yok);
    // kendi grubu aşağıda gerçek davranışı doğrular.
    bgMedHook = BgMedHook(syncPlans: (_, _) async {}, rebuild: (_, _) async {});
  });

  tearDown(() async {
    bgMedHook = null;
    LocalSession.setActiveAccount(null);
    await db.close();
  });

  ProviderContainer make() {
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      authControllerProvider.overrideWith(_StubAuth.new),
      babyRepositoryProvider.overrideWithValue(babies),
      recordRepositoryProvider.overrideWithValue(records),
      runningInBackgroundProvider.overrideWithValue(true),
    ]);
    c.read(probe);
    return c;
  }

  Future<void> tick([int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('sync bitmeden container dispose edilmez; bitince "bitti" ve dispose', () async {
    final gate = Completer<void>();
    when(() => records.sync('shared')).thenAnswer((_) => gate.future);
    final c = make();

    final run = runBackgroundSyncWith(c, timeout: const Duration(seconds: 5));
    await tick();
    expect(disposed, isFalse, reason: 'iş sürerken dispose olmamalı');

    gate.complete();
    expect(await run, bgOutcomeDone);
    expect(disposed, isTrue);
    verify(() => records.sync('shared')).called(1);
    verifyNever(() => records.sync('solo')); // periyodik tur: yalnız paylaşımlı
  });

  test('zaman aşımı: damga "zaman aşımı", dispose yine en sonda', () async {
    final never = Completer<void>();
    when(() => records.sync('shared')).thenAnswer((_) => never.future);
    final c = make();

    final outcome =
        await runBackgroundSyncWith(c, timeout: const Duration(milliseconds: 50));
    expect(outcome, bgOutcomeTimeout);
    expect(disposed, isTrue);
  });

  test('403 (erişim kalkmış): çökme yok, "bitti", purge/pull/salt-okunur yazımı yok',
      () async {
    when(() => records.sync('shared')).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/sync'),
        response: Response(requestOptions: RequestOptions(path: '/sync'), statusCode: 403)));
    final c = make();

    expect(await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5)),
        bgOutcomeDone);
    verifyNever(() => babies.pullFromServer(accountId: any(named: 'accountId')));
    verifyNever(() => babies.pullFromServer());
    verifyNever(() => records.purgeBaby(any()));
  });

  test('BabyController ve subscriptionProvider HİÇ kurulmaz (ağ/unawaited iş yok)',
      () async {
    when(() => records.sync('shared')).thenAnswer((_) async {});
    final c = make();
    var babyCtrlInit = false, subInit = false;
    // dispose'dan önce gözlemek için gövdeyi kendimiz çağırmıyoruz; bunun yerine
    // provider'ların hiç başlatılmadığını dispose ÖNCESİ bir kancayla tespit edelim.
    final observer = Provider<void>((ref) {
      ref.onDispose(() {
        babyCtrlInit = c.exists(babyControllerProvider);
        subInit = c.exists(subscriptionProvider);
      });
    });
    c.read(observer);
    await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5));
    expect(babyCtrlInit, isFalse);
    expect(subInit, isFalse);
  });

  test('onlyBabyId (FCM sync_nudge): yalnız o bebek, paylaşımsız olsa da', () async {
    when(() => records.sync(any())).thenAnswer((_) async {});
    final c = make();
    await runBackgroundSyncWith(c,
        timeout: const Duration(seconds: 5), onlyBabyId: 'solo');
    verify(() => records.sync('solo')).called(1);
    verifyNever(() => records.sync('shared'));
  });

  test('bekleme (gebelik) bebeği atlanır', () async {
    when(() => babies.getAll(accountId: any(named: 'accountId'))).thenAnswer(
        (_) async => [_baby('preg', status: BabyStatus.expecting)]);
    final c = make();
    expect(await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5)),
        bgOutcomeDone);
    verifyNever(() => records.sync(any()));
  });

  test('O1: sync 401 (refresh reddi sonrası) → damga "oturum yok", dispose en sonda', () async {
    when(() => records.sync('shared')).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/sync'),
        response: Response(requestOptions: RequestOptions(path: '/sync'), statusCode: 401)));
    final c = make();
    expect(await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5)),
        bgOutcomeNoSession);
    expect(disposed, isTrue);
  });

  group('İlaç v2 (M6) — arka plan turunda plan senkronu + ilaç bildirimi yeniden kurma', () {
    late List<String> planSynced;
    late List<List<String>> rebuilt;

    setUp(() {
      planSynced = [];
      rebuilt = [];
      bgMedHook = BgMedHook(
        syncPlans: (c, id) async => planSynced.add(id),
        rebuild: (c, list) async => rebuilt.add([for (final b in list) b.id]),
      );
      when(() => records.sync(any())).thenAnswer((_) async {});
    });

    test('periyodik tur: planlar yalnız paylaşımlı bebekte çekilir; yeniden kurma TÜM bebekler', () async {
      final c = make();
      await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5));
      expect(planSynced, ['shared']);
      expect(rebuilt.single, ['shared', 'solo']);
    });

    test('FCM sync_nudge (plans): o bebeğin planları çekilir ve yeniden kurulur', () async {
      final c = make();
      await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5), onlyBabyId: 'solo');
      expect(planSynced, ['solo']);
      expect(rebuilt.single, ['shared', 'solo']);
    });

    test('plan senkronu düşse de yeniden kurma yapılır (yerel planlarla)', () async {
      bgMedHook = BgMedHook(
        syncPlans: (c, id) async => throw DioException(requestOptions: RequestOptions()),
        rebuild: (c, list) async => rebuilt.add([for (final b in list) b.id]),
      );
      final c = make();
      expect(await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5)), bgOutcomeDone);
      expect(rebuilt, hasLength(1));
    });

    test('bekleme bebeği yeniden kurmaya girmez', () async {
      when(() => babies.getAll(accountId: any(named: 'accountId'))).thenAnswer(
          (_) async => [_baby('preg', status: BabyStatus.expecting), _baby('shared')]);
      final c = make();
      await runBackgroundSyncWith(c, timeout: const Duration(seconds: 5));
      expect(rebuilt.single, ['shared']);
    });
  });

  group('V24 — bg access_removed', () {
    test('çıkarılan bebeğin özel/randevu hatırlatıcıları iptal edilir, ilaç yeniden kurulur',
        () async {
      final rid = await db.into(db.localReminders).insert(
          LocalRemindersCompanion.insert(baby: 'shared'));
      final other = await db.into(db.localReminders).insert(
          LocalRemindersCompanion.insert(baby: 'solo'));
      final plugin = _CancelSpy();
      final prev = NotificationService.instance;
      NotificationService.instance = NotificationService.withPlugin(plugin);
      addTearDown(() => NotificationService.instance = prev);
      final rebuilt = <List<String>>[];
      bgMedHook = BgMedHook(
          syncPlans: (_, _) async {},
          rebuild: (c, list) async => rebuilt.add([for (final b in list) b.id]));
      final c = make();
      await rebuildMedicationFromPushWith(c, revokedBabyId: 'shared');
      expect(plugin.cancelled, contains(rid));
      expect(plugin.cancelled, isNot(contains(other)));
      expect(rebuilt, hasLength(1));
      expect(disposed, isTrue);
    });
  });
}
