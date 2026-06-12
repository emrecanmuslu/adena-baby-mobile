import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/article.dart';

/// Uzman içeriği (kategori + makale) API katmanı — salt okunur.
class ContentRepository {
  final ApiClient _api;
  ContentRepository(this._api);

  Future<List<ArticleCategory>> categories() async {
    final resp = await _api.dio.get('/content/categories');
    final data = resp.data as List<dynamic>;
    return data
        .map((e) => ArticleCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Makale listesi — [category] (slug) ve/veya [ageMonths] ile filtreli.
  Future<List<Article>> articles({String? category, int? ageMonths}) async {
    final query = <String, dynamic>{};
    if (category != null) query['category'] = category;
    if (ageMonths != null) query['age_months'] = ageMonths;
    final resp = await _api.dio.get('/content/articles', queryParameters: query);
    final data = resp.data as List<dynamic>;
    return data.map((e) => Article.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Article> article(String slug) async {
    final resp = await _api.dio.get('/content/articles/$slug');
    return Article.fromJson(resp.data as Map<String, dynamic>);
  }
}

final contentRepositoryProvider = Provider<ContentRepository>(
    (ref) => ContentRepository(ref.watch(apiClientProvider)));

final contentCategoriesProvider =
    FutureProvider<List<ArticleCategory>>((ref) async {
  return ref.watch(contentRepositoryProvider).categories();
});

/// Makale listesi sorgu anahtarı — Dart record'u değer-eşitlikli olduğundan
/// `family` anahtarı olarak güvenle kullanılır.
typedef ArticleQuery = ({String? category, int? ageMonths});

final articlesProvider =
    FutureProvider.family<List<Article>, ArticleQuery>((ref, q) async {
  return ref
      .watch(contentRepositoryProvider)
      .articles(category: q.category, ageMonths: q.ageMonths);
});

final articleProvider =
    FutureProvider.family<Article, String>((ref, slug) async {
  return ref.watch(contentRepositoryProvider).article(slug);
});
