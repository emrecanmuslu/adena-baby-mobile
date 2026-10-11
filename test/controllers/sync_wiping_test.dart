import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/records/record_controller.dart';

/// K3 (BULGULAR.md): `SyncService.wiping` statik bayrağı "yerel verileri sil"
/// sırasında sync'in yeniden ekleme yapmasını önler. Bayrak hiçbir yolda false'a
/// dönmüyordu → wipe'tan sonra (RestartWidget süreci öldürmediği için) sync
/// süreç ömrü boyunca sessizce kapalı kalıyordu. Silme işi `SyncService.whileWiping`
/// ile sarılır: gövde başarılı da bitse hata da fırlatsa bayrak sıfırlanır.
void main() {
  setUp(() => SyncService.wiping = false);
  tearDown(() => SyncService.wiping = false);

  test('whileWiping: gövde çalışırken bayrak true, bitince false', () async {
    bool? seenDuring;
    await SyncService.whileWiping(() async {
      seenDuring = SyncService.wiping;
    });
    expect(seenDuring, isTrue, reason: 'silme sırasında sync durmalı');
    expect(SyncService.wiping, isFalse, reason: 'silme bitince sync açılmalı');
  });

  test('whileWiping: gövde hata fırlatsa da bayrak false\'a döner', () async {
    await expectLater(
      SyncService.whileWiping(() async => throw StateError('db')),
      throwsStateError,
    );
    expect(SyncService.wiping, isFalse,
        reason: 'wipe patlasa bile sync kalıcı kapalı kalmamalı');
  });

  test('whileWiping: gövdenin dönüş değerini geçirir', () async {
    final r = await SyncService.whileWiping(() async => 42);
    expect(r, 42);
  });
}
