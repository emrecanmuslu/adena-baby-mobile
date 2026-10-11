import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/notification_service.dart';

class _NoopPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('NoopPlugin: ${i.memberName}');
}

/// I6 (INCELEME.md) — aile etkinlik bildirimi id'si: zaman tabanlı halka
/// (500 ms periyot, ~%2 çarpışma) yerine prefs'te kalıcı sayaç; 700000..700049
/// döngüsel; ardışık çağrılar farklı id üretir; aralık dışına çıkmaz.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ardışık 60 çağrı: ilk 50 benzersiz, 51. başa döner, hepsi aralıkta', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = NotificationService.withPlugin(_NoopPlugin());
    final ids = <int>[];
    for (var i = 0; i < 60; i++) {
      ids.add(await svc.nextActivityId());
    }
    expect(ids.take(50).toSet(), hasLength(50));
    expect(ids[50], ids[0], reason: '50\'lik halka');
    for (var i = 1; i < ids.length; i++) {
      expect(ids[i], isNot(ids[i - 1]), reason: 'ardışık çağrı aynı id üretmemeli');
    }
    expect(ids.every((id) => id >= 700000 && id < 700000 + NotificationService.activityIdRing),
        isTrue);
  });

  test('sayaç prefs\'te kalıcı: başka isolate/süreç 49\'da bıraktıysa 700000\'a sarar',
      () async {
    SharedPreferences.setMockInitialValues({'notif_activity_seq_v1': 49});
    final svc = NotificationService.withPlugin(_NoopPlugin());
    expect(await svc.nextActivityId(), 700000);
    expect((await SharedPreferences.getInstance()).getInt('notif_activity_seq_v1'), 0);
  });
}
