import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/community.dart';
import '../content/content_ui.dart' show parseHexColor;

/// Topluluk yeşili (tasarım: açık #2C9E6B / koyu #7BD8AC) — en iyi cevap, oy.
Color get bestGreen => AppColors.brightness == Brightness.dark
    ? const Color(0xFF7BD8AC)
    : const Color(0xFF2C9E6B);

/// Kısa göreli zaman ("az önce", "5 dk", "3 sa", "2 gün", sonra tarih).
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('az önce');
  if (d.inMinutes < 60) return trp('{n} dk', {'n': d.inMinutes});
  if (d.inHours < 24) return trp('{n} sa', {'n': d.inHours});
  if (d.inDays < 7) return trp('{n} gün', {'n': d.inDays});
  return '${t.day}.${t.month}.${t.year}';
}

/// Yazar satırı (design .ad-qwho) — küçük renkli avatar (baş harf) + ad +
/// göreli zaman. Anonimse nötr gri avatar + "Anonim". [isMine] → "(sen)".
class AuthorRow extends StatelessWidget {
  final String name;
  final String color;
  final bool anonymous;
  final bool isMine;
  final DateTime time;
  final String? authorId; // verilirse ada tıklayınca profil açılır (anonimde null)
  const AuthorRow({
    super.key,
    required this.name,
    required this.color,
    required this.anonymous,
    required this.time,
    this.isMine = false,
    this.authorId,
  });

  @override
  Widget build(BuildContext context) {
    // Anonim: nötr gri zemin (--line-2) + soluk kullanıcı ikonu.
    final c = anonymous ? AppColors.line2 : (parseHexColor(color) ?? AppColors.coral);
    final label = (anonymous ? tr('Anonim') : name) + (isMine ? tr(' (sen)') : '');
    final row = Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: anonymous
              ? AdenaIcon('user', size: 11, color: AppColors.muted, sw: 2.4)
              : Text(
                  (name.isNotEmpty ? name.characters.first : '?').toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.ink2)),
        ),
        const SizedBox(width: 6),
        Text('· ${relativeTime(time)}',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ],
    );
    // Kendi olmayan, kimliği açık yazara tıklayınca profil aç.
    if (authorId == null || isMine) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/community/user/$authorId'),
      child: row,
    );
  }
}

/// Dikey oy kontrolü (design .ad-vote) — yukarı/aşağı arrowUp + skor.
/// [myVote] -1|0|1; aynı yöne tekrar basınca oy kaldırılır (0).
class VoteControl extends StatelessWidget {
  final int score;
  final int myVote;
  final ValueChanged<int> onVote; // gönderilen yeni değer: 1, -1 veya 0
  const VoteControl(
      {super.key, required this.score, required this.myVote, required this.onVote});

  @override
  Widget build(BuildContext context) {
    final up = myVote == 1;
    final down = myVote == -1;
    final restBg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      width: 32,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(
            flip: false,
            bg: up ? AppColors.growthBg : restBg,
            color: up ? bestGreen : AppColors.muted2,
            onTap: () => onVote(up ? 0 : 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('$score',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: up ? bestGreen : AppColors.ink)),
          ),
          _btn(
            flip: true,
            bg: down ? AppColors.feverBg : restBg,
            color: down ? AppColors.coralDd : AppColors.muted2,
            onTap: () => onVote(down ? 0 : -1),
          ),
        ],
      ),
    );
  }

  Widget _btn(
      {required bool flip,
      required Color bg,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 27,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: flip ? 3.14159 : 0,
          child: AdenaIcon('arrowUp', size: 15, color: color, sw: 2.4),
        ),
      ),
    );
  }
}

/// "En iyi cevap" rozeti.
class BestBadge extends StatelessWidget {
  const BestBadge({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.growthBg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdenaIcon('check', size: 11, color: bestGreen, sw: 3),
          const SizedBox(width: 4),
          Text(tr('En iyi cevap'),
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w900, color: bestGreen)),
        ],
      ),
    );
  }
}

/// Kendi içeriği (soru/cevap) için Düzenle/Sil menüsü — kompakt "⋯" düğmesi.
class OwnerMenu extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const OwnerMenu({super.key, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: tr('Seçenekler'),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      icon: AdenaIcon('more', size: 17, color: AppColors.muted2),
      onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            AdenaIcon('edit', size: 16, color: AppColors.ink2),
            const SizedBox(width: 10),
            Text(tr('Düzenle'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            AdenaIcon('trash', size: 16, color: AppColors.coralDd),
            const SizedBox(width: 10),
            Text(tr('Sil'),
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.coralDd)),
          ]),
        ),
      ],
    );
  }
}

/// Sil onayı ister (kırmızı eylem). Onaylanırsa true döner.
Future<bool> showDeleteConfirm(BuildContext context,
    {required String title, required String message}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Sil'),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Vazgeç'),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.muted)),
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// Cevap düzenleme sheet'i — mevcut gövdeyi düzenletir, yeni gövdeyi döndürür
/// (iptal/boş = null).
Future<String?> showEditAnswerSheet(BuildContext context, String current) async {
  final ctl = TextEditingController(text: current);
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 18,
        bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Cevabı düzenle'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(ctx).scaffoldBackgroundColor,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.line, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () {
              final v = ctl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: Text(tr('Kaydet'),
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    ),
  );
  ctl.dispose();
  return result;
}

/// Tek soru kartı — skor + başlık + özet + kategori + cevap sayısı. Feed ve
/// profil ekranı paylaşır. [onTap] verilmezse soru detayını açar.
class QuestionCard extends StatelessWidget {
  final Question question;
  final VoidCallback? onTap;
  const QuestionCard({super.key, required this.question, this.onTap});

  @override
  Widget build(BuildContext context) {
    final q = question;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ?? () => context.push('/community/question/${q.id}'),
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
                  if (q.categoryName != null) _CatTag(q.categoryName!),
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
                      authorId: q.authorId,
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

/// Şikayet sebebi seçtiren sheet → seçilen sebep kodunu döndürür (iptal=null).
Future<String?> showReportSheet(BuildContext context) async {
  const reasons = [
    ('spam', 'Spam / reklam'),
    ('abuse', 'Hakaret / taciz'),
    ('misinfo', 'Yanlış / tehlikeli bilgi'),
    ('other', 'Diğer'),
  ];
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Text(tr('Neden şikayet ediyorsun?'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final (code, label) in reasons)
            ListTile(
              title: Text(tr(label),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, code),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
