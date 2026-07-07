import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/content_repository.dart';
import 'content_ui.dart';

/// Makale listesi ekranı argümanları (GoRoute extra ile taşınır).
class ArticleListArgs {
  final String? categorySlug;
  final int? ageMonths;
  final String title;
  const ArticleListArgs({this.categorySlug, this.ageMonths, required this.title});
}

/// Kategori ya da yaş filtreli makale listesi — tam genişlik kartlar.
class ArticleListScreen extends ConsumerWidget {
  final ArticleListArgs args;
  const ArticleListScreen({super.key, required this.args});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(articlesProvider(
        (category: args.categorySlug, ageMonths: args.ageMonths)));
    final cats = ref.watch(contentCategoriesProvider).asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(args.title),
      ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            for (var i = 0; i < 6; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Skeleton(height: 118, radius: 18),
              ),
          ],
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(apiErrorText(e),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
          ),
        ),
        data: (articles) {
          if (articles.isEmpty) return const _Empty();
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
            itemCount: articles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (_, i) {
              final cat = cats
                  .where((c) => c.slug == articles[i].categorySlug)
                  .firstOrNull;
              return ArticleCard(
                article: articles[i],
                categoryIcon: cat?.icon ?? '',
                accent: categoryColor(cat?.color),
              );
            },
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📖', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            Text(tr('Bu bölümde henüz yazı yok'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
