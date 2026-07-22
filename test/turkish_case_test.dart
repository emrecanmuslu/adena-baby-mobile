import 'package:adena_baby/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurkishCase', () {
    test('TR locale: i→İ ve ı→I doğru eşlenir', () {
      I18n.instance.apply('tr', const {});
      expect('zirve'.toUpperCaseTr(), 'ZİRVE');
      expect('ışık'.toUpperCaseTr(), 'IŞIK');
      expect('Buradasın'.toUpperCaseTr(), 'BURADASIN');
      expect('ZİRVE'.toLowerCaseTr(), 'zirve');
      expect('IŞIK'.toLowerCaseTr(), 'ışık');
    });

    test('EN locale: standart dönüşüm (i→I)', () {
      I18n.instance.apply('en', const {});
      expect('time'.toUpperCaseTr(), 'TIME');
      expect('TIME'.toLowerCaseTr(), 'time');
      I18n.instance.apply('tr', const {}); // diğer testler için geri al
    });
  });
}
