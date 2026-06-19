import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/community_repository.dart';

/// TokenStorage somut bir sınıf ama `implements` ile tüm üyeleri override
/// edebiliriz → secure storage'a (platform kanalı) hiç dokunmadan sabit token.
class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'fake-access';
  @override
  Future<String?> get refreshToken async => 'fake-refresh';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient api;
  late DioAdapter adapter;
  late CommunityRepository repo;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    repo = CommunityRepository(api);
  });

  Map<String, dynamic> questionJson({
    String id = 'q1',
    String title = 'Başlık',
    int score = 3,
    int answerCount = 2,
    int myVote = 1,
  }) =>
      {
        'id': id,
        'title': title,
        'body': 'gövde',
        'category_slug': 'uyku',
        'category_name': 'Uyku',
        'author_name': 'Anne',
        'author_color': '#112233',
        'author_id': 'u9',
        'is_anonymous': false,
        'is_mine': true,
        'score': score,
        'answer_count': answerCount,
        'my_vote': myVote,
        'has_best': true,
        'created_at': '2026-06-18T10:00:00Z',
        'best_answer_id': 'a5',
      };

  group('feed', () {
    test('varsayılan sorgu parametrelerini kurar ve listeyi parse eder', () async {
      adapter.onGet(
        '/community/questions',
        (s) => s.reply(200, [questionJson(id: 'q1'), questionJson(id: 'q2')]),
        queryParameters: {'sort': 'new', 'offset': 0, 'limit': 20},
      );

      final list = await repo.feed();
      expect(list, hasLength(2));
      expect(list.first.id, 'q1');
      expect(list.first.title, 'Başlık');
      expect(list.first.score, 3);
      expect(list.first.answerCount, 2);
      expect(list.first.myVote, 1);
      expect(list[1].id, 'q2');
    });

    test('category + search trimlenip sorguya eklenir', () async {
      adapter.onGet(
        '/community/questions',
        (s) => s.reply(200, [questionJson()]),
        queryParameters: {
          'sort': 'top',
          'offset': 40,
          'limit': 10,
          'category': 'beslenme',
          'search': 'gece uykusu',
        },
      );

      final list = await repo.feed(
        category: 'beslenme',
        sort: 'top',
        search: '  gece uykusu  ',
        offset: 40,
        limit: 10,
      );
      expect(list, hasLength(1));
    });

    test('boş/whitespace search sorguya eklenmez', () async {
      // search anahtarı yoksa eşleşir; varsa http_mock_adapter eşleştirmez.
      adapter.onGet(
        '/community/questions',
        (s) => s.reply(200, <dynamic>[]),
        queryParameters: {'sort': 'new', 'offset': 0, 'limit': 20},
      );

      final list = await repo.feed(search: '   ');
      expect(list, isEmpty);
    });
  });

  test('question(id) doğru endpoint + parse', () async {
    adapter.onGet(
      '/community/questions/q1',
      (s) => s.reply(200, {
        ...questionJson(id: 'q1'),
        'answers': [
          {
            'id': 'a1',
            'body': 'cevap',
            'author_name': 'Baba',
            'score': 5,
            'my_vote': 0,
            'is_best': true,
            'created_at': '2026-06-18T11:00:00Z',
          }
        ],
      }),
    );

    final q = await repo.question('q1');
    expect(q.id, 'q1');
    expect(q.answers, hasLength(1));
    expect(q.answers.first.id, 'a1');
    expect(q.answers.first.isBest, isTrue);
    expect(q.bestAnswerId, 'a5');
  });

  test('userProfile doğru endpoint + parse', () async {
    adapter.onGet(
      '/community/users/u9',
      (s) => s.reply(200, {
        'id': 'u9',
        'name': 'Anne',
        'color': '#abcdef',
        'question_count': 4,
        'answer_count': 7,
        'questions': [questionJson(id: 'q1')],
      }),
    );

    final p = await repo.userProfile('u9');
    expect(p.id, 'u9');
    expect(p.name, 'Anne');
    expect(p.color, '#abcdef');
    expect(p.questionCount, 4);
    expect(p.answerCount, 7);
    expect(p.questions, hasLength(1));
  });

  test('createQuestion POST + payload + dönen id', () async {
    adapter.onPost(
      '/community/questions',
      (s) => s.reply(201, {'id': 'new-q'}),
      data: {'title': 'T', 'body': 'B', 'category': 'uyku'},
    );

    final id = await repo.createQuestion(title: 'T', body: 'B', category: 'uyku');
    expect(id, 'new-q');
  });

  test('createQuestion category null ise payloadda category yok', () async {
    adapter.onPost(
      '/community/questions',
      (s) => s.reply(201, {'id': 'q-x'}),
      data: {'title': 'T', 'body': ''},
    );

    final id = await repo.createQuestion(title: 'T');
    expect(id, 'q-x');
  });

  test('updateQuestion PATCH doğru path + payload (category null gönderir)', () async {
    adapter.onPatch(
      '/community/questions/q1',
      (s) => s.reply(200, {'ok': true}),
      data: {'title': 'Yeni', 'body': 'gövde', 'category': null},
    );

    await repo.updateQuestion('q1', title: 'Yeni', body: 'gövde');
  });

  test('deleteQuestion DELETE doğru path', () async {
    adapter.onDelete('/community/questions/q1', (s) => s.reply(204, null));
    await repo.deleteQuestion('q1');
  });

  test('createAnswer POST doğru path + body', () async {
    adapter.onPost(
      '/community/questions/q1/answers',
      (s) => s.reply(201, {'id': 'a1'}),
      data: {'body': 'cevabım'},
    );
    await repo.createAnswer('q1', 'cevabım');
  });

  test('updateAnswer PATCH doğru path + body', () async {
    adapter.onPatch(
      '/community/answers/a1',
      (s) => s.reply(200, {'ok': true}),
      data: {'body': 'düzeltildi'},
    );
    await repo.updateAnswer('a1', 'düzeltildi');
  });

  test('deleteAnswer DELETE doğru path', () async {
    adapter.onDelete('/community/answers/a1', (s) => s.reply(204, null));
    await repo.deleteAnswer('a1');
  });

  test('vote POST payload + (score,myVote) parse', () async {
    adapter.onPost(
      '/community/vote',
      (s) => s.reply(200, {'score': 9, 'my_vote': 1}),
      data: {'target_type': 'question', 'target_id': 'q1', 'value': 1},
    );

    final r = await repo.vote(targetType: 'question', targetId: 'q1', value: 1);
    expect(r.score, 9);
    expect(r.myVote, 1);
  });

  test('vote negatif/0 değerleri parse eder', () async {
    adapter.onPost(
      '/community/vote',
      (s) => s.reply(200, {'score': -2, 'my_vote': -1}),
      data: {'target_type': 'answer', 'target_id': 'a1', 'value': -1},
    );

    final r = await repo.vote(targetType: 'answer', targetId: 'a1', value: -1);
    expect(r.score, -2);
    expect(r.myVote, -1);
  });

  test('setBest POST doğru path + answer_id', () async {
    adapter.onPost(
      '/community/questions/q1/best',
      (s) => s.reply(200, {'ok': true}),
      data: {'answer_id': 'a5'},
    );
    await repo.setBest('q1', 'a5');
  });

  test('setBest answerId null → answer_id null (en iyi kaldırma)', () async {
    adapter.onPost(
      '/community/questions/q1/best',
      (s) => s.reply(200, {'ok': true}),
      data: {'answer_id': null},
    );
    await repo.setBest('q1', null);
  });

  test('report POST payload (note varsayılan boş)', () async {
    adapter.onPost(
      '/community/report',
      (s) => s.reply(201, {'ok': true}),
      data: {
        'target_type': 'question',
        'target_id': 'q1',
        'reason': 'spam',
        'note': '',
      },
    );
    await repo.report(targetType: 'question', targetId: 'q1', reason: 'spam');
  });

  test('report POST note ile', () async {
    adapter.onPost(
      '/community/report',
      (s) => s.reply(201, {'ok': true}),
      data: {
        'target_type': 'answer',
        'target_id': 'a1',
        'reason': 'abuse',
        'note': 'kötü dil',
      },
    );
    await repo.report(
        targetType: 'answer', targetId: 'a1', reason: 'abuse', note: 'kötü dil');
  });
}
