import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/adena_icons.dart';
import '../../core/age.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/article.dart';
import '../../models/baby.dart';

/// Bebeğin yaşını ay olarak verir (bekleme modu/doğum yok → null).
/// İçerik önerileri yaşa göre filtrelendiği için prematüre bebeklerde
/// düzeltilmiş yaş kullanılır ([correctedAgeMonths]); term bebekte takvim
/// yaşına eşittir. Saf / test edilebilir.
int? babyAgeMonths(Baby? b) => correctedAgeMonths(b);

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

/// Yatay şerit kartının sabit yüksekliği (hub şeritleri + skeleton aynı değeri
/// kullanır — kart içeriğiyle birlikte güncellenmeli).
const double kArticleStripHeight = 172;

/// Tek makale kartı. [width] verilirse yatay şeritte sabit genişlik; null ise
/// tam genişlik (dikey liste). İçerikte görsel KULLANMIYORUZ → varsayılan
/// görünüm kompakttır (küçük kategori-renkli ikon çipi); dev 16:9 placeholder
/// çizilmez. Kapak görseli yalnız gerçekten varsa ve tam-genişlik kartta
/// gösterilir. [accent] kategori vurgu rengi (yoksa mercan).
class ArticleCard extends StatelessWidget {
  final Article article;
  final String categoryIcon;
  final double? width;
  final Color? accent;
  const ArticleCard({
    super.key,
    required this.article,
    this.categoryIcon = '',
    this.width,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final a = accent ?? AppColors.coralDd;
    final horizontal = width != null;
    final showCover = !horizontal && article.coverImage != null;

    final card = Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/content/article/${article.slug}'),
        child: showCover
            ? _coverLayout(context, a)
            : (horizontal ? _stripLayout(a) : _rowLayout(a)),
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

  /// Kategori ikonu çipi — "görsel" yerine kimliği taşıyan küçük plaka.
  Widget _chip(Color a, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: a.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        child: AdenaIcon(categoryIcon.isEmpty ? 'star' : categoryIcon,
            size: size * 0.48, color: a, sw: 1.9),
      );

  Widget _categoryLabel() => Text(article.categoryName.toUpperCaseTr(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: AppColors.muted));

  Widget _title({int lines = 2}) => Text(article.title,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
          fontSize: 14.5, height: 1.25, fontWeight: FontWeight.w900));

  Widget _summary({int lines = 2}) => Text(article.summary,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: AppColors.muted));

  Widget _meta() => Row(
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
                ageRangeLabel(article.ageMinMonth, article.ageMaxMonth),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted2)),
          ),
        ],
      );

  /// Yatay şerit mini kartı: çip + kategori üstte, başlık/özet/meta altta.
  Widget _stripLayout(Color a) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _chip(a, 40),
                const SizedBox(width: 9),
                Expanded(child: _categoryLabel()),
              ],
            ),
            const SizedBox(height: 10),
            _title(),
            if (article.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Expanded(child: _summary()),
            ] else
              const Spacer(),
            const SizedBox(height: 8),
            _meta(),
          ],
        ),
      );

  /// Tam genişlik satır kartı: çip solda, metin sağda (görselsiz varsayılan).
  Widget _rowLayout(Color a) => Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chip(a, 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _categoryLabel(),
                  const SizedBox(height: 3),
                  _title(),
                  if (article.summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _summary(),
                  ],
                  const SizedBox(height: 8),
                  _meta(),
                ],
              ),
            ),
          ],
        ),
      );

  /// Kapak görselli tam-genişlik kart (yalnız gerçek görsel varsa).
  Widget _coverLayout(BuildContext context, Color a) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              child: Image.network(article.coverImage!,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, _, _) => ColoredBox(
                      color: a.withValues(alpha: 0.12),
                      child: Center(child: _chip(a, 48)))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _categoryLabel(),
                const SizedBox(height: 4),
                _title(),
                if (article.summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _summary(),
                ],
                const SizedBox(height: 8),
                _meta(),
              ],
            ),
          ),
        ],
      );
}
