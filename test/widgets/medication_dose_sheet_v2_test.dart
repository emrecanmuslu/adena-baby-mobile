import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/data/local_session.dart';
import 'package:adena_baby/data/record_repository.dart';
import 'package:adena_baby/data/sync_gate.dart';
import 'package:adena_baby/features/auth/auth_controller.dart';
import 'package:adena_baby/features/babies/members_screen.dart';
import 'package:adena_baby/features/health/medication_widgets.dart';
import 'package:adena_baby/features/records/record_controller.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/membership.dart';
import 'package:adena_baby/models/record.dart';
import 'package:adena_baby/models/user.dart';

/// İlaç v2 — doz sayfası / işaretleme akışları (ILAC-INCELEME-2 V12, V34):
/// "Verildi yap" (V12), bakıcı yalnız kendi kaydını (M16), erken işaretleme
/// onayı (S9), K3 çift doz diyaloğu.
class _MockActions extends Mock implements RecordActions {}

class _MockRecords extends Mock implements RecordRepository {}

class _Me extends AuthController {
  @override
  Future<User?> build() async => const User(id: 'me', email: 'me@x.com', name: 'Ben');
}

final _plan = MedicationPlan(
    id: 1, uuid: 'u1', name: 'Demir', dose: '1 ml', times: const ['08:00', '20:00'],
    active: true, createdAt: DateTime(2026, 1, 1), startDate: DateTime(2026, 1, 1));

String _ymd(DateTime d) => medDateToWire(d)!;

Record _rec(String id, DateTime doseDay, String time, DateTime ts,
        {String? by, bool skipped = false}) =>
    Record(
      id: id,
      baby: 'b1',
      type: RecordType.medication,
      ts: ts,
      data: {
        'v': 2, 'name': 'Demir', 'plan_uuid': 'u1', 'kind': 'scheduled',
        'dose_date': _ymd(doseDay), 'dose_time': time, 'given': !skipped,
        if (skipped) 'skipped': true,
      },
      createdBy: by,
    );

void main() {
  late _MockActions actions;
  late _MockRecords records;

  setUpAll(() {
    initializeDateFormatting('tr_TR');
    registerFallbackValue(Record(
        id: 'x', baby: 'b', type: RecordType.medication, ts: DateTime(2026), data: const {}));
  });

  setUp(() {
    actions = _MockActions();
    records = _MockRecords();
    when(() => actions.upsertQuiet(any())).thenAnswer((_) async {});
    when(() => actions.delete(any())).thenAnswer((_) async {});
  });

  /// [recent] = kartın izlediği bugün/dün kayıtları (K3 denetimi).
  Future<void> pump(WidgetTester t, MedicationDose dose,
      {bool fullWrite = true, List<Record> recent = const []}) async {
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    when(() => records.watchDay(any(), any())).thenAnswer((_) => Stream.value(recent));
    await t.pumpWidget(ProviderScope(
      overrides: [
        recordActionsProvider.overrideWithValue(actions),
        recordRepositoryProvider.overrideWithValue(records),
        authControllerProvider.overrideWith(_Me.new),
        localUserIdProvider.overrideWithValue('local-me'),
        canFullWriteProvider('b1').overrideWithValue(fullWrite),
        membersProvider('b1').overrideWith((ref) async => const [
              Membership(user: User(id: 'me', email: 'me@x.com', name: 'Ben'), role: 'parent'),
              Membership(user: User(id: 'u2', email: 'a@x.com', name: 'Ayşe'), role: 'owner'),
            ]),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            // K3 denetimi kartın izlediği akışlardan (bugün + dün) okur.
            final now = DateTime.now();
            ref.watch(dayRecordsProvider((babyId: 'b1', day: DateTime(now.year, now.month, now.day))));
            ref.watch(dayRecordsProvider(
                (babyId: 'b1', day: DateTime(now.year, now.month, now.day - 1))));
            ref.watch(membersProvider('b1'));
            ref.watch(authControllerProvider);
            return Center(
              child: TextButton(
                  onPressed: () => medTapDose(context, ref, 'b1', dose), child: const Text('doz')),
            );
          }),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('doz'));
    await t.pumpAndSettle();
  }

  MedicationDose doseOf(List<Record> recs, DateTime now, String time) =>
      todaysMedicationDoses([_plan], recs, now: now).firstWhere((d) => d.time == time);

  group('V12 — "Verildi yap"', () {
    testWidgets('doz zaten verilmişse (verildi + atlandı çakışması) "Verildi yap" yok', (t) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final recs = [
        _rec('g', today, '08:00', today.add(const Duration(hours: 8, minutes: 1)), by: 'u2'),
        _rec('s', today, '08:00', today.add(const Duration(hours: 8, minutes: 3)),
            by: 'me', skipped: true),
      ];
      final dose = doseOf(recs, today.add(const Duration(hours: 9)), '08:00');
      expect(dose.conflict, isTrue);
      await pump(t, dose, recent: recs);
      expect(find.text('Kaydı geri al'), findsWidgets);
      expect(find.text('Verildi yap'), findsNothing);
    });

    testWidgets('yalnız atlanmış doz: "Verildi yap" K3 çift doz denetiminden geçer', (t) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final at = DateTime.now();
      // 20:00 dozu atlandı; aynı plan 10 dk önce (başka doz kimliğiyle) verildi →
      // gizli çift: "Verildi yap" önce onay sormalı.
      final skip = _rec('s', today, '20:00', at.subtract(const Duration(minutes: 5)),
          by: 'me', skipped: true);
      final other = _rec('g', today, '08:00', at.subtract(const Duration(minutes: 10)), by: 'u2');
      final dose = doseOf([skip], at, '20:00');
      expect(dose.isSkipped, isTrue);
      await pump(t, dose, recent: [skip, other]);
      await t.tap(find.text('Verildi yap'));
      await t.pumpAndSettle();
      expect(find.text('Bu doz zaten verildi'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      verifyNever(() => actions.upsertQuiet(any()));
    });
  });
}
