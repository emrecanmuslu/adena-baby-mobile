import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/content_repository.dart';

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
  late ContentRepository repo;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    repo = ContentRepository(api);
  });

  test('categories() doğru endpoint + parse', () async {
    adapter.onGet(
      '/content/categories',
      (s) => s.reply(200, [
        {
          'slug': 'uyku',
          'name': 'Uyku',
          'icon': 'moon',
          'color': '#9B8CE8',
          'article_count': 5,
        },
        {
          'slug': 'beslenme',
          'name': 'Beslenme',
          'icon': '',
          'color': '',
          'article_count': 0,
        },
      ]),
    );

    final cats = await repo.categories();
    expect(cats, hasLength(2));
    expect(cats.first.slug, 'uyku');
    expect(cats.first.name, 'Uyku');
    expect(cats.first.color, '#9B8CE8');
    expect(cats.first.articleCount, 5);
    // Boş string color → null normalize.
    expect(cats[1].color, isNull);
  });

  group('articles', () {
    Map<String, dynamic> articleJson({String slug = 'a1'}) => {
          'slug': slug,
          'title': 'Makale',
          'summary': 'özet',
          'category_slug': 'uyku',
          'category_name': 'Uyku',
          'age_min_month': 0,
          'age_max_month': 12,
          'cover_image': 'https://x/y.png',
          'author_name': 'Uzman',
          'read_minutes': 4,
        };

    test('parametresiz → boş sorgu, listeyi parse eder', () async {
      adapter.onGet(
        '/content/articles',
        (s) => s.reply(200, [articleJson(slug: 'a1'), articleJson(slug: 'a2')]),
        queryParameters: {},
      );

      final list = await repo.articles();
      expect(list, hasLength(2));
      expect(list.first.slug, 'a1');
      expect(list.first.title, 'Makale');
      expect(list.first.ageMaxMonth, 12);
      expect(list.first.coverImage, 'https://x/y.png');
      // body liste yanıtında yok → null.
      expect(list.first.body, isNull);
    });

    test('category filtresi sorguya eklenir', () async {
      adapter.onGet(
        '/content/articles',
        (s) => s.reply(200, [articleJson()]),
        queryParameters: {'category': 'uyku'},
      );

      final list = await repo.articles(category: 'uyku');
      expect(list, hasLength(1));
    });

    test('ageMonths filtresi age_months olarak eklenir', () async {
      adapter.onGet(
        '/content/articles',
        (s) => s.reply(200, [articleJson()]),
        queryParameters: {'age_months': 6},
      );

      final list = await repo.articles(ageMonths: 6);
      expect(list, hasLength(1));
    });

    test('category + ageMonths birlikte', () async {
      adapter.onGet(
        '/content/articles',
        (s) => s.reply(200, [articleJson()]),
        queryParameters: {'category': 'beslenme', 'age_months': 3},
      );

      final list = await repo.articles(category: 'beslenme', ageMonths: 3);
      expect(list, hasLength(1));
    });
  });

  test('article(slug) doğru endpoint + body dahil parse', () async {
    adapter.onGet(
      '/content/articles/uyku-rehberi',
      (s) => s.reply(200, {
        'slug': 'uyku-rehberi',
        'title': 'Uyku Rehberi',
        'summary': 'özet',
        'category_slug': 'uyku',
        'category_name': 'Uyku',
        'age_min_month': 0,
        'age_max_month': 24,
        'cover_image': '',
        'author_name': 'Dr.',
        'read_minutes': 8,
        'body': '# Markdown gövde',
      }),
    );

    final a = await repo.article('uyku-rehberi');
    expect(a.slug, 'uyku-rehberi');
    expect(a.title, 'Uyku Rehberi');
    expect(a.body, '# Markdown gövde');
    // Boş string cover → null normalize.
    expect(a.coverImage, isNull);
  });
}
