import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/data/local_prefs.dart';
import 'package:adena_baby/data/local_session.dart';

/// D9 — misafire girişte prefs yazımı düşse bile kimlik BELLEKTE kurulur;
/// aksi hâlde misafir bebekleri account_id=null ile görünmez olup onboarding
/// döngüsüne girerdi. Bu testte SharedPreferences platformu BİLEREK mock'lanmaz
/// → `getInstance()` MissingPluginException ile düşer (gerçek "prefs yok" hâli).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
    LocalPrefs.resetForTests();
    LocalSession.resetForTests();
  });

  test('prefs açılamazken enterGuest: userId üretilir, kapsam ona bağlanır, misafir açık',
      () async {
    expect(LocalSession.userId, isEmpty);
    await LocalSession.enterGuest();
    expect(LocalSession.userId, isNotEmpty, reason: 'kimlik bellekte kurulmalı');
    expect(LocalSession.activeAccountId, LocalSession.userId,
        reason: 'misafir yerel veri kapsamı kimliğe bağlı');
    expect(LocalSession.guest, isTrue);
  });
}
