import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_markdown.dart';
import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/leaps.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/leap_repository.dart';
import '../../data/leap_weeks.dart';
import '../babies/baby_controller.dart';

/// Tek bir gelişim atağının detayı — halka hero + ikonlu mini kartlar + alıntı
/// (design/Gelişim Atakları.html). Gövde markdown'ı bölümlere ayrıştırılır;
/// beklenmedik yapıda düz markdown'a düşülür.
class LeapDetailScreen extends ConsumerWidget {
  final int index;
  const LeapDetailScreen({super.key, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leapsProvider);
    final baby = ref.watch(activeBabyProvider);
    final weeks = correctedAgeWeeks(baby);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(trp('{n}. Atak', {'n': index})),
            Text(tr('Gelişim Atakları'),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ],
        ),
      ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: const [
            Skeleton(height: 260, radius: 26),
            SizedBox(height: 14),
            Skeleton(height: 14),
            SizedBox(height: 8),
            Skeleton(height: 14),
          ],
        ),
        error: (_, _) => Center(
          child: Text(tr('İçerik yüklenemedi'), style: TextStyle(color: AppColors.muted)),
        ),
        data: (leaps) {
          final leap = leaps.where((l) => l.index == index).firstOrNull;
          if (leap == null) {
            return Center(
              child: Text(tr('Bulunamadı'), style: TextStyle(color: AppColors.muted)),
            );
          }
          final phase =
              weeks == null ? null : leapPhase(weeks, leap.weekStart, leap.fussyWeeksBefore);
          final parsed = _LeapBody.parse(leap.body);
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, 28 + MediaQuery.of(context).padding.bottom),
            children: [
              _DetailHero(leap: leap, phase: phase),
              if (parsed == null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: AdMarkdown(leap.body),
                )
              else ...[
                _ParaCard(text: parsed.intro),
                for (var s = 0; s < parsed.sections.length; s++) ...[
                  _SectionHeader(index: s, title: parsed.sections[s].$1),
                  for (var b = 0; b < parsed.sections[s].$2.length; b++)
                    _MiniCard(section: s, bullet: b, text: parsed.sections[s].$2[b]),
                ],
                if (parsed.quote != null) _QuoteCard(text: parsed.quote!),
              ],
              const SizedBox(height: 20),
              AdMedicalNote(
                text: tr('Bu içerik genel bilgilendirme amaçlıdır; gelişim atakları '
                    'tıbbi bir tanı değildir. Her bebek kendi temposunda gelişir. '
                    'Endişelerin varsa doktoruna danış.'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Gövde markdown ayrıştırma ────────────────────────────────────────────────

/// Beklenen yapı: giriş paragraf(lar)ı, `## Başlık` + `- madde` bölümleri,
/// opsiyonel `> alıntı`. Yapı tutmazsa null → düz [AdMarkdown] kullanılır.
class _LeapBody {
  final String intro;
  final List<(String, List<String>)> sections;
  final String? quote;
  _LeapBody(this.intro, this.sections, this.quote);

  static _LeapBody? parse(String md) {
    final introLines = <String>[];
    final sections = <(String, List<String>)>[];
    final quoteLines = <String>[];
    for (final raw in md.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('## ')) {
        sections.add((line.substring(3).trim(), []));
      } else if (line.startsWith('- ')) {
        if (sections.isEmpty) return null;
        sections.last.$2.add(line.substring(2).trim());
      } else if (line.startsWith('> ')) {
        quoteLines.add(line.substring(2).trim());
      } else if (line.startsWith('#')) {
        return null; // beklenmedik başlık seviyesi
      } else {
        if (sections.isNotEmpty) return null; // bölüm sonrası serbest paragraf
        introLines.add(line);
      }
    }
    if (introLines.isEmpty || sections.isEmpty) return null;
    if (sections.any((s) => s.$2.isEmpty)) return null;
    return _LeapBody(introLines.join('\n\n'), sections,
        quoteLines.isEmpty ? null : quoteLines.join(' '));
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────────

/// Atak index'ine göre uydu ikonları (merkez hep 'ai' kıvılcımı).
const Map<int, List<String>> _satellites = {
  1: ['eye', 'ear', 'hand'],
  2: ['eye', 'ai', 'star'],
  3: ['hand', 'growth', 'star'],
  4: ['clock', 'ai', 'compass'],
  5: ['compass', 'family', 'heart'],
  6: ['search', 'star', 'ai'],
  7: ['hand', 'timeline', 'star'],
  8: ['compass', 'ai', 'star'],
  9: ['shield', 'heart', 'star'],
  10: ['home', 'family', 'star'],
};

class _DetailHero extends StatefulWidget {
  final LeapInfo leap;
  final LeapPhase? phase;
  const _DetailHero({required this.leap, required this.phase});

  @override
  State<_DetailHero> createState() => _DetailHeroState();
}

class _DetailHeroState extends State<_DetailHero> with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leap = widget.leap;
    final phase = widget.phase;
    final surface = Theme.of(context).colorScheme.surface;
    final sat = _satellites[leap.index] ?? const ['star', 'heart', 'ai'];
    final satColors = [AppColors.sleep, AppColors.pump, AppColors.growth];

    Widget satBubble(int i, {required Alignment align, required Offset offset}) =>
        Align(
          alignment: align,
          child: Transform.translate(
            offset: offset,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: surface, boxShadow: AppColors.softShadow),
              child: AdenaIcon(sat[i], size: 18, color: satColors[i]),
            ),
          ),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: RadialGradient(
          center: const Alignment(0, -1),
          radius: 1.4,
          colors: [AppColors.peachLight, AppColors.peach],
        ),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            alignment: WrapAlignment.center,
            children: [
              _Chip.surface(trp('{n}. Atak', {'n': leap.index})),
              _Chip.coral(trp('~{n}. Hafta', {'n': leap.weekStart})),
              if (phase == LeapPhase.peak)
                _Chip.ink(tr('Şu an · Zirve'), dotted: true)
              else if (phase == LeapPhase.fussy)
                _Chip.ink(tr('Yaklaşıyor'), dotted: true)
              else if (phase == LeapPhase.past)
                _Chip.ink(tr('Geçti')),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: RotationTransition(
                    turns: _spin,
                    child: CustomPaint(
                      painter: _RingPainter(
                          color: AppColors.coralDd.withValues(alpha: 0.25)),
                    ),
                  ),
                ),
                Positioned.fill(
                  left: 19,
                  top: 19,
                  right: 19,
                  bottom: 19,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.coralDd.withValues(alpha: 0.16), width: 2),
                    ),
                  ),
                ),
                Positioned.fill(
                  left: 38,
                  top: 38,
                  right: 38,
                  bottom: 38,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: surface,
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.coralDd.withValues(alpha: 0.24),
                            blurRadius: 28,
                            offset: const Offset(0, 12)),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: AdenaIcon('ai', size: 40, color: AppColors.coralDark, sw: 1.9),
                  ),
                ),
                satBubble(0, align: Alignment.topCenter, offset: const Offset(0, -4)),
                satBubble(1, align: Alignment.bottomLeft, offset: const Offset(-9, -8)),
                satBubble(2, align: Alignment.bottomRight, offset: const Offset(9, -8)),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Text(leap.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(leap.summary,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink2)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final List<BoxShadow>? shadow;
  final bool dotted;
  const _Chip._(this.label, this.bg, this.fg, this.shadow, this.dotted);

  factory _Chip.surface(String label) => _Chip._(
      label,
      AppColors.brightness == Brightness.dark ? const Color(0xFF251D2E) : Colors.white,
      AppColors.brightness == Brightness.dark ? const Color(0xFFFFAF9E) : AppColors.coralDd,
      AppColors.smallShadow,
      false);
  factory _Chip.coral(String label) => _Chip._(label, AppColors.coral, Colors.white, [
        BoxShadow(
            color: AppColors.coralDd.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 5))
      ], false);
  factory _Chip.ink(String label, {bool dotted = false}) => _Chip._(
      label,
      AppColors.brightness == Brightness.dark ? const Color(0xFF0D0912) : AppColors.ink,
      Colors.white,
      null,
      dotted);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999), boxShadow: shadow),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotted) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.coral,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.coral.withValues(alpha: 0.35), spreadRadius: 3),
                ],
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(label.toUpperCaseTr(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: fg)),
        ],
      ),
    );
  }
}

