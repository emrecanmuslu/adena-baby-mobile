import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/community_repository.dart';
import '../../data/content_repository.dart';
import '../../models/community.dart';
import 'ask_question_sheet.dart';
import 'community_ui.dart';

/// Topluluk akışı — kızlarsoruyor tarzı soru-cevap. Sıralama (yeni/popüler) +
/// kategori filtresi + soru kartları. FAB ile soru sor.
class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  String _sort = 'new';
  String? _category; // null = tümü

  @override
  Widget build(BuildContext context) {
    final async =
        ref.watch(communityFeedProvider((category: _category, sort: _sort)));
    final cats = ref.watch(contentCategoriesProvider).asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(tr('Topluluk')),
            const SizedBox(width: 8),
            AdInfoDot(
              title: tr('Ebeveyn Topluluğu'),
              body: tr('Diğer ebeveynlere soru sor, deneyim paylaş. Yanıtları '
                  'oyla, soruna gelen en iyi cevabı işaretle. Saygılı ol; '
                  'uygunsuz içeriği şikayet edebilirsin. Tıbbi konularda '
                  'doktoruna danışmayı unutma.'),
              size: 16,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _ask(context),
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        icon: const AdenaIcon('plus', size: 20, color: Colors.white, sw: 2.4),
        label: Text(tr('Soru sor'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Column(
        children: [
          _SortBar(
            sort: _sort,
            onSort: (s) => setState(() => _sort = s),
          ),
          _CategoryChips(
            categories: cats,
            selected: _category,
            onSelect: (slug) => setState(() => _category = slug),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.coral,
              onRefresh: () async => ref.invalidate(
                  communityFeedProvider((category: _category, sort: _sort))),
              child: async.when(
                loading: () => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    for (var i = 0; i < 5; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Skeleton(height: 110, radius: 16),
                      ),
                  ],
                ),
                error: (e, _) => ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(apiErrorText(e),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.muted, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                data: (items) {
                  if (items.isEmpty) return const _Empty();
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        16, 8, 16, 96 + MediaQuery.of(context).padding.bottom),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _QuestionCard(question: items[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _ask(BuildContext context) async {
    final newId = await showAskQuestionSheet(context, ref);
    if (newId != null) {
      ref.invalidate(communityFeedProvider((category: _category, sort: _sort)));
      if (context.mounted) context.push('/community/question/$newId');
    }
  }
}

/// Yeni / Popüler sıralama çubuğu (design .ad-cm-sort) — kompakt haplar.
class _SortBar extends StatelessWidget {
  final String sort;
  final ValueChanged<String> onSort;
  const _SortBar({required this.sort, required this.onSort});

  @override
  Widget build(BuildContext context) {
    Widget tab(String key, String label) {
      final sel = sort == key;
      return GestureDetector(
        onTap: () => onSort(key),
        child: Container(
          margin: const EdgeInsets.only(right: 5),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? AppColors.peachLight : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: sel ? AppColors.smallShadow : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: sel ? AppColors.coralDd : AppColors.muted)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(children: [tab('new', tr('Yeni')), tab('top', tr('Popüler'))]),
    );
  }
}

/// Kategori filtre çipleri ("Tümü" + uzman içeriği kategorileri).
class _CategoryChips extends StatelessWidget {
  final List categories; // ArticleCategory
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _CategoryChips(
      {required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget chip(String? slug, String label) {
      final sel = selected == slug;
      // Yatay ListView çocukları üste yaslar → Center ile dikeyde ortala.
      return Center(
        child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onSelect(slug),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? AppColors.peachLight : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: sel ? AppColors.coral : AppColors.line, width: 1.5),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: sel ? AppColors.coralDd : AppColors.ink2)),
          ),
        ),
      ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 24, 0),
        children: [
          chip(null, tr('Tümü')),
          for (final c in categories) chip(c.slug as String, c.name as String),
        ],
      ),
    );
  }
}

/// Tek soru kartı — skor + başlık + özet + kategori + cevap sayısı.
class _QuestionCard extends StatelessWidget {
  final Question question;
  const _QuestionCard({required this.question});

  @override
  Widget build(BuildContext context) {
    final q = question;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/community/question/${q.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.softShadow,
          ),
          padding: const EdgeInsets.fromLTRB(15, 13, 15, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (q.categoryName != null)
                    _CatTag(q.categoryName!),
                  const Spacer(),
                  if (q.hasBest)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.growthBg,
                          borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AdenaIcon('check', size: 11, color: bestGreen, sw: 3),
                          const SizedBox(width: 4),
                          Text(tr('Çözüldü'),
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: bestGreen)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 9),
              Text(q.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14.5, height: 1.32, fontWeight: FontWeight.w900)),
              if (q.body.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(q.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
              ],
              const SizedBox(height: 11),
              Row(
                children: [
                  Expanded(
                    child: AuthorRow(
                      name: q.authorName,
                      color: q.authorColor,
                      anonymous: q.isAnonymous,
                      isMine: q.isMine,
                      time: q.createdAt,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _QStat(icon: 'arrowUp', label: '${q.score}', highlight: q.myVote == 1),
                  const SizedBox(width: 12),
                  _QStat(icon: 'comment', label: '${q.answerCount}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kategori etiketi (design .ad-cattag) — peach-l zemin, coral-dd, büyük harf.
class _CatTag extends StatelessWidget {
  final String text;
  const _CatTag(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.peachLight, borderRadius: BorderRadius.circular(999)),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: AppColors.coralDd)),
    );
  }
}

/// Soru kartı istatistiği (design .ad-qstat) — ikon + sayı; oylanınca yeşil.
class _QStat extends StatelessWidget {
  final String icon;
  final String label;
  final bool highlight;
  const _QStat({required this.icon, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final c = highlight ? bestGreen : AppColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdenaIcon(icon, size: 14, color: c, sw: icon == 'arrowUp' ? 2.4 : 2.0),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: c)),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
          child: Column(
            children: [
              const Text('💬', style: TextStyle(fontSize: 54)),
              const SizedBox(height: 10),
              Text(tr('Henüz soru yok'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  tr('İlk soruyu sen sor — deneyimli ebeveynler ve uzmanlar '
                      'cevaplamak için burada.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
