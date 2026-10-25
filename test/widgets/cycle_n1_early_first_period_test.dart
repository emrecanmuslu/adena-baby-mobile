import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/cycle_repository.dart';
import 'package:adena_baby/data/local/app_database.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/features/cycle/cycle_entry_sheet.dart';
import 'package:adena_baby/features/cycle/cycle_today_screen.dart';
import 'package:adena_baby/models/cycle.dart';

import 'cycle_screen_harness.dart';

class _MockRepo extends Mock implements CycleRepository {}

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'a';
  @override
  Future<String?> get refreshToken async => 'r';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

/// Düzeltme turu 2 — N1 (S1 düzeltmesi): doğum+0..42 günde akış varsayılan
/// olarak loşia sayılır, ama kullanıcı AÇIKÇA "Bu ilk adetim" diyebilir →
/// onay diyaloğu → [İlk adetim olarak kaydet] çapa kurar / [Loşia olarak
/// kaydet] loşia kalır.
void main() {
  setUpAll(() => registerFallbackValue(CycleEntry(id: '', date: DateTime(2026))));

  late _MockRepo repo;
  final saved = <(CycleEntry, bool)>[];
  setUp(() {
    repo = _MockRepo();
    saved.clear();
    when(() => repo.saveEntry(any(),
            confirmedFirstPeriod: any(named: 'confirmedFirstPeriod')))
        .thenAnswer((inv) async {
      final e = inv.positionalArguments.first as CycleEntry;
      saved.add((e, inv.namedArguments[#confirmedFirstPeriod] as bool));
      return e;
    });
  });

  Future<void> open(WidgetTester t, {int birthDaysAgo = 35}) async {
    await pumpCycleScreen(t,
        Consumer(builder: (context, ref, _) => TextButton(
            onPressed: () => showCycleEntrySheet(context, ref, lochiaMode: true),
            child: const Text('AÇ'))),
        settings: CycleSettings(
          birthDate: dayOffset(-birthDaysAgo),
          breastfeeding: Breastfeeding.none,
          lifecycleMode: CycleLifecycleMode.postpartum,
          predictionsHidden: true,
        ),
        overrides: [cycleRepositoryProvider.overrideWithValue(repo)]);
    await t.tap(find.text('AÇ'));
    await t.pumpAndSettle();
  }

  const body = 'Doğumdan sonraki ilk haftalardaki kanama çoğunlukla loşiadır. '
      'Bunun ilk âdetin olduğundan eminsen kaydedebilirsin; âdet takvimin bu '
      'günden başlar.';

  testWidgets('doğum+35: "Bu ilk âdetim" → onay → onaylı âdet kaydı', (t) async {
    await open(t);
    await t.tap(find.text('Bu ilk âdetim'));
    await t.pumpAndSettle();
    expect(textHas(body), findsOneWidget);
    await t.tap(find.text('İlk âdetim olarak kaydet'));
    await t.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single.$2, isTrue);
    expect(saved.single.$1.isPeriod, isTrue);
  });

  testWidgets('doğum+35: onay yerine "Loşia olarak kaydet" → onaysız', (t) async {
    await open(t);
    await t.tap(find.text('Bu ilk âdetim'));
    await t.pumpAndSettle();
    await t.tap(find.text('Loşia olarak kaydet'));
    await t.pumpAndSettle();
    expect(saved.single.$2, isFalse);
  });

  testWidgets('loşia ekranı notu açık seçeneği anlatır', (t) async {
    await pumpCycleScreen(t, const CycleTodayScreen(),
        settings: CycleSettings(
          birthDate: dayOffset(-20),
          breastfeeding: Breastfeeding.none,
          lifecycleMode: CycleLifecycleMode.postpartum,
          predictionsHidden: true,
        ));
    expect(textHas('kayıt ekranında "Bu ilk âdetim"i seçebilirsin'), findsOneWidget);
    expect(textHas('ilk âdet olarak kabul edilmez'), findsNothing);
  });

  testWidgets('doğum+60: seçenek görünmez', (t) async {
    await open(t, birthDaysAgo: 60);
    expect(find.text('Bu ilk âdetim'), findsNothing);
  });

  group('repository (gerçek)', () {
    const acct = 'acct-n1';
    late ApiClient api;
    late AppDatabase db;
    setUp(() {
      api = ApiClient(_FakeTokens());
      DioAdapter(dio: api.dio);
      db = AppDatabase(NativeDatabase.memory());
      LocalSession.setActiveAccount(acct);
    });
    tearDown(() async {
      LocalSession.setActiveAccount(null);
      await db.close();
    });
    final birth = DateTime(2026, 2, 1);
    DateTime pp(int n) => DateTime(2026, 2, 1 + n);
    Future<CycleRepository> setup() async {
      final r = CycleRepository(db, api, () => false);
      await r.patchSettings({
        'birth_date': '2026-02-01',
        'lifecycle_mode': 'postpartum',
        'predictions_hidden': true,
      });
      return r;
    }

    test('doğum+35 onaylı → çapa + tracking', () async {
      final r = await setup();
      await r.saveEntry(CycleEntry(id: '', date: pp(35), flow: FlowLevel.medium),
          confirmedFirstPeriod: true);
      final s = await r.getSettings();
      expect(s.firstPeriodDate, pp(35));
      expect(s.lifecycleMode, CycleLifecycleMode.tracking);
      expect(s.predictionsHidden, isFalse);
      expect(birth.isBefore(pp(35)), isTrue);
    });

    test('doğum+35 onaysız (loşia / seçenek kullanılmadı) → çapa yok', () async {
      final r = await setup();
      await r.saveEntry(CycleEntry(id: '', date: pp(35), flow: FlowLevel.medium));
      final s = await r.getSettings();
      expect(s.firstPeriodDate, isNull);
      expect(s.lifecycleMode, CycleLifecycleMode.postpartum);
    });
  });
}
