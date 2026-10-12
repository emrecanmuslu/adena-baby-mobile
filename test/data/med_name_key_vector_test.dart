import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/medication/med_names.dart';

/// ILAC-INCELEME-2 V26: plan adı katlaması mobil ↔ backend BİREBİR aynı. Ortak
/// vektör kardeş repoda (`../api/apps/health/med_name_vectors.json`); Python
/// testi aynı dosyayı okur. Dosya yoksa (CI'da api checkout edilmemiş) atlanır.
void main() {
  final f = File('../api/apps/health/med_name_vectors.json');
  test('ortak vektör: medNameKey backend med_name_key ile aynı', () {
    if (!f.existsSync()) {
      markTestSkipped('api repo yok — ortak vektör atlandı');
      return;
    }
    final vectors = (jsonDecode(f.readAsStringSync()) as Map)['vectors'] as List;
    expect(vectors, isNotEmpty);
    for (final v in vectors) {
      final raw = (v as List)[0] as String, expected = v[1] as String;
      expect(medNameKey(raw), expected, reason: jsonEncode(raw));
    }
  });
}
