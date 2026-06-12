import 'package:flutter/material.dart';

import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
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
  const AuthorRow({
    super.key,
    required this.name,
    required this.color,
    required this.anonymous,
    required this.time,
    this.isMine = false,
  });

  @override
  Widget build(BuildContext context) {
    // Anonim: nötr gri zemin (--line-2) + soluk kullanıcı ikonu.
    final c = anonymous ? AppColors.line2 : (parseHexColor(color) ?? AppColors.coral);
    final label = (anonymous ? tr('Anonim') : name) + (isMine ? tr(' (sen)') : '');
    return Row(
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
