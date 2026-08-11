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
}
