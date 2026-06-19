import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/units.dart';

/// Units: kanonik saklama (ml/kg/cm/°C) ile tercih birimi (oz/lb/in/°F) arası
/// dönüşüm + formatlama. Dönüşüm/format metotları saf — açık kurucu ile test
/// edilir (cihaz bölgesine bağlı değil).

const _metric = Units(); // ml/kg/cm/C
const _imperial = Units(volume: 'oz', weight: 'lb', length: 'in', temp: 'F');

void main() {
  // fromMap → deviceDefault → PlatformDispatcher erişir; binding gerekli.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Units kurucu varsayılanları', () {
    test('varsayılan = metrik', () {
      const u = Units();
      expect(u.volume, 'ml');
      expect(u.weight, 'kg');
      expect(u.length, 'cm');
      expect(u.temp, 'C');
    });
  });

  group('etiketler', () {
    test('metrik etiketleri', () {
      expect(_metric.volumeLabel, 'ml');
      expect(_metric.weightLabel, 'kg');
      expect(_metric.lengthLabel, 'cm');
    });

    test('imperial etiketleri', () {
      expect(_imperial.volumeLabel, 'oz');
      expect(_imperial.weightLabel, 'lb');
      expect(_imperial.lengthLabel, 'in');
    });

    test('bilinmeyen birim → metrik etikete düşer', () {
      const u = Units(volume: 'xx', weight: 'yy', length: 'zz');
      expect(u.volumeLabel, 'ml');
      expect(u.weightLabel, 'kg');
      expect(u.lengthLabel, 'cm');
    });
  });

  group('giriş → kanonik (metrik: kimlik)', () {
    test('metrikte değer değişmez', () {
      expect(_metric.volumeToCanonical(120), 120);
      expect(_metric.weightToCanonical(5.2), 5.2);
      expect(_metric.lengthToCanonical(50), 50);
    });
  });

  group('giriş → kanonik (imperial dönüşümü)', () {
    test('oz → ml (×29.5735)', () {
      expect(_imperial.volumeToCanonical(1), closeTo(29.5735, 1e-6));
      expect(_imperial.volumeToCanonical(4), closeTo(118.294, 1e-3));
    });

    test('lb → kg (×0.453592)', () {
      expect(_imperial.weightToCanonical(1), closeTo(0.453592, 1e-6));
      expect(_imperial.weightToCanonical(10), closeTo(4.53592, 1e-5));
    });

    test('in → cm (×2.54)', () {
      expect(_imperial.lengthToCanonical(1), closeTo(2.54, 1e-9));
      expect(_imperial.lengthToCanonical(20), closeTo(50.8, 1e-9));
    });
  });

  group('kanonik → tercih birimi', () {
    test('metrikte kimlik (num → double)', () {
      expect(_metric.volumeFromCanonical(120), 120.0);
      expect(_metric.weightFromCanonical(5), 5.0);
      expect(_metric.lengthFromCanonical(50), 50.0);
    });

    test('ml → oz', () {
      expect(_imperial.volumeFromCanonical(29.5735), closeTo(1.0, 1e-6));
    });

    test('kg → lb', () {
      expect(_imperial.weightFromCanonical(0.453592), closeTo(1.0, 1e-6));
    });

    test('cm → in', () {
      expect(_imperial.lengthFromCanonical(2.54), closeTo(1.0, 1e-9));
    });

    test('gidiş-dönüş kayıpsız (oz)', () {
      final canon = _imperial.volumeToCanonical(3.5);
      expect(_imperial.volumeFromCanonical(canon), closeTo(3.5, 1e-9));
    });
  });

  group('formatlı gösterim', () {
    test('fmtVolume metrik → tam sayıya yuvarlar + ml', () {
      expect(_metric.fmtVolume(120), '120 ml');
      expect(_metric.fmtVolume(119.6), '120 ml');
    });

    test('fmtVolume imperial → 1 ondalık + oz', () {
      // 29.5735 ml = 1.0 oz
      expect(_imperial.fmtVolume(29.5735), '1.0 oz');
    });

    test('fmtWeight metrik → 2 ondalık + kg', () {
      expect(_metric.fmtWeight(5.2), '5.20 kg');
    });

    test('fmtWeight imperial → 1 ondalık + lb', () {
      expect(_imperial.fmtWeight(0.453592), '1.0 lb');
    });

    test('fmtLength → 1 ondalık + birim', () {
      expect(_metric.fmtLength(50), '50.0 cm');
      expect(_imperial.fmtLength(2.54), '1.0 in');
    });
  });

  group('editValue', () {
    test('tam sayı değer → ondalıksız', () {
      expect(_metric.editValue(5.0), '5');
      expect(_metric.editValue(120.0), '120');
    });

    test('ondalık değer → 2 hane', () {
      expect(_metric.editValue(5.25), '5.25');
    });

    test('.00 ile biten → tam sayıya indirilir', () {
      expect(_metric.editValue(5.004), '5'); // toStringAsFixed(2) = "5.00"
    });

    test('decimal:true ile tam sayı bile ondalık zorlanır', () {
      // v == roundToDouble ama decimal=true → ilk dal atlanır, "5.00" → "5"
      // (".00" kontrolü yine tam sayıya indirir)
      expect(_metric.editValue(5.0, decimal: true), '5');
    });
  });

  group('serileştirme', () {
    test('toMap / fromMap gidiş-dönüş', () {
      final m = _imperial.toMap();
      expect(m, {'volume': 'oz', 'weight': 'lb', 'length': 'in', 'temp': 'F'});
      final back = Units.fromMap(m);
      expect(back.volume, 'oz');
      expect(back.weight, 'lb');
      expect(back.length, 'in');
      expect(back.temp, 'F');
    });

    test('copyWith yalnız verilen alanı değiştirir', () {
      final u = _metric.copyWith(weight: 'lb');
      expect(u.weight, 'lb');
      expect(u.volume, 'ml');
      expect(u.length, 'cm');
      expect(u.temp, 'C');
    });
  });
}
