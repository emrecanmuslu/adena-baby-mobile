import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/medication/med_scheduler.dart';
import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

/// İlaç v2 (A4) — doz başına tek seferlik bildirim planlayıcısı.
class _FakeAndroid implements AndroidFlutterLocalNotificationsPlugin {
  bool canExact = true;
  @override
  Future<bool?> canScheduleExactNotifications() async => canExact;
  @override
  Future<bool?> requestNotificationsPermission() async => true;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Fake implements FlutterLocalNotificationsPlugin {
  final android = _FakeAndroid();
  final pending = <int, ({DateTime at, String? title, String? body, String? payload})>{};
  final displayed = <int>{}; // ekrandaki (süresi gelip gösterilmiş) bildirimler
  int schedules = 0;
  final cancels = <int>[];

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;
  @override
  T? resolvePlatformSpecificImplementation<T extends FlutterLocalNotificationsPlatform>() =>
      T == AndroidFlutterLocalNotificationsPlugin ? android as T : null;
  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async => [
        for (final e in pending.entries)
          PendingNotificationRequest(e.key, e.value.title, e.value.body, e.value.payload)
      ];
  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancels.add(id);
    pending.remove(id);
    displayed.remove(id);
  }

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
  }) async {
    expect(matchDateTimeComponents, isNull, reason: 'tek seferlik olmalı');
    schedules++;
    pending[id] = (
        at: DateTime.fromMillisecondsSinceEpoch(scheduledDate.millisecondsSinceEpoch),
        title: title,
        body: body,
        payload: payload);
  }

  /// Saat ilerler: süresi gelen bekleyenler ekrana düşer.
  void advance(DateTime now) {
    for (final id in [...pending.keys]) {
      if (!pending[id]!.at.isAfter(now)) {
        pending.remove(id);
        displayed.add(id);
      }
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

MedicationPlan _p({
  String uuid = 'p1',
  int id = 1,
  String name = 'Demir',
  String dose = '1 ml',
  List<String> times = const ['08:00', '20:00'],
  DateTime? end,
  bool active = true,
}) =>
    MedicationPlan(
      id: id, uuid: uuid, name: name, dose: dose, times: times, active: active,
      createdAt: DateTime(2026, 10, 1), startDate: DateTime(2026, 10, 1), endDate: end);

Record _given(String date, String time, {String plan = 'p1'}) => Record(
      id: 'r$date$time',
      baby: 'b1',
      type: RecordType.medication,
      ts: DateTime.parse('${date}T$time:00'),
      data: {'plan_uuid': plan, 'dose_date': date, 'dose_time': time, 'given': true},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Fake plugin;
  late NotificationService svc;
  late DateTime now;
  late List<String> mirrored;

  MedicationScheduler sched({bool ios = false}) => MedicationScheduler.forTest(svc,
      now: () => now, ios: ios, mirror: (j) async => mirrored.add(j));

  MedSchedLoader input(List<MedicationPlan> plans,
          {List<Record> records = const [], bool enabled = true, bool missedOn = true,
          bool expecting = false, String name = 'Ada'}) =>
      () async => MedSchedInput(enabled: enabled, missedOn: missedOn, babies: [
            MedSchedBaby(id: 'b1', name: name, expecting: expecting, plans: plans, records: records)
          ]);

  Iterable<String> titles() => plugin.pending.values.map((v) => v.title ?? '');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    plugin = _Fake();
    svc = NotificationService.withPlugin(plugin);
    now = DateTime(2026, 10, 12, 7, 0);
    mirrored = [];
  });

  test('günlük plan: 7 gün × saat × (ana + K4) tek seferlik; id\'ler yeni aralıkta; başlık/gövde',
      () async {
    await sched().rebuild(input([_p()]));
    expect(plugin.pending.length, 7 * 2 * 2 + 1); // + pencere sonu uyarısı
    for (final id in plugin.pending.keys) {
      expect(id, inInclusiveRange(NotificationService.medIdLo, NotificationService.medIdHi - 1));
    }
    final first = plugin.pending.values.reduce((a, b) => a.at.isBefore(b.at) ? a : b);
    expect(first.at, DateTime(2026, 10, 12, 8));
    expect(first.title, 'Ada · Demir · 08:00');
    expect(first.body, '1 ml');
    expect(first.payload, 'med:p1|2026-10-12|08:00|m');
    expect(titles(), contains('Ada · Demir 08:00 dozu işaretlenmedi'));
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 8, 30)), isTrue);
  });

  test('M1: verilmiş doz için ana ve K4 bildirimi kurulmaz', () async {
    await sched().rebuild(input([_p()], records: [_given('2026-10-12', '08:00')]));
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 8)), isFalse);
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 8, 30)), isFalse);
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 20)), isTrue);
  });

  test('M1: kayıt sonradan gelince (senkron/yerel) bekleyen ve EKRANDAKİ bildirim kalkar', () async {
    final s = sched();
    await s.rebuild(input([_p()]));
    now = DateTime(2026, 10, 12, 8, 5);
    plugin.advance(now); // 08:00 gösterildi
    final shown = plugin.displayed.single;
    await s.rebuild(input([_p()], records: [_given('2026-10-12', '08:00')]));
    expect(plugin.displayed, isNot(contains(shown)), reason: 'verilmiş dozun "İlaç zamanı" kalmamalı');
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 8, 30)), isFalse);
  });

  test('M8: değişmeyen yeniden kurmada hiçbir bildirime dokunulmaz; ekrandaki korunur', () async {
    final s = sched();
    await s.rebuild(input([_p()]));
    now = DateTime(2026, 10, 12, 8, 5);
    plugin.advance(now);
    final shown = plugin.displayed.single;
    final before = plugin.schedules;
    plugin.cancels.clear();
    await s.rebuild(input([_p()]));
    expect(plugin.cancels, isEmpty);
    expect(plugin.displayed, contains(shown), reason: 'okunmamış hatırlatma kaybolmamalı');
    // 7 günlük pencere 5 dk kaydı → en fazla yeni günün dozları eklenir.
    expect(plugin.schedules - before, lessThanOrEqualTo(4));
  });

  test('plan saati değişince: eski gelecek bildirimler iptal, ekrandaki dokunulmaz', () async {
    final s = sched();
    await s.rebuild(input([_p()]));
    now = DateTime(2026, 10, 12, 8, 5);
    plugin.advance(now);
    final shown = plugin.displayed.single;
    await s.rebuild(input([_p(times: const ['09:00', '21:00'])]));
    expect(plugin.displayed, contains(shown));
    expect(plugin.pending.values.any((v) => v.at.hour == 20 && v.at.minute == 0), isFalse);
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 9)), isTrue);
  });

  test('K4 kapalı → yalnız ana bildirimler; tercih kapalı → hiçbiri; bekleme modu → hiçbiri',
      () async {
    final s = sched();
    await s.rebuild(input([_p()], missedOn: false));
    expect(plugin.pending.length, 14 + 1);
    await s.rebuild(input([_p()], enabled: false));
    expect(plugin.pending, isEmpty);
    await s.rebuild(input([_p()], expecting: true));
    expect(plugin.pending, isEmpty);
  });

  test('S12: kür bitiş günü 20:00 tek "kür bugün bitiyor"; bitişten sonra doz yok', () async {
    await sched().rebuild(input([_p(end: DateTime(2026, 10, 13), times: const ['08:00'])],
        missedOn: false));
    final ats = plugin.pending.values.map((v) => v.at).toList()..sort();
    expect(ats, [DateTime(2026, 10, 12, 8), DateTime(2026, 10, 13, 8), DateTime(2026, 10, 13, 20)]);
    expect(titles(), contains('Ada · Demir · kür bugün bitiyor'));
  });

  test('iOS bütçesi: en çok 40, en yakın dozlar önce; pencere sonu "uygulamayı aç" uyarısı', () async {
    final plans = [
      for (var i = 0; i < 3; i++)
        _p(uuid: 'p$i', id: i, name: 'İlaç $i', times: const ['08:00', '14:00', '20:00'])
    ];
    await sched(ios: true).rebuild(input(plans));
    expect(plugin.pending.length, lessThanOrEqualTo(kIosMedBudget));
    final w = plugin.pending.values.where((v) => v.title == 'İlaç hatırlatmaları duracak').toList();
    expect(w, hasLength(1));
    final mains = plugin.pending.values.where((v) => (v.payload ?? '').endsWith('|m'));
    final lastMain = mains.map((v) => v.at).reduce((a, b) => a.isAfter(b) ? a : b);
    expect(w.single.at, lastMain.subtract(const Duration(hours: 2)));
    // En yakın doz mutlaka kurulu.
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 8)), isTrue);
  });

  test('Android: pencere 7 gün; süresiz planda pencere sonu uyarısı var', () async {
    await sched().rebuild(input([_p(times: const ['08:00'])], missedOn: false));
    expect(plugin.pending.length, 7 + 1);
  });

  test('cancelDose (push/NSE eşleniği): o dozun ana + K4 bildirimi hemen kalkar', () async {
    final s = sched();
    await s.rebuild(input([_p()]));
    final n = plugin.pending.length;
    await s.cancelDose('p1', '2026-10-12', '08:00');
    expect(plugin.pending.length, n - 2);
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 8)), isFalse);
  });

  test('cancelBaby: yalnız o bebeğin ilaç bildirimleri', () async {
    final s = sched();
    await s.rebuild(() async => MedSchedInput(babies: [
          MedSchedBaby(id: 'b1', name: 'Ada', plans: [_p()], records: const []),
          MedSchedBaby(id: 'b2', name: 'Can', plans: [_p(uuid: 'q', id: 9)], records: const []),
        ]));
    await s.cancelBaby('b1');
    final babyTitles = titles().where((t) => t != 'İlaç hatırlatmaları duracak');
    expect(babyTitles.every((t) => t.startsWith('Can')), isTrue);
    expect(babyTitles, isNotEmpty);
  });

  test('kesin alarm izni değişince (kip karması) hepsi yeniden kurulur', () async {
    final s = sched();
    await s.rebuild(input([_p()], missedOn: false));
    final before = plugin.schedules;
    plugin.android.canExact = false;
    await s.rebuild(input([_p()], missedOn: false));
    expect(plugin.schedules - before, 14 + 1);
  });

  test('cancelAll sonrası (defter bayat) yeniden kurma eksikleri tamamlar', () async {
    final s = sched();
    await s.rebuild(input([_p()], missedOn: false));
    plugin.pending.clear(); // NotificationService.cancelAll / OS temizliği
    await s.rebuild(input([_p()], missedOn: false));
    expect(plugin.pending.length, 14 + 1);
  });

  test('defter App Group\'a aynalanır (NSE için id/an/içerik)', () async {
    await sched().rebuild(input([_p()], missedOn: false));
    final reg = (jsonDecode(mirrored.last) as Map).cast<String, dynamic>();
    final e = reg['p1|2026-10-12|08:00|m'] as Map;
    expect(e['id'], isA<int>());
    expect(e['b'], 'b1');
    expect(e['t'], 'Ada · Demir · 08:00');
    expect(e['at'], DateTime(2026, 10, 12, 8).millisecondsSinceEpoch);
  });

  test('Adım 0: senkronla ilk kez gelen plan (planı oluşturmayan cihaz, varsayılan '
      'tercihler) → hatırlatma kurulur', () async {
    // Varsayılan MedSchedInput: enabled=true, missedOn=true (tercih okunmadı/yok).
    await sched().rebuild(() async => MedSchedInput(babies: [
          MedSchedBaby(id: 'b1', name: 'Ada', plans: [_p()], records: const []),
        ]));
    expect(plugin.pending, isNotEmpty);
  });

  test('PRN ve kürü bitmiş plan bildirim üretmez', () async {
    await sched().rebuild(input([
      _p(uuid: 'prn', id: 2).copyWith(times: const []),
      MedicationPlan(id: 3, uuid: 'prn2', name: 'Ateş', dose: '', times: const [],
          active: true, createdAt: DateTime(2026, 10, 1), kind: MedKind.prn),
      _p(uuid: 'done', id: 4, end: DateTime(2026, 10, 11)),
    ]));
    expect(plugin.pending, isEmpty);
  });

  test('V1: saat 21:00→09:00 sonrası dünkü kayıt bugünün 09:00 ana ve +30 dk hatırlatmasını engellemez',
      () async {
    now = DateTime(2026, 10, 12, 7, 30);
    final p = MedicationPlan(
        id: 1, uuid: 'p1', name: 'Demir', dose: '1 ml', times: const ['09:00'], active: true,
        createdAt: DateTime(2026, 10, 1), startDate: DateTime(2026, 10, 1),
        scheduleFrom: DateTime(2026, 10, 12, 7));
    await sched().rebuild(input([p], records: [_given('2026-10-11', '21:00')]));
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 9)), isTrue);
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 9, 30)), isTrue);
  });

  test('V2: uuid\'siz plan için de hatırlatma kurulur (yerel anahtar yedeği)', () async {
    final p = MedicationPlan(
        id: 9, name: 'Eski', dose: '', times: const ['09:00'], active: true,
        createdAt: DateTime(2026, 10, 1), startDate: DateTime(2026, 10, 1));
    await sched().rebuild(input([p]));
    expect(plugin.pending.values.any((v) => v.at == DateTime(2026, 10, 12, 9)), isTrue);
  });

  group('V5 — isolate\'lar arası defter (SharedPreferences önbelleği)', () {
    Future<void> otherIsolateWrites(Map<String, dynamic> reg) =>
        SharedPreferencesStorePlatform.instance
            .setValue('String', 'flutter.${MedicationScheduler.kRegistry}', jsonEncode(reg));

    test('başka isolate dozu yeni id ile kurduysa cancelDose GÜNCEL defteri okur', () async {
      final s = sched();
      await s.rebuild(input([_p()])); // bu isolate'in önbelleği yüklendi
      final reg = (jsonDecode((await SharedPreferences.getInstance())
              .getString(MedicationScheduler.kRegistry)!) as Map)
          .cast<String, dynamic>();
      const k = 'p1|2026-10-12|08:00|m';
      final oldId = (reg[k] as Map)['id'] as int;
      plugin.pending.remove(oldId);
      const newId = NotificationService.medIdLo + 99999;
      plugin.pending[newId] =
          (at: DateTime(2026, 10, 12, 8), title: 'Ada · Demir · 08:00', body: '1 ml', payload: null);
      reg[k] = {...(reg[k] as Map), 'id': newId};
      await otherIsolateWrites(reg);
      await s.cancelDose('p1', '2026-10-12', '08:00');
      expect(plugin.pending.containsKey(newId), isFalse,
          reason: 'bayat önbellek eski id\'yi iptal eder, yenisi çalardı');
    });

    test('erişimi kalkan bebek (access_removed) sonraki yeniden kurmada geri kurulmaz', () async {
      final s = sched();
      await s.rebuild(input([_p()]));
      expect(plugin.pending, isNotEmpty);
      await s.cancelBaby('b1', revoke: true);
      expect(plugin.pending, isEmpty);
      // bg turu: yerel DB'de bebek henüz duruyor (temizlik ön planda) → kurulmamalı.
      await s.rebuild(input([_p()]));
      expect(plugin.pending, isEmpty);
      // Ön plan bebek listesini başarıyla tazeledi (yeniden davet / yanlış alarm).
      await s.clearRevoked();
      await s.rebuild(input([_p()]));
      expect(plugin.pending, isNotEmpty);
    });
  });
}
