import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/data/pregnancy_weeks.dart';

/// Gebelik haftası tablosu (gömülü) saf arama/fallback testleri.

void main() {
  final data = PregnancyWeeksData.embedded;

  group('PregnancyWeeksData.stageFor', () {
    test('aralık içi hafta doğrudan eşleşir', () {
      expect(data.stageFor(20).fruit, 'muz');
      expect(data.stageFor(4).fruit, 'haşhaş tohumu');
      expect(data.stageFor(40).fruit, 'karpuz');
    });

    test('4 altındaki hafta 4e kıstırılır', () {
      expect(data.stageFor(3).fruit, data.stageFor(4).fruit);
      expect(data.stageFor(0).fruit, 'haşhaş tohumu');
      expect(data.stageFor(-5).fruit, 'haşhaş tohumu');
    });

    test('40 üstündeki hafta 40a kıstırılır', () {
      expect(data.stageFor(41).fruit, 'karpuz');
      expect(data.stageFor(99).fruit, 'karpuz');
    });

    test('FruitStage emoji ve boyut alanları dolu', () {
      final s = data.stageFor(28);
      expect(s.fruit, 'patlıcan');
      expect(s.emoji, isNotEmpty);
      expect(s.size, contains('kg'));
    });
  });

  group('PregnancyWeeksData.noteFor', () {
    test('mevcut hafta notunu döndürür', () {
      expect(data.noteFor(40), contains('doğuma tam hazır'));
      expect(data.noteFor(12), contains('trimester'));
    });

    test('4 altında not yoksa ilk trimester genel notuna düşer (week<=13)', () {
      final note = data.noteFor(3);
      expect(note, contains('organları'));
    });

    test('her hafta 4..40 için boş olmayan not vardır', () {
      for (var w = 4; w <= 40; w++) {
        expect(data.noteFor(w), isNotEmpty, reason: 'hafta $w notu boş');
      }
    });
  });

  group('fromApi fabrikası', () {
    test('boş liste → gömülü tabloya düşer', () {
      final d = PregnancyWeeksData.fromApi(const []);
      expect(d.stageFor(20).fruit, 'muz');
      expect(d.noteFor(20), isNotEmpty);
    });

    test('geçerli API verisi okunur', () {
      final d = PregnancyWeeksData.fromApi([
        {'week': 10, 'fruit': 'testmeyve', 'emoji': '🍇', 'size': '~9 cm', 'note': 'test notu'},
      ]);
      expect(d.stageFor(10).fruit, 'testmeyve');
      expect(d.stageFor(10).size, '~9 cm');
      expect(d.noteFor(10), 'test notu');
    });

    test('week alanı olmayan kayıt atlanır, hepsi geçersizse gömülüye düşer', () {
      final d = PregnancyWeeksData.fromApi([
        {'fruit': 'gecersiz'},
        {'emoji': '❌'},
      ]);
      expect(d.stageFor(20).fruit, 'muz'); // gömülü
    });

    test('Map olmayan öğeler güvenle atlanır', () {
      final d = PregnancyWeeksData.fromApi(['saçma', 42, null]);
      expect(d.stageFor(20).fruit, 'muz');
    });
  });

  group('global yardımcılar (geriye uyumluluk)', () {
    test('fruitStageFor gömülü stageFor ile aynı', () {
      expect(fruitStageFor(20).fruit, data.stageFor(20).fruit);
    });
    test('weeklyNote gömülü noteFor ile aynı', () {
      expect(weeklyNote(20), data.noteFor(20));
    });
  });
}
