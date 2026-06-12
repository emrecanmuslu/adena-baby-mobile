import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/article.dart';
import '../../models/baby.dart';

/// Bebeğin yaşını ay olarak verir (bekleme modu/doğum yok → null).
int? babyAgeMonths(Baby? b) {
  if (b == null || b.isExpecting) return null;
  final bd = b.birthDate;
  if (bd == null) return null;
  final now = DateTime.now();
  var m = (now.year - bd.year) * 12 + (now.month - bd.month);
  if (now.day < bd.day) m -= 1;
  return m < 0 ? 0 : m;
}

/// "#9B8CE8" → Color (geçersizse null).
Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceFirst('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Kategori vurgu rengi — sunucu hex'i yoksa mercan.
Color categoryColor(String? hex) => parseHexColor(hex) ?? AppColors.coralDd;

/// Yaş aralığını okunur etikete çevirir ("0-6 ay", "1 yaş+", "Her yaş").
String ageRangeLabel(int minM, int maxM) {
  if (minM <= 0 && maxM >= 240) return tr('Her yaş');
  String fmt(int m) => m >= 24
      ? trp('{n} yaş', {'n': m ~/ 12})
      : trp('{n} ay', {'n': m});
  if (maxM >= 240) return '${fmt(minM)}+';
  if (minM <= 0) return '${fmt(maxM)}${tr('a kadar')}';
  return '${fmt(minM)} – ${fmt(maxM)}';
}

/// Tek makale kartı. [width] verilirse yatay şeritte sabit genişlik; null ise
/// tam genişlik (dikey liste). Kapak yoksa kategori renginde degrade + ikon.
class ArticleCard extends StatelessWidget {
  final Article article;
  final String categoryIcon;
  final double? width;
  const ArticleCard({
    super.key,
    required this.article,
    this.categoryIcon = '',
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/content/article/${article.slug}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: _Cover(article: article, icon: categoryIcon),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(article.categoryName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.25,
                          fontWeight: FontWeight.w900)),
                  if (article.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(article.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AdenaIcon('clock', size: 12, color: AppColors.muted2),
                      const SizedBox(width: 4),
                      Text(trp('{n} dk', {'n': article.readMinutes}),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.muted2)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                            ageRangeLabel(
                                article.ageMinMonth, article.ageMaxMonth),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.muted2)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.softShadow,
      ),
      child: card,
    );
    return width != null ? SizedBox(width: width, child: shadowed) : shadowed;
  }
}

/// Kapak görseli — varsa ağ resmi, yoksa kategori ikonlu degrade placeholder.
class _Cover extends StatelessWidget {
  final Article article;
  final String icon;
  const _Cover({required this.article, required this.icon});

  @override
  Widget build(BuildContext context) {
    if (article.coverImage != null) {
      return Image.network(article.coverImage!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder());
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final dark = AppColors.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF2E2740), Color(0xFF3A2A2E)]
              : const [Color(0xFFFFE9DF), Color(0xFFFFD9CC)],
        ),
      ),
      child: Center(
        child: AdenaIcon(icon.isEmpty ? 'star' : icon,
            size: 34, color: AppColors.coralDd, sw: 1.7),
      ),
    );
  }
}
