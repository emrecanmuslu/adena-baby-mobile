import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/babies/notification_sync.dart';

/// ILAC-INCELEME-2 V23 (M17): saat dilimi değişince yalnız ilaçlar değil, duvar
/// saatine bağlı diğer günlük hatırlatıcı senkronları da yeniden kurulmalı.
void main() {
  test('saat dilimi değişti → epoch artar (senkronlar yeniden kurar); değişmedi → artmaz',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    void bump() => c.read(timezoneEpochProvider.notifier).bump();
    expect(c.read(timezoneEpochProvider), 0);
    expect(await refreshTimezoneAndBump(() async => false, bump), isFalse);
    expect(c.read(timezoneEpochProvider), 0);
    expect(await refreshTimezoneAndBump(() async => true, bump), isTrue);
    expect(c.read(timezoneEpochProvider), 1);
  });
}
