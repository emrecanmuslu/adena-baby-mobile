import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/push_service.dart';

/// D4 — `inactive` (bildirim paneli aşağı çekilmiş, iOS app switcher) ön plan
/// sayılır: push yalnız in-app banner, OS bildirimi YOK (çift görünmesin).
void main() {
  test('resumed ve inactive ön plan; paused/hidden/detached değil', () {
    expect(isForegroundLifecycle(AppLifecycleState.resumed), isTrue);
    expect(isForegroundLifecycle(AppLifecycleState.inactive), isTrue);
    expect(isForegroundLifecycle(AppLifecycleState.paused), isFalse);
    expect(isForegroundLifecycle(AppLifecycleState.hidden), isFalse);
    expect(isForegroundLifecycle(AppLifecycleState.detached), isFalse);
  });
}
