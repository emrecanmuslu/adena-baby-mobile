import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/theme.dart';
import 'package:adena_baby/data/health_repository.dart';
import 'package:adena_baby/data/record_repository.dart';
import 'package:adena_baby/features/health/medication_history_screen.dart';
import 'package:adena_baby/features/health/medication_plan_sheet.dart';
import 'package:adena_baby/features/health/medication_widgets.dart';
import 'package:adena_baby/features/health/medications_screen.dart' show medPlanSchedule;
import 'package:adena_baby/features/records/record_controller.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

class _MockActions extends Mock implements RecordActions {}

class _MockRecords extends Mock implements RecordRepository {}

MedicationPlan _plan({
  int id = 1,
  String name = 'Demir',
  MedKind kind = MedKind.scheduled,
  MedFreq freq = MedFreq.daily,
  List<String> times = const ['08:00', '20:00'],
  int? interval,
  int? everyN,
  List<int> weekdays = const [],
  DateTime? end,
  int? prnMin,
  int? prnMax,
}) =>
    MedicationPlan(
      id: id, uuid: 'u$id', name: name, dose: '1 ml', times: times, active: true,
      createdAt: DateTime(2026, 10, 1), startDate: DateTime(2026, 10, 1), kind: kind,
      freq: freq, intervalHours: interval, everyNDays: everyN, weekdays: weekdays,
      endDate: end, prnMinIntervalMin: prnMin, prnMaxPerDay: prnMax);

Record _prnRec(DateTime ts) => Record(
      id: 'p$ts',
      baby: 'b1',
      type: RecordType.medication,
      ts: ts,
      data: {'plan_uuid': 'u9', 'kind': 'prn', 'dose_date': '2026-10-12', 'given': true},
    );

