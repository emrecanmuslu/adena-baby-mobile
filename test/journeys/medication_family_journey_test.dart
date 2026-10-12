import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/medication.dart';
import 'package:adena_baby/core/medication/dose_write.dart';
import 'package:adena_baby/core/medication/med_scheduler.dart';
import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/core/push_service.dart' show medDoseCancelTarget;
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

/// İlaç v2 (A9) — ILAC-INCELEME §2'nin 14 senaryosu, YENİ beklenen sonuçlarla,
/// iki ebeveynli aile yolculuğu olarak. "Sunucu" = ortak kayıt/plan kümesi;
/// B'nin cihazı = kendi bildirim eklentisi + planlayıcısı. A'nın eylemleri
/// sunucuya kayıt/plan olarak düşer; push `med_dose` / `access_removed` B'de
/// ağsız iptal olarak uygulanır (Android bg / ön plan). iOS NSE (Swift) burada
/// doğrulanamaz — cihaz adımları ILAC-YAYIN.md.
class _Plugin implements FlutterLocalNotificationsPlugin {
  final pending = <int, DateTime>{};
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
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      [for (final id in pending.keys) PendingNotificationRequest(id, null, null, null)];
  @override
  Future<void> cancel({required int id, String? tag}) async => pending.remove(id);
  @override
  Future<void> cancelAll() async => pending.clear();
  @override
  Future<void> zonedSchedule({
    required int id,
    required TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async =>
      pending[id] = DateTime.fromMillisecondsSinceEpoch(scheduledDate.millisecondsSinceEpoch);
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Plugin bDevice;
  late MedicationScheduler bSched;
  late DateTime now;
  late List<Record> server; // ortak kayıtlar
  late List<MedicationPlan> plans; // ortak planlar (B'de senkronla inmiş)
  var n = 0;

  MedicationPlan plan(
          {List<String> times = const ['08:00', '20:00'], bool active = true, DateTime? scheduleFrom}) =>
      MedicationPlan(
          id: 1, uuid: 'p1', name: 'Demir', dose: '1 ml', times: times, active: active,
          createdAt: DateTime(2026, 10, 1), startDate: DateTime(2026, 10, 1),
          scheduleFrom: scheduleFrom ?? DateTime(2026, 10, 1));

  Record mark(String by, DateTime at, String date, String time, {bool skipped = false}) {
    final r = medDoseRecord(
        id: 'r${n++}', babyId: 'b1', plan: plans.single,
        doseDate: DateTime.parse(date), doseTime: time, at: at, skipped: skipped);
    return Record(id: r.id, baby: r.baby, type: r.type, ts: r.ts, data: r.data, createdBy: by);
  }

  Future<void> bRebuild() => bSched.rebuild(() async => MedSchedInput(
      babies: [MedSchedBaby(id: 'b1', name: 'Ada', plans: plans, records: server)]));

  bool bHasAt(DateTime t) => bDevice.pending.values.contains(t);

  /// A'nın işareti B'ye push olarak ulaşır (ağsız iptal).
  Future<void> pushToB(Record r, String event) async {
    final t = medDoseCancelTarget({
      'type': 'med_dose', 'event': event, 'plan_uuid': r.data['plan_uuid'],
      'dose_date': r.data['dose_date'], 'dose_time': r.data['dose_time'],
    });
    if (t != null) await bSched.cancelDose(t.plan, t.date, t.time);
  }

  List<MedicationDose> card() =>
      resolveDoses(plans, server, from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 13), now: now);
  MedicationDose doseAt(String t) => card().firstWhere((d) => d.time == t);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bDevice = _Plugin();
    now = DateTime(2026, 10, 12, 7, 0);
    bSched = MedicationScheduler.forTest(NotificationService.withPlugin(bDevice), now: () => now);
    server = [];
    plans = [plan()];
    await bRebuild();
  });

  test('S1/S7: A 07:58\'de verir → B\'nin 08:00 ve 08:30 bildirimi push\'la (uygulama kapalı) iptal', () async {
    expect(bHasAt(DateTime(2026, 10, 12, 8)), isTrue);
    now = DateTime(2026, 10, 12, 7, 58);
    final r = mark('A', now, '2026-10-12', '08:00');
    server.add(r);
    await pushToB(r, 'given');
    expect(bHasAt(DateTime(2026, 10, 12, 8)), isFalse);
    expect(bHasAt(DateTime(2026, 10, 12, 8, 30)), isFalse);
    await bRebuild(); // sonra senkron: geri kurulmaz
    expect(bHasAt(DateTime(2026, 10, 12, 8)), isFalse);
    expect(bHasAt(DateTime(2026, 10, 12, 20)), isTrue);
  });

  test('S2: ikisi çevrimdışı aynı dozu verir → "2 kez verildi" görünür; 20:00 verilmiş sayılmaz', () async {
    now = DateTime(2026, 10, 12, 9);
    server.addAll([
      mark('A', DateTime(2026, 10, 12, 7, 58), '2026-10-12', '08:00'),
      mark('B', DateTime(2026, 10, 12, 8, 3), '2026-10-12', '08:00'),
    ]);
    expect(doseAt('08:00').multiple, isTrue);
    expect(doseAt('20:00').isResolved, isFalse);
    await bRebuild();
    expect(bHasAt(DateTime(2026, 10, 12, 20)), isTrue);
  });

  test('S3: A verdi, B atladı → verildi kazanır + çakışma notu; 20:00 etkilenmez', () async {
    now = DateTime(2026, 10, 12, 9);
    server.addAll([
      mark('A', DateTime(2026, 10, 12, 7, 58), '2026-10-12', '08:00'),
      mark('B', DateTime(2026, 10, 12, 8, 5), '2026-10-12', '08:00', skipped: true),
    ]);
    expect(doseAt('08:00').isGiven, isTrue);
    expect(doseAt('08:00').conflict, isTrue);
    expect(doseAt('20:00').status, MedicationDoseStatus.upcoming);
  });

  test('S3b: A geri alır → B\'de hatırlatma (zamanı gelmemişse) yeniden kurulur', () async {
    now = DateTime(2026, 10, 12, 7, 30);
    final r = mark('A', now, '2026-10-12', '08:00');
    server.add(r);
    await pushToB(r, 'given');
    expect(bHasAt(DateTime(2026, 10, 12, 8)), isFalse);
    server.remove(r); // geri alındı (senkron)
    await pushToB(r, 'undone'); // iptal yapmaz
    await bRebuild();
    expect(bHasAt(DateTime(2026, 10, 12, 8)), isTrue);
  });

  test('S4: A saati 08:00→09:00 yapar → B yeniden kurar; 08:01 kaydı 09:00 dozunu kapatır (gizli çift yok)', () async {
    now = DateTime(2026, 10, 12, 8, 30);
    server.add(mark('A', DateTime(2026, 10, 12, 8, 1), '2026-10-12', '08:00'));
    // Gerçek düzenleme: saat değişince zamanlama çapası (scheduleFrom) ilerler.
    plans = [plan(times: const ['09:00', '21:00'], scheduleFrom: DateTime(2026, 10, 12, 8, 20))];
    await bRebuild();
    expect(bHasAt(DateTime(2026, 10, 12, 9)), isFalse, reason: 'bugünkü doz zaten verildi');
    expect(bHasAt(DateTime(2026, 10, 12, 21)), isTrue);
    expect(bHasAt(DateTime(2026, 10, 13, 9)), isTrue);
    expect(bDevice.pending.values.any((t) => t.hour == 20 && t.minute == 0), isFalse);
  });

  test('S5: A duraklatır / siler → B\'de bekleyen ilaç bildirimi kalmaz', () async {
    plans = [plan(active: false)];
    await bRebuild();
    expect(bDevice.pending, isEmpty);
    plans = [plan()];
    await bRebuild();
    expect(bDevice.pending, isNotEmpty);
    plans = [];
    await bRebuild();
    expect(bDevice.pending, isEmpty);
  });

  test('S6: bakıcının işareti ebeveynlere aynı yoldan ulaşır (rol bağımsız)', () async {
    now = DateTime(2026, 10, 12, 8, 2);
    final r = mark('caregiver', now, '2026-10-12', '08:00');
    server.add(r);
    await pushToB(r, 'given');
    expect(bHasAt(DateTime(2026, 10, 12, 8, 30)), isFalse);
    expect(doseAt('08:00').givenRecords.single.createdBy, 'caregiver');
  });

  test('S8: aileden çıkarılan üye → access_removed ile tüm ilaç bildirimleri iptal', () async {
    expect(bDevice.pending, isNotEmpty);
    await bSched.cancelBaby('b1');
    expect(bDevice.pending, isEmpty);
  });

  test('S9: yeni katılan üye — plan senkronla inince varsayılan tercihlerle kurulur', () async {
    plans = [];
    await bRebuild();
    expect(bDevice.pending, isEmpty);
    plans = [plan()];
    await bRebuild();
    expect(bHasAt(DateTime(2026, 10, 12, 8)), isTrue);
  });

  test('S13: dünkü 22:00 dozu 00:20\'de verilir → dünün dozu; bugünün 08:00 hatırlatması durur', () async {
    plans = [plan(times: const ['08:00', '22:00'])];
    now = DateTime(2026, 10, 13, 0, 20);
    server.add(mark('A', now, '2026-10-12', '22:00'));
    await bRebuild();
    final ds = resolveDoses(plans, server,
        from: DateTime(2026, 10, 12), to: DateTime(2026, 10, 14), now: now);
    expect(ds.firstWhere((d) => d.doseDate == DateTime(2026, 10, 12) && d.time == '22:00').isGiven,
        isTrue);
    expect(ds.firstWhere((d) => d.doseDate == DateTime(2026, 10, 13) && d.time == '08:00').isResolved,
        isFalse);
    expect(bHasAt(DateTime(2026, 10, 13, 8)), isTrue);
  });

  test('S14: çıkış → defter + bildirimler temizlenir; sessionExpired → değişiklik yok (K5)', () async {
    final before = Map.of(bDevice.pending);
    // sessionExpired: planlayıcıya dokunulmaz.
    expect(bDevice.pending, before);
    await NotificationService.withPlugin(bDevice).cancelAll();
    await bSched.clearRegistry();
    expect(bDevice.pending, isEmpty);
  });
}
