import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/modal_gate.dart';

/// [ModalGate] — kendiliğinden açılan modallar arası öncelik kapısı.
void main() {
  setUp(ModalGate.resetForTest);

  test('başlangıçta kapı açık', () {
    expect(ModalGate.isBlocked, isFalse);
  });

  test('acquire kapatır, release açar', () {
    ModalGate.acquire();
    expect(ModalGate.isBlocked, isTrue);
    ModalGate.release();
    expect(ModalGate.isBlocked, isFalse);
  });

  test('iç içe tutuşlarda son bırakışta açılır', () {
    ModalGate.acquire();
    ModalGate.acquire();
    ModalGate.release();
    expect(ModalGate.isBlocked, isTrue, reason: 'bir tutuş hâlâ sürüyor');
    ModalGate.release();
    expect(ModalGate.isBlocked, isFalse);
  });

  test('fazladan release sayacı eksiye düşürmez', () {
    ModalGate.release();
    ModalGate.release();
    expect(ModalGate.isBlocked, isFalse);
    // Eksiye düşseydi bir sonraki acquire kapıyı kapatamazdı:
    ModalGate.acquire();
    expect(ModalGate.isBlocked, isTrue);
  });

  test('durum değişince dinleyiciye haber verir', () {
    var calls = 0;
    void listener() => calls++;
    ModalGate.listenable.addListener(listener);
    addTearDown(() => ModalGate.listenable.removeListener(listener));

    ModalGate.acquire();
    ModalGate.release();
    expect(calls, 2);
  });

  group('SystemPromptGate', () {
    setUp(() {
      SystemPromptGate.resetForTest();
      SystemPromptGate.settle = Duration.zero;
    });
    tearDown(SystemPromptGate.resetForTest);

    test('asıl ekrana ulaşılmadan izin penceresi açılmaz', () async {
      var done = false;
      unawaited(SystemPromptGate.whenClear().then((_) => done = true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(done, isFalse, reason: 'onboarding sırasında sorulmamalı');

      SystemPromptGate.markAppReady();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(done, isTrue);
    });

    test('paywall/tur kapıyı tutarken bekler, bırakınca açılır', () async {
      SystemPromptGate.markAppReady();
      ModalGate.acquire(); // ör. Premium Karşılama açık
      var done = false;
      unawaited(SystemPromptGate.whenClear().then((_) => done = true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(done, isFalse, reason: 'paywall üstüne binmemeli');

      ModalGate.release();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(done, isTrue);
    });

    test('kapı bırakılıp yerleşme süresinde yeniden tutulursa (tur) beklemeye devam eder',
        () async {
      SystemPromptGate.settle = const Duration(milliseconds: 30);
      SystemPromptGate.markAppReady();
      ModalGate.acquire(); // paywall
      var done = false;
      unawaited(SystemPromptGate.whenClear().then((_) => done = true));

      ModalGate.release(); // paywall kapandı…
      ModalGate.acquire(); // …hemen ardından tur açıldı
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(done, isFalse, reason: 'turun üstüne binmemeli');

      ModalGate.release(); // tur kapandı
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(done, isTrue);
    });
  });
}
