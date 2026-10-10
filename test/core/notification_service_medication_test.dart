import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart';

import 'package:adena_baby/core/notification_service.dart';
import 'package:adena_baby/features/babies/notification_sync.dart';
import 'package:adena_baby/models/medication_plan.dart';

/// K5 (BULGULAR.md): silinen/duraklatılan ilaç planının bildirimleri bayat
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

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async =>
      scheduled.values.toList();

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
      name: 'Vitamin D',
      dose: '1 damla',
      times: times ?? const ['09:00', '21:00'],
      active: active,
      createdAt: DateTime(2026, 1, 1),
    );

/// Plan 5'in id'leri: 670000 + 5*10 + idx.
Set<int> _idsOf(int planId, int doses) =>
    {for (var i = 0; i < doses; i++) 670000 + (planId % 1000) * 10 + i};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlugin plugin;
  late NotificationService svc;

  setUp(() {
    plugin = _FakePlugin();
    svc = NotificationService.withPlugin(plugin);
  });

  group('K5 — ilaç planı bildirimleri', () {
    test('(a) plan silinince hiçbir bildirimi zamanlı kalmaz', () async {
      // 1) Plan aktifken kuruldu.
      await svc.syncMedicationPlans([_plan(5)],
          enabled: true, activePlanIds: () async => {5});
      expect(plugin.ids, _idsOf(5, 2));

      // 2) Sheet: DB'den sildi + açık iptal + invalidate. Widget, yenileme
      //    sırasında ESKİ (planı hâlâ içeren) listeyle yeniden build olur.
      await svc.cancelMedicationPlan(5);
      await svc.syncMedicationPlans([_plan(5)],
          enabled: true, activePlanIds: () async => {}); // DB: plan yok
      // 3) Yeni liste gelir (plan yok).
      await svc.syncMedicationPlans([],
          enabled: true, activePlanIds: () async => {});

      expect(plugin.ids, isEmpty,
          reason: 'silinen planın bildirimi bayat listeden geri gelmemeli');
    });

    test('(b) duraklatma: eski (aktif) ve yeni (pasif) çağrılar iç içe bitse de sonuç iptal',
        () async {
      await svc.syncMedicationPlans([_plan(5)],
          enabled: true, activePlanIds: () async => {5});
      expect(plugin.ids, _idsOf(5, 2));

      // Eski rebuild'in çağrısı (aktif) ile yeni rebuild'in çağrısı (pasif)
      // beklenmeden art arda ateşlenir — await zincirleri iç içe geçer.
      final old = svc.syncMedicationPlans([_plan(5)],
          enabled: true, activePlanIds: () async => {});
      final fresh = svc.syncMedicationPlans([_plan(5, active: false)],
          enabled: true, activePlanIds: () async => {});
      await Future.wait([old, fresh]);

      expect(plugin.ids, isEmpty,
          reason: 'son durum "duraklatıldı" → bildirim kalmamalı');
    });

    test('(b2) duraklatılmış plan tek başına da iptal edilir', () async {
      await svc.syncMedicationPlans([_plan(5)],
          enabled: true, activePlanIds: () async => {5});
      await svc.syncMedicationPlans([_plan(5, active: false)],
          enabled: true, activePlanIds: () async => {});
      expect(plugin.ids, isEmpty);
    });

    test('öz-onarım: hiçbir aktif plana ait olmayan ilaç bildirimi iptal edilir, '
        'sağlık/slot ve feed id\'lerine dokunulmaz', () async {
      // Yetim: plan 7 (DB'de yok). Komşu aralıklar: diş 660000+slot, aile 700000.
      for (final id in _idsOf(7, 3)) {
        plugin.scheduled[id] = PendingNotificationRequest(id, 'yetim', null, null);
      }
      plugin.scheduled[669999] =
          const PendingNotificationRequest(669999, 'tooth', null, null);
      plugin.scheduled[700000] =
          const PendingNotificationRequest(700000, 'family', null, null);
      plugin.scheduled[800001] =
          const PendingNotificationRequest(800001, 'feed', null, null);

      await svc.syncMedicationPlans([_plan(5)],
          enabled: true, activePlanIds: () async => {5});

      expect(plugin.ids, {..._idsOf(5, 2), 669999, 700000, 800001});
    });

    test('başka bebeğin aktif planı (listede yok) korunur', () async {
      await svc.syncMedicationPlans([_plan(5)],
          enabled: true, activePlanIds: () async => {5, 8});
      await svc.syncMedicationPlans([_plan(8, times: const ['10:00'])],
          enabled: true, activePlanIds: () async => {5, 8});
      expect(plugin.ids, {..._idsOf(5, 2), ..._idsOf(8, 1)});
    });

    test('aktif plan kaynağı okunamazsa yetim temizliği atlanır, listedekiler yine kurulur/iptal edilir',
        () async {
      plugin.scheduled[670070] =
          const PendingNotificationRequest(670070, 'bilinmeyen', null, null);
      await svc.syncMedicationPlans([_plan(5), _plan(6, active: false)],
          enabled: true, activePlanIds: () async => throw StateError('db'));
      expect(plugin.ids, {..._idsOf(5, 2), 670070});
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
}
