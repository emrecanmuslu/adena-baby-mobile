import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ADET-INCELEME D2: "Tahmini doğum" çevirileri her dilde "tahmini" anlamını
/// korur (EN'de "Due date" idi). Kaynak `../api/apps/translations/data/*.json`
/// (kardeş repo); yoksa translation_keys_test ile aynı kural: yerelde atla.
void main() {
  final dir = Directory('${Directory.current.path}/../api/apps/translations/data');
  const want = {
    'en': 'Estimated',
    'es': 'probable',
    'fr': 'estimée',
    'ar': 'التقديري',
    'hi': 'अनुमानित',
    'zh': '估计',
  };
  test('"Tahmini doğum" ve "Tahmini doğum: {d}" tahmin anlamında', () {
    if (!dir.existsSync()) {
      final env = Platform.environment;
      if (env['REQUIRE_API_TRANSLATIONS'] == '1' || env['CI'] == 'true') {
        fail('api çeviri JSON\'ları yok: ${dir.path}');
      }
      return;
    }
    want.forEach((loc, needle) {
      final m = (jsonDecode(File('${dir.path}/$loc.json').readAsStringSync()) as Map)
          .cast<String, dynamic>();
      for (final k in ['Tahmini doğum', 'Tahmini doğum: {d}']) {
        expect(m[k], contains(needle), reason: '$loc: $k → ${m[k]}');
      }
    });
  });
}
