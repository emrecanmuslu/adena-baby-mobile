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
import '../../models/community.dart';
import 'ask_question_sheet.dart';
import 'community_ui.dart';

/// Soru detayı — soru + cevaplar + oylama + en iyi cevap + şikayet + cevap yaz.
/// Etkileşimli olduğu için durumu yerelde tutar (Riverpod cache'i yerine).
class QuestionDetailScreen extends ConsumerStatefulWidget {
  final String questionId;
  const QuestionDetailScreen({super.key, required this.questionId});

  @override
  ConsumerState<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen> {
  final _answer = TextEditingController();
  Question? _q;
  Object? _error;
  bool _sending = false;

  CommunityRepository get _repo => ref.read(communityRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final q = await _repo.question(widget.questionId);
      if (mounted) setState(() { _q = q; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  // ── Oylama (yerel iyimser değil; sunucu yanıtını uygular) ──
  Future<void> _voteQuestion(int value) async {
    try {
      final r = await _repo.vote(
          targetType: 'question', targetId: _q!.id, value: value);
      setState(() => _q = _q!.copyWith(score: r.score, myVote: r.myVote));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _voteAnswer(Answer a, int value) async {
    try {
      final r = await _repo.vote(
          targetType: 'answer', targetId: a.id, value: value);
      setState(() {
        _q = _q!.copyWith(
          answers: [
            for (final x in _q!.answers)
              x.id == a.id ? x.copyWith(score: r.score, myVote: r.myVote) : x,
          ],
        );
      });
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _setBest(Answer a) async {
    try {
      await _repo.setBest(_q!.id, a.id);
      setState(() {
        final answers = [
          for (final x in _q!.answers) x.copyWith(isBest: x.id == a.id),
        ]..sort((p, n) => p.isBest == n.isBest
            ? n.score.compareTo(p.score)
            : (p.isBest ? -1 : 1));
        _q = _q!.copyWith(bestAnswerId: a.id, answers: answers);
      });
      ref.invalidate(communityFeedProvider); // akışta "Çözüldü" rozeti güncel
      if (mounted) showAdToast(context, tr('En iyi cevap işaretlendi ✓'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _submitAnswer() async {
    final body = _answer.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    FocusScope.of(context).unfocus();
    try {
      await _repo.createAnswer(_q!.id, body);
      _answer.clear();
      ref.invalidate(communityFeedProvider); // akışta cevap sayısı güncel
      await _load(); // cevaplar yeniden yüklensin (sıra/sayı güncel)
      if (mounted) showAdToast(context, tr('Cevabın eklendi 💬'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Kendi içeriğini yönet (düzenle/sil) ──
  Future<void> _editQuestion() async {
    final r = await showAskQuestionSheet(context, ref, edit: _q);
    if (r != null) {
      ref.invalidate(communityFeedProvider); // akıştaki başlık/kategori güncel
      await _load();
    }
  }

  Future<void> _deleteQuestion() async {
    final ok = await showDeleteConfirm(context,
        title: tr('Soru silinsin mi?'),
        message: tr('Bu soru ve tüm cevapları kalıcı olarak silinecek.'));
    if (!ok) return;
    try {
      await _repo.deleteQuestion(_q!.id);
      ref.invalidate(communityFeedProvider);
      if (mounted) {
        context.pop();
        showAdToast(context, tr('Soru silindi'));
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _editAnswer(Answer a) async {
    final body = await showEditAnswerSheet(context, a.body);
    if (body == null || body == a.body) return;
    try {
      await _repo.updateAnswer(a.id, body);
      await _load();
      if (mounted) showAdToast(context, tr('Cevap güncellendi ✓'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _deleteAnswer(Answer a) async {
    final ok = await showDeleteConfirm(context,
        title: tr('Cevap silinsin mi?'),
        message: tr('Bu cevap kalıcı olarak silinecek.'));
    if (!ok) return;
    try {
      await _repo.deleteAnswer(a.id);
      ref.invalidate(communityFeedProvider); // cevap sayısı değişti
      await _load();
      if (mounted) showAdToast(context, tr('Cevap silindi'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _report(String targetType, String targetId,
      {bool isQuestion = false}) async {
    final reason = await showReportSheet(context);
    if (reason == null) return;
    try {
      await _repo.report(
          targetType: targetType, targetId: targetId, reason: reason);
      if (!mounted) return;
      showAdToast(context, tr('Şikayetin alındı, teşekkürler.'));
      if (isQuestion) {
        context.pop();
      } else {
        await _load();
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Soru')),
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
          : _q == null
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: const [
                    Skeleton(height: 140, radius: 16),
                    SizedBox(height: 12),
                    Skeleton(height: 90, radius: 16),
                    SizedBox(height: 12),
                    Skeleton(height: 90, radius: 16),
                  ],
                )
              : _content(),
    );
  }

  Widget _content() {
    final q = _q!;
    final answers = q.answers;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppColors.coral,
            onRefresh: _load,
            child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _QuestionBlock(
                q: q,
                onVote: _voteQuestion,
                onReport: () => _report('question', q.id, isQuestion: true),
                onEdit: _editQuestion,
                onDelete: _deleteQuestion,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(3, 4, 3, 10),
                child: Text(
                    answers.isEmpty
                        ? tr('Henüz cevap yok')
                        : trp('{n} CEVAP', {'n': answers.length}),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.muted,
                        letterSpacing: 0.7)),
              ),
              if (answers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(tr('İlk cevabı sen yaz — deneyimini paylaş.'),
                      style: TextStyle(
                          color: AppColors.muted, fontWeight: FontWeight.w600)),
                ),
              for (final a in answers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AnswerTile(
                    answer: a,
                    canPickBest: q.isMine,
                    onVote: (v) => _voteAnswer(a, v),
                    onBest: () => _setBest(a),
                    onReport: () => _report('answer', a.id),
                    onEdit: () => _editAnswer(a),
                    onDelete: () => _deleteAnswer(a),
                  ),
                ),
            ],
          ),
          ),
        ),
        _Composer(
          controller: _answer,
          sending: _sending,
          onSend: _submitAnswer,
        ),
      ],
    );
  }
}

/// Soru başlık bloğu — oy sütunu + başlık/gövde + kategori + yazar + şikayet.
class _QuestionBlock extends StatelessWidget {
  final Question q;
  final ValueChanged<int> onVote;
  final VoidCallback onReport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _QuestionBlock(
      {required this.q,
      required this.onVote,
      required this.onReport,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VoteControl(
              score: q.score, myVote: q.myVote, enabled: !q.isMine, onVote: onVote),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (q.categoryName != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.peachLight,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(q.categoryName!.toUpperCaseTr(),
                          style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: AppColors.coralDd)),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(q.title,
                    style: const TextStyle(
                        fontSize: 16, height: 1.3, fontWeight: FontWeight.w900)),
                if (q.body.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(q.body,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.55,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
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
                        authorId: q.authorId,
                        time: q.createdAt,
                      ),
                    ),
                    if (q.isMine)
                      OwnerMenu(onEdit: onEdit, onDelete: onDelete)
                    else
                      _ReportButton(onTap: onReport),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek cevap — oy sütunu + gövde + yazar + en iyi rozeti/seçimi + şikayet.
class _AnswerTile extends StatelessWidget {
  final Answer answer;
  final bool canPickBest;
  final ValueChanged<int> onVote;
  final VoidCallback onBest;
  final VoidCallback onReport;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AnswerTile({
    required this.answer,
    required this.canPickBest,
    required this.onVote,
    required this.onBest,
    required this.onReport,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final a = answer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: a.isBest ? AppColors.growth : Colors.transparent, width: 1.6),
        boxShadow: a.isBest
            ? const [
                BoxShadow(
                    color: Color(0x2952BA8E), blurRadius: 20, offset: Offset(0, 8)),
              ]
            : AppColors.smallShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VoteControl(
              score: a.score, myVote: a.myVote, enabled: !a.isMine, onVote: onVote),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.isBest)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 7),
                    child: BestBadge(),
                  ),
                Text(a.body,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink2)),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: AuthorRow(
                        name: a.authorName,
                        color: a.authorColor,
                        anonymous: a.isAnonymous,
                        isMine: a.isMine,
                        authorId: a.authorId,
                        time: a.createdAt,
                      ),
                    ),
                    if (canPickBest && !a.isBest)
                      GestureDetector(
                        onTap: onBest,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AdenaIcon('check', size: 13, color: bestGreen, sw: 2.6),
                              const SizedBox(width: 4),
                              Text(tr('En iyi seç'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: bestGreen)),
                            ],
                          ),
                        ),
                      ),
                    if (a.isMine)
                      OwnerMenu(onEdit: onEdit, onDelete: onDelete)
                    else
                      _ReportButton(onTap: onReport),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ReportButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: AdenaIcon('shieldAlert', size: 15, color: AppColors.muted2),
      ),
    );
  }
}

/// Alt cevap yazma çubuğu.
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer(
      {required this.controller, required this.sending, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 8,
          bottom: 8 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: AppColors.line, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: tr('Cevap yaz…'),
                  hintStyle: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(19),
                    borderSide: BorderSide(color: AppColors.line, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(19),
                    borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            GestureDetector(
              onTap: sending ? null : onSend,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.coral,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Color(0x59E2553F),
                        blurRadius: 14,
                        offset: Offset(0, 6)),
                  ],
                ),
                alignment: Alignment.center,
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const AdenaIcon('send',
                        size: 18, color: Colors.white, sw: 2.0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
