import 'dart:async';

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

/// Topluluk akışı — kızlarsoruyor tarzı soru-cevap. Arama + sıralama (yeni/
/// popüler) + kategori filtresi + sonsuz kaydırma (sayfalı). FAB ile soru sor.
class CommunityFeedScreen extends ConsumerStatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  ConsumerState<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends ConsumerState<CommunityFeedScreen> {
  static const _pageSize = 20;

  String _sort = 'new';
  String? _category; // null = tümü
  String _search = '';
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  final _scroll = ScrollController();
  final List<Question> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _fetch(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _hasMore = true;
      });
    } else {
      if (_loadingMore || !_hasMore || _loading) return;
      setState(() => _loadingMore = true);
    }
    final offset = reset ? 0 : _items.length;
    try {
      final page = await _repo.feed(
          category: _category,
          sort: _sort,
          search: _search,
          offset: offset,
          limit: _pageSize);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(page);
        } else {
          _items.addAll(page);
        }
        _hasMore = page.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _fetch();
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final s = v.trim();
      if (s == _search) return;
      _search = s;
      _fetch(reset: true);
    });
  }

  void _setSort(String s) {
    if (s == _sort) return;
    setState(() => _sort = s);
    _fetch(reset: true);
  }

  void _setCategory(String? c) {
    if (c == _category) return;
    setState(() => _category = c);
    _fetch(reset: true);
  }

  @override
  Widget build(BuildContext context) {
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
          _SearchBar(
            controller: _searchCtl,
            onChanged: _onSearchChanged,
            onClear: () {
              _searchCtl.clear();
              _onSearchChanged('');
            },
          ),
          _SortBar(sort: _sort, onSort: _setSort),
          _CategoryChips(
              categories: cats, selected: _category, onSelect: _setCategory),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.coral,
              onRefresh: () => _fetch(reset: true),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Skeleton(height: 110, radius: 16),
            ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 12),
            child: Column(
              children: [
                Text(apiErrorText(_error!),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => _fetch(reset: true),
                  child: Text(tr('Tekrar dene')),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return _Empty(searching: _search.isNotEmpty);
    }
    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 96 + MediaQuery.of(context).padding.bottom),
      itemCount: _items.length + 1, // +1 = alt yükleniyor/bitti göstergesi
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i == _items.length) return _footer();
        final q = _items[i];
        return QuestionCard(
          question: q,
          onTap: () async {
            await context.push('/community/question/${q.id}');
            if (mounted) _fetch(reset: true); // detayda değişmiş olabilir
          },
        );
      },
    );
  }

  Widget _footer() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.coral),
          ),
        ),
      );
    }
    if (!_hasMore && _items.length > _pageSize) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text(tr('Hepsi bu kadar'),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
        ),
      );
    }
    return const SizedBox(height: 4);
  }

  Future<void> _ask(BuildContext context) async {
    final newId = await showAskQuestionSheet(context, ref);
    if (newId != null && newId != 'edited') {
      await _fetch(reset: true);
      if (context.mounted) context.push('/community/question/$newId');
    }
  }
}

/// Arama çubuğu — başlık/gövdede ara (sunucu taraflı, debounce'lu).
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBar(
      {required this.controller, required this.onChanged, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('Soru ara…'),
          hintStyle: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.muted),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
          suffixIcon: ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                    onPressed: onClear,
                  ),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: AppColors.line, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
          ),
        ),
      ),
    );
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
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
                color:
                    sel ? AppColors.peachLight : Theme.of(context).colorScheme.surface,
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

class _Empty extends StatelessWidget {
  final bool searching;
  const _Empty({this.searching = false});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
          child: Column(
            children: [
              Text(searching ? '🔍' : '💬', style: const TextStyle(fontSize: 54)),
              const SizedBox(height: 10),
              Text(searching ? tr('Sonuç bulunamadı') : tr('Henüz soru yok'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  searching
                      ? tr('Farklı bir kelimeyle aramayı dene.')
                      : tr('İlk soruyu sen sor — deneyimli ebeveynler ve uzmanlar '
                          'cevaplamak için burada.'),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
