import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/push_service.dart';

/// O17 — push/NSE çapası "gelecek tarih eşiği": eşin ileri tarihli girdiği
/// beslenme kaydı widget'ı/hatırlatıcıyı günler sonrasına kurmasın.
void main() {
  final now = DateTime(2026, 6, 1, 12);

  test('geçmiş ve 1 saate kadar ileri çapa makul', () {
    expect(feedAnchorPlausible(now.subtract(const Duration(hours: 3)), now: now), isTrue);
    expect(feedAnchorPlausible(now.add(const Duration(minutes: 59)), now: now), isTrue);
  });

  test('1 saatten ileri çapa reddedilir', () {
    expect(feedAnchorPlausible(now.add(const Duration(hours: 1, minutes: 1)), now: now), isFalse);
    expect(feedAnchorPlausible(now.add(const Duration(days: 2)), now: now), isFalse);
  });
}
