import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/community_repository.dart';
import '../../models/community.dart';
import '../content/content_ui.dart' show parseHexColor;
import 'community_ui.dart';

/// Bir üyenin herkese açık topluluk profili — avatar + ad + istatistik +
/// anonim olmayan soruları. Yazara tıklayınca açılır.
class CommunityProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const CommunityProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<CommunityProfileScreen> createState() =>
      _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends ConsumerState<CommunityProfileScreen> {
  CommunityProfile? _p;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p =
          await ref.read(communityRepositoryProvider).userProfile(widget.userId);
      if (mounted) setState(() => _p = p);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Profil')),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(apiErrorText(_error!),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.muted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _load();
                      },
                      child: Text(tr('Tekrar dene')),
                    ),
                  ],
                ),
              ),
            )
          : _p == null
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: const [
                    Skeleton(height: 96, radius: 18),
                    SizedBox(height: 14),
                    Skeleton(height: 110, radius: 16),
                    SizedBox(height: 12),
                    Skeleton(height: 110, radius: 16),
                  ],
                )
              : _content(_p!),
    );
  }

  Widget _content(CommunityProfile p) {
    return RefreshIndicator(
      color: AppColors.coral,
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          _Header(profile: p),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 0, 3, 10),
            child: Text(tr('SORULARI'),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.muted,
                    letterSpacing: 0.7)),
          ),
          if (p.questions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(tr('Henüz herkese açık soru yok.'),
                  style: TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
          for (final q in p.questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: QuestionCard(question: q),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CommunityProfile profile;
  const _Header({required this.profile});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final c = parseHexColor(p.color) ?? AppColors.coral;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
                (p.name.isNotEmpty ? p.name.characters.first : '?').toUpperCaseTr(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(
                    trp('{q} soru · {a} cevap',
                        {'q': p.questionCount, 'a': p.answerCount}),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
