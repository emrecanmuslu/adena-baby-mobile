import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/content_repository.dart';
import '../../models/article.dart';
import '../babies/baby_controller.dart';
import 'article_list_screen.dart';
import 'content_ui.dart';

/// Uzman Rehberi hub'ı: bebeğin yaşına uygun öneriler + kategori şeritleri.
/// Admin-yönetimli makaleler (salt okunur). Sağlık Hub ve Ana sayfadan köprü.
class ContentHubScreen extends ConsumerWidget {
  const ContentHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    final age = babyAgeMonths(baby);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(tr('Uzman Rehberi')),
            const SizedBox(width: 8),
            AdInfoDot(
              title: tr('Uzman Rehberi'),
              body: tr('Uzman onaylı bakım ve gelişim rehberleri. Bebeğinin '
                  'yaşına uygun öneriler en üstte. İçerikler genel bilgilendirme '
                  'amaçlıdır; tıbbi tanı yerine geçmez.'),
              size: 16,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          if (age != null) _AgeStrip(ageMonths: age),
          _CategoriesSection(),
        ],
      ),
    );
  }
}

/// "Bebeğine uygun" yatay öneri şeridi (yaşa göre filtreli makaleler).
class _AgeStrip extends ConsumerWidget {
  final int ageMonths;
  const _AgeStrip({required this.ageMonths});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(articlesProvider((category: null, ageMonths: ageMonths)));
    final cats = ref.watch(contentCategoriesProvider).asData?.value ?? const [];

    return async.when(
      loading: () => const _StripSkeleton(),
      error: (e, _) => const SizedBox.shrink(),
      data: (articles) {
        if (articles.isEmpty) return const SizedBox.shrink();
        final shown = articles.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 14, 3, 10),
              child: Row(
                children: [
                  Text(tr('BEBEĞİNE UYGUN'),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.muted,
                          letterSpacing: 0.7)),
                  const SizedBox(width: 6),
                  AdInfoDot(
                    title: tr('Yaşa uygun öneriler'),
                    body: tr('Bebeğinin şu anki yaşına denk gelen rehberler. '
                        'Yaş büyüdükçe öneriler otomatik güncellenir.'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 274,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => ArticleCard(
                  article: shown[i],
                  categoryIcon: _iconFor(shown[i].categorySlug, cats),
                  width: 230,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _iconFor(String slug, List<ArticleCategory> cats) =>
      cats.where((c) => c.slug == slug).firstOrNull?.icon ?? '';
}

/// Kategori listesi (AdMenuItem satırları) — dokun → kategori makale listesi.
class _CategoriesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contentCategoriesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        adSec(tr('Kategoriler')),
        async.when(
          loading: () => Column(
            children: [
              for (var i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Skeleton(height: 64, radius: 16),
                ),
            ],
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(apiErrorText(e),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
          ),
          data: (cats) {
            if (cats.isEmpty) return const _Empty();
            return Column(
              children: [
                for (final c in cats)
                  AdMenuItem(
                    icon: c.icon.isEmpty ? 'star' : c.icon,
                    color: categoryColor(c.color),
                    bg: categoryColor(c.color).withValues(alpha: 0.14),
                    title: c.name,
                    meta: trp('{n} yazı', {'n': c.articleCount}),
                    onTap: () => context.push(
                      '/content/articles',
                      extra: ArticleListArgs(
                          categorySlug: c.slug, title: c.name),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StripSkeleton extends StatelessWidget {
  const _StripSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: SizedBox(
        height: 274,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: const [
            SizedBox(width: 230, child: Skeleton(height: 274, radius: 18)),
            SizedBox(width: 12),
            SizedBox(width: 230, child: Skeleton(height: 274, radius: 18)),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Text('📚', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(tr('Henüz içerik yok'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('Uzman rehberleri yakında burada olacak.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
