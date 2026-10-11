import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/in_flight_guard.dart';

/// O8 (UI kısmı): "Adet başlat" gibi düğmelere hızlı çift dokunuşta gövde
/// yalnız bir kez çalışmalı; iş bitince (başarı/hata) yeniden çalışabilmeli.
void main() {
  test('sürerken ikinci çağrı atlanır, gövde bir kez çalışır', () async {
    final g = InFlightGuard();
    final gate = Completer<void>();
    var calls = 0;
    final first = g.run(() async {
      calls++;
      await gate.future;
    });
    expect(g.busy, isTrue);
    final second = await g.run(() async => calls++);
    expect(second, isFalse);
    gate.complete();
    expect(await first, isTrue);
    expect(calls, 1);
    expect(g.busy, isFalse);
  });

  test('iş bitince yeniden çalışır', () async {
    final g = InFlightGuard();
    var calls = 0;
    expect(await g.run(() async => calls++), isTrue);
    expect(await g.run(() async => calls++), isTrue);
    expect(calls, 2);
  });

  test('gövde hata fırlatsa da kilit açılır ve hata yukarı geçer', () async {
    final g = InFlightGuard();
    await expectLater(g.run(() async => throw StateError('x')), throwsStateError);
    expect(g.busy, isFalse);
    expect(await g.run(() async {}), isTrue);
  });
}
