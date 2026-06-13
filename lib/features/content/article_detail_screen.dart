import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_markdown.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/content_repository.dart';
import 'content_ui.dart';

/// Makale detay — kapak/başlık + üst veri + Markdown gövde + tıbbi uyarı.
class ArticleDetailScreen extends ConsumerWidget {
  final String slug;
  const ArticleDetailScreen({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(articleProvider(slug));
    final cats = ref.watch(contentCategoriesProvider).asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(async.asData?.value.categoryName ?? tr('Rehber')),
      ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: const [
            Skeleton(height: 180, radius: 18),
            SizedBox(height: 16),
            Skeleton(width: 240, height: 22),
            SizedBox(height: 10),
            Skeleton(height: 14),
            SizedBox(height: 8),
            Skeleton(height: 14),
            SizedBox(height: 8),
            Skeleton(width: 200, height: 14),
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
        data: (a) {
          final icon = cats.where((c) => c.slug == a.categorySlug)
                  .firstOrNull?.icon ??
              '';
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 28 + MediaQuery.of(context).padding.bottom),
            children: [
              if (a.coverImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(a.coverImage!,
                        fit: BoxFit.cover,
                        cacheWidth: 1080,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ),
                ),
              const SizedBox(height: 14),
              // Kategori + yaş rozetleri
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(icon: icon.isEmpty ? 'star' : icon, label: a.categoryName),
                  _Pill(
                      icon: 'baby',
                      label: ageRangeLabel(a.ageMinMonth, a.ageMaxMonth)),
                  _Pill(
                      icon: 'clock',
                      label: trp('{n} dk okuma', {'n': a.readMinutes})),
                ],
              ),
              const SizedBox(height: 14),
              Text(a.title,
                  style: const TextStyle(
                      fontSize: 24, height: 1.2, fontWeight: FontWeight.w900)),
              if (a.authorName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    AdenaIcon('user', size: 14, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text(a.authorName,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              AdMarkdown(a.body ?? ''),
              const SizedBox(height: 20),
              const _Disclaimer(),
            ],
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.feedBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdenaIcon(icon, size: 13, color: AppColors.coralDd),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.coralDd)),
        ],
      ),
    );
  }
}

/// Tıbbi sorumluluk reddi — her makalenin altında sabit.
class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdenaIcon('shield', size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Bu içerik genel bilgilendirme amaçlıdır ve tıbbi tanı, '
                  'muayene veya tedavinin yerine geçmez. Bebeğinin sağlığıyla '
                  'ilgili kararlarda mutlaka doktoruna danış.'),
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
