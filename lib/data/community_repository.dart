import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/community.dart';

/// Topluluk (soru-cevap) API katmanı.
class CommunityRepository {
  final ApiClient _api;
  CommunityRepository(this._api);

  Future<List<Question>> feed(
      {String? category, String sort = 'new', int offset = 0, int limit = 20}) async {
    final query = <String, dynamic>{'sort': sort, 'offset': offset, 'limit': limit};
    if (category != null) query['category'] = category;
    final resp =
        await _api.dio.get('/community/questions', queryParameters: query);
    final data = resp.data as List<dynamic>;
    return data.map((e) => Question.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Question> question(String id) async {
    final resp = await _api.dio.get('/community/questions/$id');
    return Question.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Yeni soru oluşturur; oluşturulan sorunun id'sini döndürür.
  Future<String> createQuestion(
      {required String title, String body = '', String? category}) async {
    final data = <String, dynamic>{'title': title, 'body': body};
    if (category != null) data['category'] = category;
    final resp = await _api.dio.post('/community/questions', data: data);
    return (resp.data as Map<String, dynamic>)['id'] as String;
  }

  Future<void> createAnswer(String questionId, String body) async {
    await _api.dio.post('/community/questions/$questionId/answers',
        data: {'body': body});
  }

  /// Oy ver/kaldır → {score, myVote} döndürür.
  Future<({int score, int myVote})> vote(
      {required String targetType, required String targetId, required int value}) async {
    final resp = await _api.dio.post('/community/vote', data: {
      'target_type': targetType,
      'target_id': targetId,
      'value': value,
    });
    final d = resp.data as Map<String, dynamic>;
    return (score: (d['score'] as num).toInt(), myVote: (d['my_vote'] as num).toInt());
  }

  Future<void> setBest(String questionId, String? answerId) async {
    await _api.dio.post('/community/questions/$questionId/best',
        data: {'answer_id': answerId});
  }

  Future<void> report(
      {required String targetType,
      required String targetId,
      required String reason,
      String note = ''}) async {
    await _api.dio.post('/community/report', data: {
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'note': note,
    });
  }
}

final communityRepositoryProvider = Provider<CommunityRepository>(
    (ref) => CommunityRepository(ref.watch(apiClientProvider)));

/// Akış sorgu anahtarı (kategori + sıralama).
typedef FeedQuery = ({String? category, String sort});

final communityFeedProvider =
    FutureProvider.family<List<Question>, FeedQuery>((ref, q) async {
  return ref
      .watch(communityRepositoryProvider)
      .feed(category: q.category, sort: q.sort);
});