void main() {
  setUpAll(() {
    initializeDateFormatting('tr_TR');
    registerFallbackValue(Record(
        id: 'x', baby: 'b', type: RecordType.medication, ts: DateTime(2026), data: const {}));
  });

  group('validateMedPlanDraft (K7–K9)', () {
    MedPlanDraft d({
      String name = 'Demir',
      MedKind kind = MedKind.scheduled,
      MedFreq freq = MedFreq.daily,
      List<String> times = const ['08:00'],
      int? interval,
      int? everyN,
      Set<int> weekdays = const {},
      DateTime? end,
      int? prnMin,
      int? prnMax,
    }) =>
        MedPlanDraft(
            name: name, kind: kind, freq: freq, times: times, intervalHours: interval,
            everyNDays: everyN, weekdays: weekdays, start: DateTime(2026, 10, 12), end: end,
            prnMinIntervalMin: prnMin, prnMaxPerDay: prnMax);

    test('geçerli taslaklar', () {
      expect(validateMedPlanDraft(d(), const []), isNull);
      expect(validateMedPlanDraft(d(freq: MedFreq.interval, interval: 8), const []), isNull);
      expect(validateMedPlanDraft(d(freq: MedFreq.everyNDays, everyN: 2), const []), isNull);
      expect(validateMedPlanDraft(d(freq: MedFreq.weekly, weekdays: {1, 3}), const []), isNull);
      expect(validateMedPlanDraft(d(kind: MedKind.prn, times: const []), const []), isNull);
      expect(validateMedPlanDraft(d(kind: MedKind.prn, times: const [], prnMin: 360, prnMax: 4),
          const []), isNull);
    });

    test('hatalar', () {
      expect(validateMedPlanDraft(d(name: ' '), const []), isNotNull);
      expect(validateMedPlanDraft(d(name: 'DEMİR'), const ['demir']), isNotNull); // M7
      expect(validateMedPlanDraft(d(times: const []), const []), isNotNull);
      expect(validateMedPlanDraft(d(freq: MedFreq.interval, interval: 0), const []), isNotNull);
      expect(validateMedPlanDraft(d(freq: MedFreq.interval, interval: 49), const []), isNotNull);
      expect(validateMedPlanDraft(d(freq: MedFreq.everyNDays, everyN: 1), const []), isNotNull);
      expect(validateMedPlanDraft(d(freq: MedFreq.weekly), const []), isNotNull);
      expect(validateMedPlanDraft(d(end: DateTime(2026, 10, 1)), const []), isNotNull);
      expect(validateMedPlanDraft(d(kind: MedKind.prn, times: const [], prnMax: 0), const []),
          isNotNull);
    });
  });

  test('medPlanSchedule: sıklık özeti', () {
    expect(medPlanSchedule(_plan()), 'her gün · 2 doz');
    expect(medPlanSchedule(_plan(freq: MedFreq.interval, interval: 8, times: const ['06:00'])),
        'her 8 saatte');
    expect(medPlanSchedule(_plan(freq: MedFreq.everyNDays, everyN: 2, times: const ['09:00'])),
        'gün aşırı · 1 doz');
    expect(medPlanSchedule(_plan(kind: MedKind.prn, times: const [])), 'ihtiyaç halinde');
    expect(medPlanSchedule(_plan(end: DateTime(2026, 10, 20))), startsWith('her gün · 2 doz · '));
  });

  group('plan formu (dar ekran, her mod taşmadan)', () {
    Future<void> open(WidgetTester t, {MedicationPlan? existing}) async {
      t.view.physicalSize = const Size(320, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [
          medicationPlansProvider('b1').overrideWith((ref) async => const <MedicationPlan>[]),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                    onPressed: () => showMedicationPlanSheet(c, 'b1', existing: existing),
                    child: const Text('aç')),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
    }

    testWidgets('düzenli: sıklık türleri arasında geçiş', (t) async {
      await open(t);
      expect(find.text('Sıklık'.toUpperCaseTr()), findsOneWidget);
      await t.tap(find.text('Her X saatte'));
      await t.pumpAndSettle();
      expect(find.text('İlk doz'), findsOneWidget);
      await t.tap(find.text('Haftalık'));
      await t.pumpAndSettle();
      expect(find.text('Hangi günler?'.toUpperCaseTr()), findsOneWidget);
      await t.tap(find.text('Gün aşırı / N günde'));
      await t.pumpAndSettle();
      expect(find.text('Kaç günde bir?'.toUpperCaseTr()), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('ihtiyaç halinde: aralık ve günlük sınır alanları; saat yok', (t) async {
      await open(t);
      await t.tap(find.text('İhtiyaç halinde'));
      await t.pumpAndSettle();
      expect(find.text('En kısa aralık'.toUpperCaseTr()), findsOneWidget);
      expect(find.text('Günde en fazla'.toUpperCaseTr()), findsOneWidget);
      expect(find.text('Saat ekle'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('kür süresi: gün sayısı ve bitiş tarihi', (t) async {
      await open(t, existing: _plan(end: DateTime(2026, 10, 20)));
      expect(find.textContaining('Bitiş:'), findsOneWidget);
      await t.tap(find.text('Gün sayısı'));
      await t.pumpAndSettle();
      expect(find.text('gün'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('kart — PRN satırı (K7)', () {
    late _MockActions actions;
    setUp(() {
      actions = _MockActions();
      when(() => actions.upsertQuiet(any())).thenAnswer((_) async {});
    });

    Future<void> pumpCard(WidgetTester t, MedicationDay day) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [recordActionsProvider.overrideWithValue(actions)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: SingleChildScrollView(child: MedDayCard(babyId: 'b1', day: day))),
        ),
      ));
      await t.pump(const Duration(milliseconds: 300));
    }

    final prn = _plan(id: 9, name: 'Ateş düşürücü', kind: MedKind.prn, times: const [],
        prnMin: 360);

    testWidgets('aralık dolmadıysa uyarı; "Verdim" önce onay ister', (t) async {
      final now = DateTime.now();
      final day = medicationDay([prn], [_prnRec(now.subtract(const Duration(hours: 2)))], now: now);
      await pumpCard(t, day);
      expect(find.textContaining('En kısa aralık'), findsOneWidget);
      await t.tap(find.text('Verdim'));
      await t.pumpAndSettle();
      expect(find.text('En kısa aralık dolmadı'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      verifyNever(() => actions.upsertQuiet(any()));
    });

    testWidgets('aralık dolduysa "Verdim" doğrudan PRN kaydı yazar (kimlik + gerçek an)', (t) async {
      final now = DateTime.now();
      final day = medicationDay([prn], [_prnRec(now.subtract(const Duration(hours: 7)))], now: now);
      await pumpCard(t, day);
      await t.tap(find.text('Verdim'));
      await t.pump();
      final rec = verify(() => actions.upsertQuiet(captureAny())).captured.single as Record;
      expect(rec.data['plan_uuid'], 'u9');
      expect(rec.data['kind'], 'prn');
      expect(rec.data.containsKey('dose_time'), isFalse);
      await t.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('K11 geçmiş: verildi / kaçırıldı / çift; özet sayılar', (t) async {
    final now = DateTime.now();
    String ymd(DateTime d) => medDateToWire(d)!;
    final today = DateTime(now.year, now.month, now.day);
    final y1 = today.subtract(const Duration(days: 1));
    final y2 = today.subtract(const Duration(days: 2));
    final plan = _plan(times: const ['00:01']);
    Record r(String id, DateTime day, {String? by}) => Record(
        id: id, baby: 'b1', type: RecordType.medication, ts: day.add(const Duration(minutes: 5)),
        data: {'plan_uuid': 'u1', 'dose_date': ymd(day), 'dose_time': '00:01', 'given': true},
        createdBy: by);
    final records = _MockRecords();
    when(() => records.watchSince(any(), any())).thenAnswer((_) => Stream.value([
          r('a', y1),
          r('b', y2),
          r('c', y2, by: 'other'),
        ]));
    await t.pumpWidget(ProviderScope(
      overrides: [
        medicationPlansProvider('b1').overrideWith((ref) async => [plan]),
        recordRepositoryProvider.overrideWithValue(records),
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          home: const MedicationHistoryScreen(babyId: 'b1', planId: 1)),
    ));
    await t.pumpAndSettle();
    expect(find.textContaining('kez verildi'), findsWidgets);
    expect(find.textContaining('· kaçırıldı'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
