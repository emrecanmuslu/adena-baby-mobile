import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_widgets.dart';
import 'translation_keys_test.dart' as tk;

/// Düzeltme turu 2 — N3: kırmızı bayrak çip metinleri sabit anahtarlı
/// `tr('…')` çağrılarıyla yazılır → translation_keys_test tarayıcısı bunları
/// görür (değişkenle `tr(s.$2)` geçilince görmüyordu).
void main() {
  test('kırmızı bayrak etiketleri çeviri taramasında', () {
    final keys = tk.scanKeys(Directory('lib')).keys;
    for (final k in [
      'Saatte bir ya da daha sık pedi dolduran kanama',
      'Büyük pıhtılar',
      'Yoğun kanamayla birlikte baş dönmesi, bayılma hissi ya da çarpıntı',
      '38°C ve üzeri ateş',
      'Kötü kokulu akıntı',
      'Şiddetli karın/kasık ağrısı',
      'Azalmış kanamanın yeniden parlak kırmızı ve yoğun hale gelmesi',
      'Kötü kokulu akıntı + ateş',
    ]) {
      expect(keys, contains(k), reason: k);
    }
  });

  test('her bayrak anahtarının etiketi var (anahtarın kendisi değil)', () {
    for (final k in [...cycleRedFlagKeys, 'rf_odor_fever']) {
      expect(redFlagLabel(k), isNot(k));
    }
  });
}
