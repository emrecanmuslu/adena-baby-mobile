import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/core/notif_soft_ask.dart';

/// Bildirim ön-izni: hiç sorulmadıysa sorulur; "Şimdi değil" sonrası 7 gün
/// susar; kabul edildiyse bir daha sorulmaz.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final t0 = DateTime(2026, 10, 25, 12);

  test('hiç sorulmadıysa sorulabilir', () async {
    expect(await NotifSoftAsk.mayAskAgain(now: t0), isTrue);
  });

  test('reddedilince 7 gün sorulmaz, sonra sorulabilir', () async {
    await NotifSoftAsk.record(accepted: false, now: t0);
    expect(await NotifSoftAsk.mayAskAgain(now: t0.add(const Duration(days: 6))),
        isFalse);
    expect(await NotifSoftAsk.mayAskAgain(now: t0.add(const Duration(days: 7))),
        isTrue);
  });

  test('kabul edilince bir daha sorulmaz', () async {
    await NotifSoftAsk.record(accepted: true, now: t0);
    expect(await NotifSoftAsk.accepted(), isTrue);
    expect(await NotifSoftAsk.mayAskAgain(now: t0.add(const Duration(days: 30))),
        isFalse);
  });
}
