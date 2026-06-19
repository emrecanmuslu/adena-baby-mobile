import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/models/article.dart';
import 'package:adena_baby/models/community.dart';

/// Covers model surface not exercised by the existing test/models/ files:
/// - article.dart (ArticleCategory, Article) — previously untested entirely
/// - Question.copyWith / Answer.copyWith — fromJson is tested elsewhere, the
///   copyWith branch logic (especially hasBest derivation) was not.
void main() {
  group('ArticleCategory.fromJson', () {
    test('tam payload tüm alanlara ayrıştırılır', () {
      final c = ArticleCategory.fromJson({
        'slug': 'uyku',
        'name': 'Uyku',
        'icon': 'moon',
        'color': '#9B8CE8',
        'article_count': 12,
      });
      expect(c.slug, 'uyku');
      expect(c.name, 'Uyku');
      expect(c.icon, 'moon');
      expect(c.color, '#9B8CE8');
      expect(c.articleCount, 12);
    });

    test('eksik alanlar varsayılana düşer', () {
      final c = ArticleCategory.fromJson({'slug': 'x', 'name': 'X'});
      expect(c.icon, '');
      expect(c.color, isNull);
      expect(c.articleCount, 0);
    });

    test('boş string color → null', () {
      final c = ArticleCategory.fromJson({'slug': 'x', 'name': 'X', 'color': ''});
      expect(c.color, isNull);
    });

    test('article_count num (double) → int', () {
      final c = ArticleCategory.fromJson(
          {'slug': 'x', 'name': 'X', 'article_count': 4.0});
      expect(c.articleCount, 4);
    });
  });

  group('Article.fromJson', () {
    test('tam payload (detay, body dolu) okunur', () {
      final a = Article.fromJson({
        'slug': 'bebek-uykusu',
        'title': 'Bebek Uykusu',
        'summary': 'özet',
        'category_slug': 'uyku',
        'category_name': 'Uyku',
        'age_min_month': 0,
        'age_max_month': 12,
        'cover_image': 'https://x/c.jpg',
        'author_name': 'Dr. Ada',
        'read_minutes': 6,
        'body': '# Markdown',
      });
      expect(a.slug, 'bebek-uykusu');
      expect(a.title, 'Bebek Uykusu');
      expect(a.summary, 'özet');
      expect(a.categorySlug, 'uyku');
      expect(a.categoryName, 'Uyku');
      expect(a.ageMinMonth, 0);
      expect(a.ageMaxMonth, 12);
      expect(a.coverImage, 'https://x/c.jpg');
      expect(a.authorName, 'Dr. Ada');
      expect(a.readMinutes, 6);
      expect(a.body, '# Markdown');
    });

    test('eksik alanlar varsayılana düşer (liste yanıtı: body null)', () {
      final a = Article.fromJson({'slug': 's', 'title': 'T'});
      expect(a.summary, '');
      expect(a.categorySlug, '');
      expect(a.categoryName, '');
      expect(a.ageMinMonth, 0);
      expect(a.ageMaxMonth, 240); // varsayılan üst sınır
      expect(a.coverImage, isNull);
      expect(a.authorName, '');
      expect(a.readMinutes, 0);
      expect(a.body, isNull);
    });

    test('boş string cover_image → null', () {
      final a = Article.fromJson({'slug': 's', 'title': 'T', 'cover_image': ''});
      expect(a.coverImage, isNull);
    });

    test('ay sınırları num(double) → int', () {
      final a = Article.fromJson({
        'slug': 's',
        'title': 'T',
        'age_min_month': 3.0,
        'age_max_month': 24.0,
        'read_minutes': 8.0,
      });
      expect(a.ageMinMonth, 3);
      expect(a.ageMaxMonth, 24);
      expect(a.readMinutes, 8);
    });
  });

  group('Answer.copyWith', () {
    final base = Answer(
      id: 'a1',
      body: 'cevap',
      authorName: 'Ada',
      authorColor: '#123456',
      authorId: 'u1',
      isAnonymous: false,
      isMine: true,
      score: 2,
      myVote: 1,
      isBest: false,
      createdAt: DateTime(2026, 6, 18),
    );

    test('verilen alanlar değişir, gerisi korunur', () {
      final c = base.copyWith(score: 5, myVote: -1, isBest: true);
      expect(c.score, 5);
      expect(c.myVote, -1);
      expect(c.isBest, isTrue);
      // korunanlar
      expect(c.id, 'a1');
      expect(c.body, 'cevap');
      expect(c.authorName, 'Ada');
      expect(c.authorColor, '#123456');
      expect(c.authorId, 'u1');
      expect(c.isMine, isTrue);
      expect(c.createdAt, DateTime(2026, 6, 18));
    });

    test('argümansız copyWith tüm alanları korur', () {
      final c = base.copyWith();
      expect(c.score, base.score);
      expect(c.myVote, base.myVote);
      expect(c.isBest, base.isBest);
    });
  });

  group('Question.copyWith', () {
    Question makeQ() => Question(
          id: 'q1',
          title: 'Soru',
          body: 'gövde',
          categorySlug: 'uyku',
          categoryName: 'Uyku',
          authorName: 'Ada',
          authorColor: '#abcdef',
          authorId: 'u1',
          isAnonymous: false,
          isMine: true,
          score: 3,
          answerCount: 1,
          myVote: 0,
          hasBest: false,
          createdAt: DateTime(2026, 6, 18),
          bestAnswerId: null,
          answers: const [],
        );

    test('score/myVote/answerCount değişir, gerisi korunur', () {
      final q = makeQ().copyWith(score: 9, myVote: 1, answerCount: 4);
      expect(q.score, 9);
      expect(q.myVote, 1);
      expect(q.answerCount, 4);
      expect(q.id, 'q1');
      expect(q.title, 'Soru');
      expect(q.body, 'gövde');
      expect(q.categorySlug, 'uyku');
      expect(q.authorId, 'u1');
      expect(q.isMine, isTrue);
      expect(q.createdAt, DateTime(2026, 6, 18));
    });

    test('bestAnswerId verilince hasBest otomatik true olur', () {
      final q = makeQ().copyWith(bestAnswerId: 'a7');
      expect(q.bestAnswerId, 'a7');
      expect(q.hasBest, isTrue);
    });

    test('bestAnswerId verilmezse mevcut hasBest korunur (false kalır)', () {
      final q = makeQ().copyWith(score: 1);
      expect(q.bestAnswerId, isNull);
      expect(q.hasBest, isFalse);
    });

    test('zaten hasBest=true olan soruda bestAnswerId vermeden korunur', () {
      final q0 = Question(
        id: 'q1',
        title: 'S',
        hasBest: true,
        bestAnswerId: 'a1',
        createdAt: DateTime(2026),
      );
      final q = q0.copyWith(score: 2);
      expect(q.hasBest, isTrue);
      expect(q.bestAnswerId, 'a1'); // korunur
    });

    test('answers listesi değiştirilebilir', () {
      final ans = [
        Answer(id: 'a1', body: 'x', createdAt: DateTime(2026)),
      ];
      final q = makeQ().copyWith(answers: ans);
      expect(q.answers.length, 1);
      expect(q.answers.first.id, 'a1');
    });

    test('argümansız copyWith answers ve diğer alanları korur', () {
      final q = makeQ().copyWith();
      expect(q.score, 3);
      expect(q.answerCount, 1);
      expect(q.answers, isEmpty);
    });
  });
}
