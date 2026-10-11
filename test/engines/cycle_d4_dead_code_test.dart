import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ADET-INCELEME D4: kullanılmayan `phaseLabel` / `phaseSelfCare` (bebek
/// varsayan "bebeğin uyuduğunda sen de uzan" gibi metinler) kaldırıldı.
void main() {
  test('cycle_widgets ölü faz öz-bakım kodu içermez', () {
    final src = File('lib/features/cycle/cycle_widgets.dart').readAsStringSync();
    expect(src, isNot(contains('phaseSelfCare')));
    expect(src, isNot(contains('phaseLabel')));
    expect(src, isNot(contains('bebeğin uyuduğunda')));
  });
}
