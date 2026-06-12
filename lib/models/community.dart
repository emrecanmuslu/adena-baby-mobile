import 'package:flutter/foundation.dart';

/// Topluluk sorusu — API §community. [answers]/[bestAnswerId] yalnız detayda.
@immutable
class Question {
  final String id;
  final String title;
  final String body;
  final String? categorySlug;
  final String? categoryName;
  final String authorName;
  final String authorColor;
  final bool isAnonymous;
  final bool isMine;
  final int score;
  final int answerCount;
  final int myVote; // -1 | 0 | 1
  final bool hasBest;
  final DateTime createdAt;
  final String? bestAnswerId;
  final List<Answer> answers;

  const Question({
    required this.id,
    required this.title,
    this.body = '',
    this.categorySlug,
    this.categoryName,
    this.authorName = '',
    this.authorColor = '#FF8A7A',
    this.isAnonymous = false,
    this.isMine = false,
    this.score = 0,
    this.answerCount = 0,
    this.myVote = 0,
    this.hasBest = false,
    required this.createdAt,
    this.bestAnswerId,
    this.answers = const [],
  });

  Question copyWith({int? score, int? myVote, int? answerCount, String? bestAnswerId,
      List<Answer>? answers}) {
    return Question(
      id: id,
      title: title,
      body: body,
      categorySlug: categorySlug,
      categoryName: categoryName,
      authorName: authorName,
      authorColor: authorColor,
      isAnonymous: isAnonymous,
      isMine: isMine,
      score: score ?? this.score,
      answerCount: answerCount ?? this.answerCount,
      myVote: myVote ?? this.myVote,
      hasBest: bestAnswerId != null ? true : hasBest,
      createdAt: createdAt,
      bestAnswerId: bestAnswerId ?? this.bestAnswerId,
      answers: answers ?? this.answers,
    );
  }

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        title: json['title'] as String,
        body: (json['body'] as String?) ?? '',
        categorySlug: json['category_slug'] as String?,
        categoryName: json['category_name'] as String?,
        authorName: (json['author_name'] as String?) ?? '',
        authorColor: (json['author_color'] as String?) ?? '#FF8A7A',
        isAnonymous: (json['is_anonymous'] as bool?) ?? false,
        isMine: (json['is_mine'] as bool?) ?? false,
        score: (json['score'] as num?)?.toInt() ?? 0,
        answerCount: (json['answer_count'] as num?)?.toInt() ?? 0,
        myVote: (json['my_vote'] as num?)?.toInt() ?? 0,
        hasBest: (json['has_best'] as bool?) ?? false,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        bestAnswerId: json['best_answer_id'] as String?,
        answers: (json['answers'] as List<dynamic>?)
                ?.map((e) => Answer.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// Bir soruya verilen cevap.
@immutable
class Answer {
  final String id;
  final String body;
  final String authorName;
  final String authorColor;
  final bool isAnonymous;
  final bool isMine;
  final int score;
  final int myVote;
  final bool isBest;
  final DateTime createdAt;

  const Answer({
    required this.id,
    required this.body,
    this.authorName = '',
    this.authorColor = '#FF8A7A',
    this.isAnonymous = false,
    this.isMine = false,
    this.score = 0,
    this.myVote = 0,
    this.isBest = false,
    required this.createdAt,
  });

  Answer copyWith({int? score, int? myVote, bool? isBest}) => Answer(
        id: id,
        body: body,
        authorName: authorName,
        authorColor: authorColor,
        isAnonymous: isAnonymous,
        isMine: isMine,
        score: score ?? this.score,
        myVote: myVote ?? this.myVote,
        isBest: isBest ?? this.isBest,
        createdAt: createdAt,
      );

  factory Answer.fromJson(Map<String, dynamic> json) => Answer(
        id: json['id'] as String,
        body: json['body'] as String,
        authorName: (json['author_name'] as String?) ?? '',
        authorColor: (json['author_color'] as String?) ?? '#FF8A7A',
        isAnonymous: (json['is_anonymous'] as bool?) ?? false,
        isMine: (json['is_mine'] as bool?) ?? false,
        score: (json['score'] as num?)?.toInt() ?? 0,
        myVote: (json['my_vote'] as num?)?.toInt() ?? 0,
        isBest: (json['is_best'] as bool?) ?? false,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