/// Dış kesikli halka (yavaş döner).
class _RingPainter extends CustomPainter {
  final Color color;
  _RingPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 1;
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashCount = 26;
    const gap = 2 * 3.14159265 / dashCount;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
          Rect.fromCircle(center: c, radius: r), i * gap, gap * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

// ── İçerik blokları ──────────────────────────────────────────────────────────

class _ParaCard extends StatelessWidget {
  final String text;
  const _ParaCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 17),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow,
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 13.5,
              height: 1.65,
              fontWeight: FontWeight.w700,
              color: AppColors.ink2)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final int index;
  final String title;
  const _SectionHeader({required this.index, required this.title});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = index == 0
        ? (AppColors.sleepBg, AppColors.sleep, 'search')
        : (AppColors.growthBg, AppColors.growth, 'heart');
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 20, 3, 11),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: AdenaIcon(icon, size: 15, color: fg, sw: 2.2),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final int section;
  final int bullet;
  final String text;
  const _MiniCard({required this.section, required this.bullet, required this.text});

  /// Bölüm 0 ("neler olur") c1-c3, bölüm 1 ("nasıl destek") c4-c6 renk/ikonları.
  static List<(Color, Color, String)> _spec(BuildContext context) {
    final d = AppColors.brightness == Brightness.dark;
    return [
      (AppColors.sleepBg, d ? const Color(0xFFB3A6F2) : const Color(0xFF6F5FD6), 'sun'),
      (AppColors.symptomBg, AppColors.symptom, 'heart'),
      (AppColors.pumpBg, d ? AppColors.pump : const Color(0xFF1F9596), 'moon'),
      (AppColors.peachLight, d ? const Color(0xFFFFAF9E) : AppColors.coralDd, 'home'),
      (AppColors.feedBg, d ? const Color(0xFFFFAF9E) : AppColors.coralDd, 'userHeart'),
      (AppColors.growthBg, d ? AppColors.growth : const Color(0xFF349970), 'clock'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec(context);
    final (bg, fg, icon) = spec[(section * 3 + bullet) % spec.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: AppColors.smallShadow,
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: AdenaIcon(icon, size: 20, color: fg),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink2)),
        ),
      ]),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final String text;
  const _QuoteCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(52, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.peachLight, AppColors.peach],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.smallShadow,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -37,
            top: -3,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(9),
                boxShadow: AppColors.smallShadow,
              ),
              child: AdenaIcon('quote', size: 13, color: AppColors.coralDark),
            ),
          ),
          Text(text,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  fontWeight: FontWeight.w800,
                  fontStyle: FontStyle.italic,
                  color: AppColors.ink2)),
        ],
      ),
    );
  }
}
