import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/models/memory.dart';
import 'package:adena_baby/models/mom_entry.dart';
import 'package:adena_baby/models/pricing.dart';
import 'package:adena_baby/models/locale_info.dart';
import 'package:adena_baby/models/cycle.dart';
import 'package:adena_baby/models/community.dart';

void main() {
  group('Memory.fromJson + getters', () {
    test('tam payload okunur', () {
      final m = Memory.fromJson({
        'id': 'mem-1',
        'date': '2026-06-18',
        'title': 'İlk gülümseme',
        'note': 'çok tatlıydı',
        'photo': 'https://x/p.jpg',
        'first_tag': 'smile',
      });
      expect(m.id, 'mem-1');
      expect(m.date, DateTime(2026, 6, 18));
      expect(m.title, 'İlk gülümseme');
      expect(m.note, 'çok tatlıydı');
      expect(m.photo, 'https://x/p.jpg');
      expect(m.firstTag, 'smile');
      expect(m.isFirst, isTrue);
    });

    test('boş photo string → null, eksik alanlar boş', () {
      final m = Memory.fromJson({'id': 'mem-1', 'date': '2026-06-18', 'photo': ''});
      expect(m.photo, isNull);
      expect(m.hasPhoto, isFalse);
      expect(m.title, '');
      expect(m.firstTag, '');
      expect(m.isFirst, isFalse);
    });

    test('isLocalPhoto: http değilse yerel', () {
      final local = Memory(id: 'x', date: DateTime(2026), photo: '/data/p.jpg');
      expect(local.hasPhoto, isTrue);
      expect(local.isLocalPhoto, isTrue);
      final remote = Memory(id: 'x', date: DateTime(2026), photo: 'https://x/p.jpg');
      expect(remote.isLocalPhoto, isFalse);
    });

    test('firstTagInfo katalog araması', () {
      expect(firstTagInfo('smile')!.key, 'smile');
      expect(firstTagInfo(''), isNull);
      expect(firstTagInfo('uydurma'), isNull);
    });
  });

  group('MomKind.fromString', () {
    test('bilinen değerler', () {
      expect(MomKind.fromString('weight'), MomKind.weight);
      expect(MomKind.fromString('appointment'), MomKind.appointment);
      expect(MomKind.fromString('note'), MomKind.note);
    });
    test('bilinmeyen → note (fallback)', () {
      expect(MomKind.fromString('xyz'), MomKind.note);
    });
  });

  group('MomEntry serialization', () {
    test('fromJson tüm alanları okur, weight_kg parse', () {
      final e = MomEntry.fromJson({
        'id': 'm1',
        'kind': 'weight',
        'date': '2026-06-18T10:00:00Z',
        'weight_kg': '68.5',
        'title': '',
        'note': 'kontrol',
      });
      expect(e.id, 'm1');
      expect(e.kind, MomKind.weight);
      expect(e.weightKg, 68.5);
      expect(e.title, isNull); // boş string → null
      expect(e.note, 'kontrol');
    });

    test('weight_kg null → null', () {
      final e = MomEntry.fromJson({
        'id': 'm1',
        'kind': 'note',
        'date': '2026-06-18T10:00:00Z',
      });
      expect(e.weightKg, isNull);
    });

    test('toCreateJson: null alanlar atlanır, kind.name + UTC tarih', () {
      final e = MomEntry(
        id: 'm1',
        kind: MomKind.weight,
        date: DateTime.utc(2026, 6, 18, 10),
        weightKg: 70.0,
      );
      final j = e.toCreateJson();
      expect(j['id'], 'm1');
      expect(j['kind'], 'weight');
      expect(j['weight_kg'], 70.0);
      expect(j.containsKey('title'), isFalse);
      expect(j.containsKey('note'), isFalse);
      expect(j['date'], '2026-06-18T10:00:00.000Z');
    });
  });

  group('PlanPricing.fromJson', () {
    test('tam payload okunur', () {
      final p = PlanPricing.fromJson({
        'plan': 'yearly',
        'price': '₺590',
        'original_price': '₺890',
        'on_sale': true,
        'discount_percent': 34,
        'badge': '%34 indirim',
      });
      expect(p.plan, 'yearly');
      expect(p.price, '₺590');
      expect(p.originalPrice, '₺890');
      expect(p.onSale, isTrue);
      expect(p.discountPercent, 34);
      expect(p.badge, '%34 indirim');
    });

    test('eksik alanlar varsayılana düşer', () {
      final p = PlanPricing.fromJson({'plan': 'monthly'});
      expect(p.price, '');
      expect(p.originalPrice, isNull);
      expect(p.onSale, isFalse);
      expect(p.discountPercent, isNull);
      expect(p.badge, '');
    });
  });

  group('SupportedLocale / CountryInfo.fromJson', () {
    test('SupportedLocale tam + eksik', () {
      final l = SupportedLocale.fromJson({
        'code': 'tr',
        'native_name': 'Türkçe',
        'english_name': 'Turkish',
        'is_default': true,
      });
      expect(l.code, 'tr');
      expect(l.nativeName, 'Türkçe');
      expect(l.isDefault, isTrue);

      final fallback = SupportedLocale.fromJson({'code': 'de'});
      expect(fallback.nativeName, 'de'); // isim yoksa code'a düşer
      expect(fallback.englishName, 'de');
      expect(fallback.isDefault, isFalse);
    });

    test('CountryInfo tam + eksik varsayılanlar', () {
      final c = CountryInfo.fromJson({
        'code': 'TR',
        'name': 'Türkiye',
        'dial_code': '+90',
        'currency': 'TRY',
        'uses_imperial': false,
        'locale': 'tr',
        'translated': true,
        'sales_enabled': true,
      });
      expect(c.code, 'TR');
      expect(c.dialCode, '+90');
      expect(c.usesImperial, isFalse);

      final d = CountryInfo.fromJson({'code': 'XX'});
      expect(d.name, '');
      expect(d.locale, 'en'); // varsayılan en
      expect(d.usesImperial, isFalse);
      expect(d.translated, isFalse);
      expect(d.salesEnabled, isTrue); // varsayılan true
    });
  });

  group('Cycle enum fromString', () {
    test('Breastfeeding', () {
      expect(Breastfeeding.fromString('exclusive'), Breastfeeding.exclusive);
      expect(Breastfeeding.fromString('none'), Breastfeeding.none);
      expect(Breastfeeding.fromString(null), isNull);
      expect(Breastfeeding.fromString(''), isNull);
      expect(Breastfeeding.fromString('uydurma'), Breastfeeding.exclusive); // fallback
    });

    test('FlowLevel', () {
      expect(FlowLevel.fromString('heavy'), FlowLevel.heavy);
      expect(FlowLevel.fromString(null), isNull);
      expect(FlowLevel.fromString('uydurma'), FlowLevel.light); // fallback
    });

    test('LochiaColor: yellow_white özel eşleme + apiValue', () {
      expect(LochiaColor.fromString('yellow_white'), LochiaColor.yellowWhite);
      expect(LochiaColor.yellowWhite.apiValue, 'yellow_white');
      expect(LochiaColor.red.apiValue, 'red');
      expect(LochiaColor.fromString(null), isNull);
      expect(LochiaColor.fromString('uydurma'), LochiaColor.red); // fallback
    });
  });

  group('CycleSettings serialization', () {
    test('fromJson okur, periodReturned', () {
      final s = CycleSettings.fromJson({
        'baby': 'b1',
        'birth_date': '2025-01-01',
        'breastfeeding': 'mixed',
        'first_period_date': '2025-06-01',
        'show_fertility_warning': false,
        'enabled': true,
      });
      expect(s.babyId, 'b1');
      expect(s.breastfeeding, Breastfeeding.mixed);
      expect(s.firstPeriodDate, DateTime(2025, 6, 1));
      expect(s.periodReturned, isTrue);
      expect(s.showFertilityWarning, isFalse);
    });

    test('first_period_date yoksa periodReturned false', () {
      final s = CycleSettings.fromJson({'enabled': true});
      expect(s.firstPeriodDate, isNull);
      expect(s.periodReturned, isFalse);
    });

    test('copyWith sentinel: firstPeriodDate açıkça null yapılabilir', () {
      final s = CycleSettings(firstPeriodDate: DateTime(2025, 6, 1));
      // Argüman verilmezse korunur
      expect(s.copyWith().firstPeriodDate, DateTime(2025, 6, 1));
      // Açıkça null verilince temizlenir
      expect(s.copyWith(firstPeriodDate: null).firstPeriodDate, isNull);
      // Yeni değer verilince değişir
      expect(
        s.copyWith(firstPeriodDate: DateTime(2025, 7, 1)).firstPeriodDate,
        DateTime(2025, 7, 1),
      );
    });
  });

  group('CycleEntry serialization', () {
    test('fromJson okur, isPeriod', () {
      final e = CycleEntry.fromJson({
        'id': 'c1',
        'date': '2026-06-18',
        'flow': 'medium',
        'lochia_color': 'yellow_white',
        'symptoms': ['cramp', 'mood'],
        'mood': 3,
        'note': 'not',
      });
      expect(e.id, 'c1');
      expect(e.date, DateTime(2026, 6, 18));
      expect(e.flow, FlowLevel.medium);
      expect(e.lochiaColor, LochiaColor.yellowWhite);
      expect(e.symptoms, ['cramp', 'mood']);
      expect(e.mood, 3);
      // Loşia rengi set → gün ADET sayılmaz (yeni kural; loşia ≠ adet).
      expect(e.isPeriod, isFalse);
    });

    test('spotting/none isPeriod false', () {
      final spot = CycleEntry.fromJson({'id': 'c', 'date': '2026-06-18', 'flow': 'spotting'});
      expect(spot.isPeriod, isFalse);
      final none = CycleEntry.fromJson({'id': 'c', 'date': '2026-06-18', 'flow': 'none'});
      expect(none.isPeriod, isFalse);
    });

    test('boş note → null, symptoms yoksa boş liste', () {
      final e = CycleEntry.fromJson({'id': 'c', 'date': '2026-06-18', 'note': ''});
      expect(e.note, isNull);
      expect(e.symptoms, isEmpty);
    });

    test('toJson: flow.name, lochia apiValue, date YYYY-MM-DD', () {
      final e = CycleEntry(
        id: 'c1',
        date: DateTime(2026, 6, 8),
        flow: FlowLevel.heavy,
        lochiaColor: LochiaColor.yellowWhite,
        symptoms: const ['cramp'],
        mood: 4,
        note: 'x',
      );
      final j = e.toJson();
      expect(j['id'], 'c1');
      expect(j['date'], '2026-06-08');
      expect(j['flow'], 'heavy');
      expect(j['lochia_color'], 'yellow_white');
      expect(j['symptoms'], ['cramp']);
      expect(j['mood'], 4);
      expect(j['note'], 'x');
    });

    test('toJson: null flow/lochia → boş string, mood null atlanır', () {
      final e = CycleEntry(id: 'c1', date: DateTime(2026, 6, 8));
      final j = e.toJson();
      expect(j['flow'], '');
      expect(j['lochia_color'], '');
      expect(j.containsKey('mood'), isFalse);
      expect(j['note'], '');
    });
  });

  group('Answer.fromJson + copyWith', () {
    test('fromJson okur, ts toLocal', () {
      final a = Answer.fromJson({
        'id': 'a1',
        'body': 'cevap',
        'author_name': 'Ada',
        'author_color': '#123456',
        'author_id': 'u1',
        'is_anonymous': false,
        'is_mine': true,
        'score': 5,
        'my_vote': 1,
        'is_best': true,
        'created_at': '2026-06-18T10:00:00Z',
      });
      expect(a.id, 'a1');
      expect(a.body, 'cevap');
      expect(a.score, 5);
      expect(a.myVote, 1);
      expect(a.isBest, isTrue);
      expect(a.createdAt.isUtc, isFalse);
    });

    test('eksik alanlar varsayılana', () {
      final a = Answer.fromJson({
        'id': 'a1',
        'body': 'x',
        'created_at': '2026-06-18T10:00:00Z',
      });
      expect(a.authorName, '');
      expect(a.authorColor, '#FF8A7A');
      expect(a.isAnonymous, isFalse);
      expect(a.score, 0);
      expect(a.myVote, 0);
      expect(a.isBest, isFalse);
    });

    test('copyWith yalnız score/myVote/isBest değiştirir', () {
      final a = Answer(id: 'a1', body: 'x', createdAt: DateTime(2026));
      final c = a.copyWith(score: 3, myVote: -1, isBest: true);
      expect(c.score, 3);
      expect(c.myVote, -1);
      expect(c.isBest, isTrue);
      expect(c.id, a.id);
      expect(c.body, a.body);
    });
  });

  group('Question.fromJson', () {
    test('iç içe answers listesi ayrıştırılır', () {
      final q = Question.fromJson({
        'id': 'q1',
        'title': 'Soru',
        'body': 'gövde',
        'category_slug': 'uyku',
        'category_name': 'Uyku',
        'created_at': '2026-06-18T10:00:00Z',
        'best_answer_id': 'a1',
        'answers': [
          {'id': 'a1', 'body': 'cevap', 'created_at': '2026-06-18T11:00:00Z'},
        ],
      });
      expect(q.id, 'q1');
      expect(q.title, 'Soru');
      expect(q.categorySlug, 'uyku');
      expect(q.bestAnswerId, 'a1');
      expect(q.answers.length, 1);
      expect(q.answers.first.id, 'a1');
    });

    test('answers yoksa boş liste, body yoksa boş', () {
      final q = Question.fromJson({
        'id': 'q1',
        'title': 'Soru',
        'created_at': '2026-06-18T10:00:00Z',
      });
      expect(q.body, '');
      expect(q.answers, isEmpty);
    });
  });

  group('CommunityProfile.fromJson', () {
    test('istatistik + soru listesi', () {
      final p = CommunityProfile.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'color': '#abcdef',
        'question_count': 4,
        'answer_count': 9,
        'questions': [
          {'id': 'q1', 'title': 'S', 'created_at': '2026-06-18T10:00:00Z'},
        ],
      });
      expect(p.id, 'u1');
      expect(p.name, 'Ada');
      expect(p.questionCount, 4);
      expect(p.answerCount, 9);
      expect(p.questions.length, 1);
    });

    test('eksik alanlar varsayılana', () {
      final p = CommunityProfile.fromJson({'id': 'u1'});
      expect(p.name, '');
      expect(p.color, '#FF8A7A');
      expect(p.questionCount, 0);
      expect(p.questions, isEmpty);
    });
  });
}
