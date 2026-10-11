import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:adena_baby/core/notification_service.dart';

class _NoopPlugin implements FlutterLocalNotificationsPlugin {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('NoopPlugin: ${i.memberName}');
}

/// Gerçek platform deposu gibi asenkron: `getAll` çağrı anındaki anlık görüntüyü
/// gecikmeyle döndürür, `setValue` gecikmeyle yazar. İki `reload→oku→yaz`
/// birbirine girince (FCM açılış kuyruğu, J7) ikisi de aynı sayacı okur.
class _DelayedStore extends SharedPreferencesStorePlatform {
  final Map<String, Object> data = {};
  Future<void> _lag() => Future<void>.delayed(const Duration(milliseconds: 5));
  @override
  Future<Map<String, Object>> getAll() async {
    final snap = Map<String, Object>.of(data);
    await _lag();
    return snap;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await _lag();
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

/// INCELEME-2 J7 — `nextActivityId` (reload → oku → yaz) atomik değildi; FCM
/// arka plan servisi isolate açılırken kuyruktaki mesajları eşzamanlı sevk
/// ettiğinden iki aile bildirimi aynı id'yi alıp üst üste yazılıyordu. Artık
/// isolate-içi Future zinciriyle serileştirilir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eşzamanlı iki çağrı → farklı id', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _DelayedStore();
    final svc = NotificationService.withPlugin(_NoopPlugin());

    final ids = await Future.wait([svc.nextActivityId(), svc.nextActivityId()]);
    expect(ids[0], isNot(ids[1]), reason: 'üst üste yazma: aynı id');
    expect(ids.every((id) => id >= 700000 && id < 700050), isTrue);
  });

  test('eşzamanlı 5 çağrı → 5 benzersiz id, sayaç kalıcı', () async {
    SharedPreferences.setMockInitialValues({});
    final store = _DelayedStore();
    SharedPreferencesStorePlatform.instance = store;
    final svc = NotificationService.withPlugin(_NoopPlugin());

    final ids = await Future.wait(List.generate(5, (_) => svc.nextActivityId()));
    expect(ids.toSet(), hasLength(5));
    expect(store.data['flutter.notif_activity_seq_v1'], 4);
  });
}
