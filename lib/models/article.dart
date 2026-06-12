import 'package:flutter/foundation.dart';

/// Uzman içeriği kategorisi — API §content/categories.
/// [icon] = AdenaIcon anahtarı, [color] = opsiyonel hex (#RRGGBB).
@immutable
class ArticleCategory {
  final String slug;
  final String name;
  final String icon;
  final String? color; // "#9B8CE8" veya null
  final int articleCount;

  const ArticleCategory({
    required this.slug,
    required this.name,
    this.icon = '',
    this.color,
    this.articleCount = 0,
  });

  factory ArticleCategory.fromJson(Map<String, dynamic> json) => ArticleCategory(
        slug: json['slug'] as String,
        name: json['name'] as String,
        icon: (json['icon'] as String?) ?? '',
        color: (json['color'] as String?)?.isEmpty ?? true
            ? null
            : json['color'] as String?,
        articleCount: (json['article_count'] as num?)?.toInt() ?? 0,
      );
}

/// Uzman/rehber makalesi — API §content/articles.
/// [body] yalnız detay yanıtında doludur (liste yanıtında null).
@immutable
class Article {
  final String slug;
  final String title;
  final String summary;
  final String categorySlug;
  final String categoryName;
  final int ageMinMonth;
  final int ageMaxMonth;
  final String? coverImage; // sunucu mutlak URL'i (yoksa null)
  final String authorName;
  final int readMinutes;
  final String? body; // Markdown — yalnız detayda

  const Article({
    required this.slug,
    required this.title,
    this.summary = '',
    this.categorySlug = '',
    this.categoryName = '',
    this.ageMinMonth = 0,
    this.ageMaxMonth = 240,
    this.coverImage,
    this.authorName = '',
    this.readMinutes = 0,
    this.body,
  });

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        slug: json['slug'] as String,
        title: json['title'] as String,
        summary: (json['summary'] as String?) ?? '',
        categorySlug: (json['category_slug'] as String?) ?? '',
        categoryName: (json['category_name'] as String?) ?? '',
        ageMinMonth: (json['age_min_month'] as num?)?.toInt() ?? 0,
        ageMaxMonth: (json['age_max_month'] as num?)?.toInt() ?? 240,
        coverImage: (json['cover_image'] as String?)?.isEmpty ?? true
            ? null
            : json['cover_image'] as String?,
        authorName: (json['author_name'] as String?) ?? '',
        readMinutes: (json['read_minutes'] as num?)?.toInt() ?? 0,
        body: json['body'] as String?,
      );
}
