import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/models/milestone.dart';
import 'package:adena_baby/models/tooth.dart';
import 'package:adena_baby/models/vaccine.dart';
import 'package:adena_baby/models/symptom.dart';
import 'package:adena_baby/data/health_catalog.dart';

void main() {
  // Local-first: modeller artık katalog (içerik) + durum (yerel) birleşiminden
  // kurulur; sunucu JSON'undan değil. Katalog kalemleri fromJson ile okunur.

  group('MilestoneCatalogItem.fromJson', () {
    test('tam payload okunur', () {
      final m = MilestoneCatalogItem.fromJson({
        'key': 'first_smile',
        'category': 'social',
        'title': 'İlk gülümseme',
        'description': 'açıklama',
        'tip': 'ipucu',
        'month': 2,
      });
      expect(m.key, 'first_smile');
      expect(m.category, 'social');
      expect(m.title, 'İlk gülümseme');
      expect(m.description, 'açıklama');
      expect(m.tip, 'ipucu');
      expect(m.month, 2);
    });

    test('eksik alanlar varsayılana düşer', () {
      final m = MilestoneCatalogItem.fromJson({});
      expect(m.key, '');
      expect(m.category, 'motor');
      expect(m.title, '');
      expect(m.month, 0);
    });
  });

  group('milestoneAgeLabel', () {
    test('12 aydan küçük → "n. ay"', () {
      expect(milestoneAgeLabel(2), '2. ay');
    });
    test('tam yıl → "n yaş"', () {
      expect(milestoneAgeLabel(12), '1 yaş');
      expect(milestoneAgeLabel(24), '2 yaş');
    });
    test('ara değer → ".5 yaş"', () {
      expect(milestoneAgeLabel(18), '1.5 yaş');
    });
  });

  group('Tooth model + getters', () {
    test('ToothCatalogItem.fromJson tam payload', () {
      final t = ToothCatalogItem.fromJson({
        'key': 'ul1',
        'jaw': 'upper',
        'side': 'right',
        'position': 2,
        'name': 'Yan kesici',
        'typical_month': 10,
      });
      expect(t.key, 'ul1');
      expect(t.jaw, 'upper');
      expect(t.position, 2);
      expect(t.typicalMonth, 10);
    });

    test('isUpper jaw değerine göre', () {
      expect(_tooth(jaw: 'upper').isUpper, isTrue);
      expect(_tooth(jaw: 'lower').isUpper, isFalse);
    });

    test('positionLabel üst/alt + sağ/sol', () {
      expect(_tooth(jaw: 'upper', side: 'right').positionLabel, 'Üst sağ');
      expect(_tooth(jaw: 'lower', side: 'left').positionLabel, 'Alt sol');
    });
  });

  group('Vaccine isOverdue', () {
    test('VaccineCatalogItem.fromJson key fallback ad', () {
      final v = VaccineCatalogItem.fromJson({'name': 'Hepatit B', 'months': 0});
      expect(v.key, 'Hepatit B');
      expect(v.months, 0);
    });

    test('isOverdue: yapılmadı + geçmiş tarih → true', () {
      final v = Vaccine(
          key: 'x', name: 'x', dueDate: DateTime(2000, 1, 1), done: false);
      expect(v.isOverdue, isTrue);
    });

    test('isOverdue: yapıldıysa her zaman false', () {
      final v = Vaccine(
          key: 'x', name: 'x', dueDate: DateTime(2000, 1, 1), done: true);
      expect(v.isOverdue, isFalse);
    });

    test('isOverdue: gelecekteki tarih → false', () {
      final v = Vaccine(
          key: 'x',
          name: 'x',
          dueDate: DateTime.now().add(const Duration(days: 30)),
          done: false);
      expect(v.isOverdue, isFalse);
    });
  });

  group('SymptomSeverity.fromString', () {
    test('bilinen değerler', () {
      expect(SymptomSeverity.fromString('mild'), SymptomSeverity.mild);
      expect(SymptomSeverity.fromString('moderate'), SymptomSeverity.moderate);
      expect(SymptomSeverity.fromString('severe'), SymptomSeverity.severe);
    });
    test('bilinmeyen/null → moderate (fallback)', () {
      expect(SymptomSeverity.fromString('çok'), SymptomSeverity.moderate);
      expect(SymptomSeverity.fromString(null), SymptomSeverity.moderate);
    });
  });

  group('symptomByKey katalog', () {
    test('bilinen anahtar bulunur', () {
      final s = symptomByKey('cough');
      expect(s, isNotNull);
      expect(s!.key, 'cough');
      expect(s.emoji, '😷');
    });
    test('null/bilinmeyen anahtar → null', () {
      expect(symptomByKey(null), isNull);
      expect(symptomByKey('uydurma'), isNull);
    });
    test('label tr default lokalde kaynak metni döner', () {
      expect(symptomByKey('cough')!.label, 'Öksürük');
    });
  });
}

Tooth _tooth({required String jaw, String side = 'left'}) => Tooth(
      key: 'k',
      jaw: jaw,
      side: side,
      position: 1,
      name: 'x',
      typicalMonth: 1,
      erupted: false,
    );
