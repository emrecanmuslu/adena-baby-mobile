import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/models/milestone.dart';

/// milestoneAgeLabel saf etiket testleri. Varsayılan locale 'tr' → trp() kaynak
/// metni döndürüp yer-tutucuyu değerle değiştirir, ağ/bundle gerekmez.

void main() {
  group('milestoneAgeLabel', () {
    test('12 ay altı → "{n}. ay"', () {
      expect(milestoneAgeLabel(0), '0. ay');
      expect(milestoneAgeLabel(2), '2. ay');
      expect(milestoneAgeLabel(11), '11. ay');
    });

    test('tam yıl katı → "{n} yaş"', () {
      expect(milestoneAgeLabel(12), '1 yaş');
      expect(milestoneAgeLabel(24), '2 yaş');
      expect(milestoneAgeLabel(60), '5 yaş');
    });

    test('yıl katı olmayan 12+ → "{y}.5 yaş" (yarım yıl konvansiyonu)', () {
      expect(milestoneAgeLabel(18), '1.5 yaş');
      expect(milestoneAgeLabel(30), '2.5 yaş');
    });
  });

  group('milestoneCategory', () {
    test('bilinen kategoriler renk + etiket döndürür', () {
      for (final key in ['motor', 'social', 'language', 'cognitive']) {
        final c = milestoneCategory(key);
        expect(c.label(), isNotEmpty);
      }
    });
    test('bilinmeyen kategori "Diğer" e düşer', () {
      expect(milestoneCategory('zzz').label(), 'Diğer');
    });
  });
}
