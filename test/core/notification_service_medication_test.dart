import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/medication/med_scheduler.dart';
import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/features/babies/notification_sync.dart';
import 'package:adena_baby/models/medication_plan.dart';

/// K5 (BULGULAR.md) → İlaç v2: silinen/duraklatılan ilaç planının bildirimleri bayat
/// provider listesinden yeniden kuruluyordu; iç içe geçen eski/yeni çağrılar
/// son durumu bozuyordu. Sahte eklenti K1 testindekiyle aynı (kopya; test
/// dosyaları arasında paylaşım için ortak yardımcı dosya açmak kapsam dışı).
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  final Map<int, PendingNotificationRequest> scheduled = {};
  Set<int> get ids => scheduled.keys.toSet();

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  T? resolvePlatformSpecificImplementation<
          T extends FlutterLocalNotificationsPlatform>() =>
      null;

  /// V4: iOS'ta FLN, `NotificationId`'siz (NSE'nin eklediği) bir bekleyen istek
  /// varken listenin TAMAMINI `Null`→`int` TypeError ile düşürür.
  bool throwPending = false;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    if (throwPending) throw TypeError();
    return scheduled.values.toList();
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();

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
    scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  }

  @override
  Future<void> periodicallyShowWithDuration({
    required int id,
    required Duration repeatDurationInterval,
    required NotificationDetails notificationDetails,
    String? title,
    String? body,
    AndroidScheduleMode androidScheduleMode = AndroidScheduleMode.exact,
    String? payload,
  }) async {
    scheduled[id] = PendingNotificationRequest(id, title, body, payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlugin: ${invocation.memberName}');
}

MedicationPlan _plan(int id, {bool active = true, List<String>? times}) =>
    MedicationPlan(
      id: id,
      uuid: 'u$id',
      name: 'Vitamin D',
      dose: '1 damla',
      times: times ?? const ['09:00', '21:00'],
      active: active,
      createdAt: DateTime(2026, 1, 1),
      startDate: DateTime(2026, 1, 1),
    );

/// İlaç v2 (A4): K5 senaryoları YENİ planlayıcıya taşındı — eski günlük-tekrar
/// API'si (`syncMedicationPlans`, id = 670000 + planId*10) tasarım gereği
/// kaldırıldı (ILAC-TASARIM §3.3: doz başına tek seferlik, defterden tahsisli id).
/// Senaryolar aynı: silinen / duraklatılan planın bildirimi kalmaz (yarışta da),
/// yetim öz-onarımı komşu aralıklara dokunmaz, başka bebeğin planı korunur,
/// kaynak okunamazsa hiçbir şey değişmez.
const _lo = NotificationService.medIdLo, _hi = NotificationService.medIdHi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlugin plugin;
  late NotificationService svc;
  late MedicationScheduler sched;
  final now = DateTime(2026, 1, 10, 8, 0);

  MedSchedLoader loader(List<MedicationPlan> plans, {String baby = 'b1'}) => () async =>
      MedSchedInput(babies: [MedSchedBaby(id: baby, name: 'Ada', plans: plans, records: const [])]);

  Set<int> medIds() => {for (final id in plugin.ids) if (id >= _lo && id < _hi) id};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    plugin = _FakePlugin();
    svc = NotificationService.withPlugin(plugin);
    sched = MedicationScheduler.forTest(svc, now: () => now);
  });

  group('K5 — ilaç planı bildirimleri (v2 planlayıcı)', () {
    test('(a) plan silinince hiçbir bildirimi zamanlı kalmaz', () async {
      await sched.rebuild(loader([_plan(5)]));
      expect(medIds(), isNotEmpty);
      // Silindi (DB'de yok) — bayat liste kavramı yok: planlayıcı DB'den okur.
      await sched.rebuild(loader(const []));
      expect(medIds(), isEmpty,
          reason: 'silinen planın bildirimi bayat listeden geri gelmemeli');
    });

    test('(b) duraklatma: eski (aktif) ve yeni (pasif) yeniden kurmalar iç içe ateşlense de sonuç iptal',
        () async {
      await sched.rebuild(loader([_plan(5)]));
      expect(medIds(), isNotEmpty);
      var dbActive = true;
      Future<MedSchedInput> fromDb() async => MedSchedInput(babies: [
            MedSchedBaby(id: 'b1', name: 'Ada', plans: [_plan(5, active: dbActive)], records: const [])
          ]);
      final old = sched.rebuild(fromDb);
      dbActive = false; // kullanıcı duraklattı
      final fresh = sched.rebuild(fromDb);
      await Future.wait([old, fresh]);
      expect(medIds(), isEmpty, reason: 'son durum "duraklatıldı" → bildirim kalmamalı');
    });

    test('(b2) duraklatılmış plan tek başına da iptal edilir', () async {
      await sched.rebuild(loader([_plan(5)]));
      await sched.rebuild(loader([_plan(5, active: false)]));
      expect(medIds(), isEmpty);
    });

    test('öz-onarım: defterde olmayan ilaç bildirimi iptal edilir; eski aralık bir kez '
        "temizlenir; sağlık/slot/aile/feed id'lerine dokunulmaz", () async {
      plugin.scheduled[_lo + 777] = PendingNotificationRequest(_lo + 777, 'yetim', null, null);
      plugin.scheduled[670051] = const PendingNotificationRequest(670051, 'eski günlük', null, null);
      plugin.scheduled[669999] = const PendingNotificationRequest(669999, 'tooth', null, null);
      plugin.scheduled[700000] = const PendingNotificationRequest(700000, 'family', null, null);
      plugin.scheduled[800001] = const PendingNotificationRequest(800001, 'feed', null, null);

      await sched.rebuild(loader([_plan(5)]));

      expect(plugin.ids.contains(_lo + 777), isFalse);
      expect(plugin.ids.contains(670051), isFalse);
      expect(plugin.ids.containsAll({669999, 700000, 800001}), isTrue);
      expect(medIds(), isNotEmpty);
    });

    test('başka bebeğin aktif planı korunur (tek, global yeniden kurma)', () async {
      Future<MedSchedInput> both() async => MedSchedInput(babies: [
            MedSchedBaby(id: 'b1', name: 'Ada', plans: [_plan(5)], records: const []),
            MedSchedBaby(id: 'b2', name: 'Can', plans: [_plan(8, times: const ['10:00'])],
                records: const []),
          ]);
      await sched.rebuild(both);
      final titles = {for (final p in plugin.scheduled.values) p.title};
      expect(titles.any((t) => t!.startsWith('Ada · ')), isTrue);
      expect(titles.any((t) => t!.startsWith('Can · ')), isTrue);
    });

    test('kaynak okunamazsa hiçbir şey değişmez (yanlış iptal yok)', () async {
      await sched.rebuild(loader([_plan(5)]));
      final before = medIds();
      await sched.rebuild(() async => throw StateError('db'));
      expect(medIds(), before);
    });
  });

  group('(c) provider yenilenirken bayat liste kullanılmaz', () {
    test('invalidate sonrası: asData ESKİ listeyi taşır (risk), settledListOrNull null',
        () async {
      var calls = 0;
      final gate = Completer<void>();
      // İlk yükleme anında döner; yenileme (2. çağrı) gate açılana dek bekler.
      final p = FutureProvider<List<MedicationPlan>>((ref) async {
        calls++;
        if (calls > 1) await gate.future;
        return calls > 1 ? const <MedicationPlan>[] : [_plan(5)];
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.listen(p, (_, _) {}); // canlı tut
      await c.read(p.future);
      expect(settledListOrNull(c.read(p)), hasLength(1));

      c.invalidate(p); // sheet: plan silindi → invalidate
      final refreshing = c.read(p);
      expect(refreshing.isLoading, isTrue);
      expect(refreshing.asData?.value, isNotNull,
          reason: 'ham asData okuması bayat (silinen planlı) listeyi döndürür');
      expect(settledListOrNull(refreshing), isNull,
          reason: 'yenileme sırasında bildirim kurulmamalı');

      gate.complete();
      await c.read(p.future);
      expect(settledListOrNull(c.read(p)), isEmpty);
    });

    test('settledListOrNull: saf loading ve error için null', () {
      expect(settledListOrNull(const AsyncLoading<List<MedicationPlan>>()),
          isNull);
      expect(
          settledListOrNull(
              AsyncError<List<MedicationPlan>>('x', StackTrace.empty)),
          isNull);
    });
  });

  group('V4 — bozuk bekleyen girdi (iOS NSE isteği)', () {
    test('eklenti listesi düşse de ham listeden okunur; eski günlük id\'ler ve yetim temizlenir',
        () async {
      plugin.scheduled[_lo + 777] = PendingNotificationRequest(_lo + 777, 'yetim', null, null);
      plugin.scheduled[670051] = const PendingNotificationRequest(670051, 'eski günlük', null, null);
      plugin.scheduled[800001] = const PendingNotificationRequest(800001, 'feed', null, null);
      plugin.throwPending = true;
      final svc2 = NotificationService.withPlugin(plugin,
          rawPending: () async => [
                {'id': null, 'title': 'NSE beslenme'}, // NotificationId'siz istek
                for (final id in plugin.scheduled.keys) {'id': id},
              ]);
      final s2 = MedicationScheduler.forTest(svc2, now: () => now);
      expect(await svc2.pendingIdsIn(_lo, _hi), {_lo + 777});
      await s2.rebuild(loader([_plan(5)]));
      expect(plugin.ids.contains(670051), isFalse, reason: 'eski günlük tekrar temizlenmeli');
      expect(plugin.ids.contains(_lo + 777), isFalse, reason: 'yetim temizlenmeli');
      expect(plugin.ids.contains(800001), isTrue);
      expect(medIds(), isNotEmpty);
    });

    test('bekleyen hiç okunamasa da eski id\'ler yerel planlardan doğrudan iptal edilir', () async {
      plugin.scheduled[670052] = const PendingNotificationRequest(670052, 'eski günlük', null, null);
      plugin.throwPending = true;
      final svc2 = NotificationService.withPlugin(plugin, rawPending: () async => throw StateError('x'));
      await MedicationScheduler.forTest(svc2, now: () => now).rebuild(loader([_plan(5)]));
      expect(plugin.ids.contains(670052), isFalse);
    });
  });
}
