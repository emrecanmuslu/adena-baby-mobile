import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/leaps.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/leap_repository.dart';
import '../../data/leap_weeks.dart';
import '../babies/baby_controller.dart';

/// Gelişim Atakları — bebeğin (düzeltilmiş) doğum tarihine göre tekrarlanan
/// 10 zihinsel/motor sıçrama döneminin "yolculuk patikası" listesi
/// (design/Gelişim Atakları.html). Şu an alakalı olan (huzursuz öncesi/zirve)
/// vurgulanır. Tıbbi tanı değildir, genel bir rehberdir.
class LeapsScreen extends ConsumerWidget {
  const LeapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    final async = ref.watch(leapsProvider);
    final weeks = correctedAgeWeeks(baby);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Gelişim Atakları')),
                Text(tr('Bebeğinin zihinsel sıçrama yolculuğu'),
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ],
            ),
            const SizedBox(width: 8),
            AdInfoDot(
              title: tr('Gelişim atakları nedir?'),
              body: tr('Bebekler ilk aylarda/yıllarda tekrarlayan, huzursuz/'
                  'ağlamaklı bir öncesi dönemle gelen zihinsel-motor sıçramalar '
                  'yaşayabilir. Haftalar yaklaşık referans noktalarıdır — her '
                  'bebek kendi temposunda gelişir, bu tıbbi bir tanı değildir.'),
              size: 16,
            ),
          ],
        ),
      ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Skeleton(height: 170, radius: 24),
            const SizedBox(height: 14),
            for (var i = 0; i < 5; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Skeleton(height: 62, radius: 16),
              ),
          ],
        ),
        error: (_, _) =>
            _JourneyBody(leaps: kEmbeddedLeaps, weeks: weeks, babyName: baby?.name),
        data: (leaps) =>
            _JourneyBody(leaps: leaps, weeks: weeks, babyName: baby?.name),
      ),
    );
  }
}

class _JourneyBody extends StatelessWidget {
  final List<LeapInfo> leaps;
  final int? weeks;
  final String? babyName;
  const _JourneyBody({required this.leaps, required this.weeks, this.babyName});

  @override
  Widget build(BuildContext context) {
    final phases = [
      for (final l in leaps)
        weeks == null ? null : leapPhase(weeks!, l.weekStart, l.fussyWeeksBefore),
    ];
    final activeIx = phases.indexWhere((p) => p == LeapPhase.fussy || p == LeapPhase.peak);
    final pastCount = phases.where((p) => p == LeapPhase.past).length;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 22 + MediaQuery.of(context).padding.bottom),
      children: [
        LeapHeroCard(
          leaps: leaps,
          phases: phases,
          activeIx: activeIx,
          pastCount: pastCount,
          weeks: weeks,
          babyName: babyName,
        ),
        const _Legend(),
        _Journey(leaps: leaps, phases: phases, activeIx: activeIx, weeks: weeks),
        const SizedBox(height: 16),
        AdMedicalNote(
          text: tr('Bu içerik genel bilgilendirme amaçlıdır; gelişim atakları '
              'tıbbi bir tanı değildir. Her bebek kendi temposunda gelişir. '
              'Endişelerin varsa doktoruna danış.'),
        ),
      ],
    );
  }
}

// ── Hero: bebeğin şu anki durumunu özetleyen üst kart ────────────────────────

/// Atak durum hero'su — liste ekranının tepesinde ve ana sayfa "Gelişim Atağı"
/// bölümünde kullanılır. [onTap] verilirse tıklanabilir olur.
class LeapHeroCard extends StatelessWidget {
  final List<LeapInfo> leaps;
  final List<LeapPhase?> phases;
  final int activeIx;
  final int pastCount;
  final int? weeks;
  final String? babyName;
  final VoidCallback? onTap;
  const LeapHeroCard({
    super.key,
    required this.leaps,
    required this.phases,
    required this.activeIx,
    required this.pastCount,
    required this.weeks,
    this.babyName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = activeIx >= 0 ? leaps[activeIx] : null;
    final phase = activeIx >= 0 ? phases[activeIx] : null;

    String kick;
    String headline;
    String body;
    String? wkChip;
    String? wkNote;
    if (weeks == null) {
      kick = tr('10 zihinsel sıçrama');
      headline = tr('Bebeğinin gelişim yolculuğu');
      body = tr('Bebeğin doğduktan sonra burada hangi atakta olduğunu görebilirsin.');
    } else if (phase == LeapPhase.fussy) {
      kick = trp('{n}. atak yaklaşıyor', {'n': active!.index});
      headline = tr('Huysuzluk artabilir — bu çok normal');
      body = trp(
          '{name} {w} haftalık. Bebeğinin beyni büyük bir adıma hazırlanıyor; '
          'bu dönemde daha huzursuz olabilir.',
          {'name': babyName ?? tr('Bebeğin'), 'w': weeks!});
      wkChip = trp('Tahmini başlangıç: ~{n}. hafta', {'n': active.weekStart});
      final left = active.weekStart - weeks!;
      wkNote = trp('≈ {n} hafta kaldı', {'n': left < 1 ? 1 : left});
    } else if (phase == LeapPhase.peak) {
      kick = trp('{n}. atak · Şu an', {'n': active!.index});
      headline = active.title;
      body = active.summary;
      wkChip = trp('~{n}. hafta', {'n': active.weekStart});
      wkNote = tr('Zirve dönemi');
    } else {
      final nextIx = phases.indexWhere((p) => p == LeapPhase.future);
      kick = tr('Sakin dönem');
      headline = tr('Şu an atak penceresi görünmüyor');
      if (nextIx >= 0) {
        final next = leaps[nextIx];
        body = trp('{name} şu an ataklar arası sakin bir dönemde.',
            {'name': babyName ?? tr('Bebeğin')});
        wkChip = trp('Tahmini başlangıç: ~{n}. hafta', {'n': next.weekStart});
        final left = next.weekStart - weeks!;
        wkNote = trp('≈ {n} hafta kaldı', {'n': left < 1 ? 1 : left});
      } else {
        body = tr('İlk 20 ayın büyük atakları geride kaldı.');
      }
    }

    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: RadialGradient(
          center: const Alignment(-0.75, -1),
          radius: 1.6,
          colors: [AppColors.peachLight, AppColors.peach],
        ),
        boxShadow: AppColors.softShadow,
      ),
      child: Stack(
        children: [
          // dekoratif yörünge halkaları (sağ üst)
          Positioned(
            top: -34,
            right: -30,
            child: CustomPaint(
              size: const Size(140, 140),
              painter: _DashedCirclePainter(
                  color: AppColors.coralDd.withValues(alpha: 0.28), strokeWidth: 2),
            ),
          ),
          Positioned(
            top: -14,
            right: -10,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.coralDd.withValues(alpha: 0.14), width: 2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: AppColors.smallShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdenaIcon('ai', size: 11, color: _kickColor(context)),
                      const SizedBox(width: 6),
                      Text(kick.toUpperCaseTr(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                              color: _kickColor(context))),
                    ],
                  ),
                ),
                const SizedBox(height: 11),
                Text(headline,
                    style: TextStyle(
                        fontSize: 21,
                        height: 1.18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink2)),
                if (wkChip != null) ...[
                  const SizedBox(height: 13),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.coral,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.coralDd.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6)),
                        ],
                      ),
                      child: Text(wkChip,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(wkNote ?? '',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink2)),
                    ),
                  ]),
                ],
                if (weeks != null) ...[
                  const SizedBox(height: 15),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: pastCount / leaps.length,
                          minHeight: 8,
                          backgroundColor: AppColors.brightness == Brightness.dark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.65),
                          valueColor: const AlwaysStoppedAnimation(AppColors.coral),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(trp('{n} / 10 atak', {'n': pastCount}),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: _kickColor(context))),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }

  static Color _kickColor(BuildContext context) =>
      AppColors.brightness == Brightness.dark ? const Color(0xFFFFAF9E) : AppColors.coralDd;
}

// ── Faz lejantı ──────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget chip(Widget dot, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            dot,
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.muted)),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          chip(
              Container(
                  width: 9,
                  height: 9,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: AppColors.muted2)),
              tr('Geçti')),
          chip(
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.coral, width: 2.5))),
              tr('Yaklaşıyor')),
          chip(
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.coral,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.coral.withValues(alpha: 0.3), spreadRadius: 3),
                    ],
                  )),
              tr('Zirve')),
          chip(
              CustomPaint(
                  size: const Size(9, 9),
                  painter: _DashedCirclePainter(
                      color: AppColors.muted2, strokeWidth: 1.5, dashCount: 8)),
              tr('Gelecek')),
        ],
      ),
    );
  }
}

// ── Yolculuk patikası ────────────────────────────────────────────────────────

const double _rowH = 92;
const double _topPad = 30; // ilk nodun merkez y'si
const double _nodeXInset = 62; // sol/sağ nod merkezlerinin kenara uzaklığı

class _Journey extends StatefulWidget {
  final List<LeapInfo> leaps;
  final List<LeapPhase?> phases;
  final int activeIx;
  final int? weeks;
  const _Journey(
      {required this.leaps, required this.phases, required this.activeIx, required this.weeks});

  @override
  State<_Journey> createState() => _JourneyState();
}

class _JourneyState extends State<_Journey> with SingleTickerProviderStateMixin {
  late final AnimationController _throb =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
        ..repeat();

  @override
  void dispose() {
    _throb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.leaps.length;
    final height = _topPad + _rowH * (n - 1) + 46;
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final centers = [
        for (var i = 0; i < n; i++)
          Offset(i.isEven ? _nodeXInset : w - _nodeXInset, _topPad + i * _rowH),
      ];

      // "Buradasın" konumu: geçilen son nod + aktif/sonraki noda doğru kısmi ilerleme.
      Offset? pin;
      double doneT = -1; // path parametresi (nod indeksi + segment kesri)
      if (widget.weeks != null) {
        final lastPast = widget.phases.lastIndexWhere((p) => p == LeapPhase.past);
        if (lastPast >= n - 1) {
          doneT = (n - 1).toDouble();
        } else {
          if (lastPast < 0 && widget.activeIx < 0) {
            // İlk ataktan önce: patika henüz başlamadı, pin gösterme (hero anlatır).
            doneT = -1;
          } else {
            double frac;
            if (widget.activeIx >= 0) {
              frac = 0.55;
            } else {
              final a = widget.leaps[lastPast].weekStart;
              final b = widget.leaps[lastPast + 1].weekStart;
              // Nodların üstüne binmesin diye kesri orta banda sıkıştır.
              frac = ((widget.weeks! - a) / math.max(1, b - a)).clamp(0.3, 0.8);
            }
            doneT = (lastPast < 0 ? 0 : lastPast) + frac;
          }
        }
      }

      final painter = _TrailPainter(
        centers: centers,
        doneT: doneT,
        dotColor: AppColors.line2,
        doneColor: AppColors.coral.withValues(alpha: 0.75),
      );
      if (doneT >= 0) pin = painter.pointAt(doneT);

      return SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: CustomPaint(painter: painter)),
            for (var i = 0; i < n; i++)
              _StopEntry(
                leap: widget.leaps[i],
                phase: widget.phases[i],
                center: centers[i],
                left: i.isEven,
                width: w,
                throb: _throb,
              ),
            if (pin != null)
              Positioned(
                left: pin.dx - 15,
                top: pin.dy - 15,
                child: IgnorePointer(
                  child: Row(
                    textDirection: pin.dx < w / 2 ? TextDirection.ltr : TextDirection.rtl,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.coral, AppColors.coralDd]),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.coralDd.withValues(alpha: 0.4),
                                blurRadius: 14,
                                offset: const Offset(0, 6)),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const AdenaIcon('user', size: 13, color: Colors.white),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.brightness == Brightness.dark
                              ? const Color(0xFF0D0912)
                              : AppColors.ink,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: AppColors.softShadow,
                        ),
                        child: Text(tr('Buradasın').toUpperCaseTr(),
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Patikadaki tek durak: nod + başlık/hafta metni. Sol duraklarda metin sağda,
/// sağ duraklarda solda (sağa hizalı).
class _StopEntry extends StatelessWidget {
  final LeapInfo leap;
  final LeapPhase? phase;
  final Offset center;
  final bool left;
  final double width;
  final Animation<double> throb;
  const _StopEntry({
    required this.leap,
    required this.phase,
    required this.center,
    required this.left,
    required this.width,
    required this.throb,
  });

  @override
  Widget build(BuildContext context) {
    final active = phase == LeapPhase.fussy || phase == LeapPhase.peak;
    final d = active ? 60.0 : 46.0;
    final metaW = width - _nodeXInset * 2 + 8;

    final meta = Column(
      crossAxisAlignment: left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(leap.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: left ? TextAlign.left : TextAlign.right,
            style: TextStyle(
                fontSize: active ? 14.5 : 13,
                height: 1.15,
                fontWeight: phase == LeapPhase.future ? FontWeight.w800 : FontWeight.w900,
                color: switch (phase) {
                  LeapPhase.past => AppColors.ink2,
                  LeapPhase.future || null => AppColors.muted,
                  _ => AppColors.ink,
                })),
        const SizedBox(height: 2),
        Text(
            phase == LeapPhase.past
                ? '${trp('~{n}. hafta', {'n': leap.weekStart})} · ${tr('Geçti')}'
                : trp('~{n}. hafta', {'n': leap.weekStart}),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: phase == LeapPhase.future || phase == null
                    ? AppColors.muted2
                    : AppColors.muted)),
        if (active) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: phase == LeapPhase.peak ? AppColors.coral : AppColors.feedBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
                (phase == LeapPhase.peak ? tr('Şu an') : tr('Yaklaşıyor')).toUpperCaseTr(),
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: phase == LeapPhase.peak
                        ? Colors.white
                        : (AppColors.brightness == Brightness.dark
                            ? const Color(0xFFFFAF9E)
                            : AppColors.coralDd))),
          ),
        ],
      ],
    );

    return Positioned(
      top: center.dy - d / 2 - (active ? 4 : 0),
      left: left ? center.dx - d / 2 : null,
      right: left ? null : width - center.dx - d / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/leaps/${leap.index}'),
        child: Row(
          textDirection: left ? TextDirection.ltr : TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _StopNode(index: leap.index, phase: phase, size: d, throb: throb),
            const SizedBox(width: 11),
            ConstrainedBox(
                constraints: BoxConstraints(maxWidth: metaW - d - 11), child: meta),
          ],
        ),
      ),
    );
  }
}

class _StopNode extends StatelessWidget {
  final int index;
  final LeapPhase? phase;
  final double size;
  final Animation<double> throb;
  const _StopNode(
      {required this.index, required this.phase, required this.size, required this.throb});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    switch (phase) {
      case LeapPhase.past:
        return Stack(clipBehavior: Clip.none, children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.peach,
                boxShadow: AppColors.smallShadow),
            child: Text('$index',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.brightness == Brightness.dark
                        ? const Color(0xFFFFAF9E)
                        : AppColors.coralDd)),
          ),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.growth,
                border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor, width: 2.5),
              ),
              child: const AdenaIcon('check', size: 8, color: Colors.white, sw: 4),
            ),
          ),
        ]);
      case LeapPhase.fussy:
      case LeapPhase.peak:
        final peak = phase == LeapPhase.peak;
        return AnimatedBuilder(
          animation: throb,
          builder: (context, child) {
            final t = throb.value;
            return Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: peak ? AppColors.coral : surface,
                border: peak ? null : Border.all(color: AppColors.coral, width: 3),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.coralDd.withValues(alpha: 0.28),
                      blurRadius: 22,
                      offset: const Offset(0, 8)),
                  BoxShadow(
                      color: AppColors.coral
                          .withValues(alpha: 0.45 * (1 - t).clamp(0.0, 1.0)),
                      spreadRadius: 12 * t),
                ],
              ),
              child: child,
            );
          },
          child: Text('$index',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: peak
                      ? Colors.white
                      : (AppColors.brightness == Brightness.dark
                          ? const Color(0xFFFFAF9E)
                          : AppColors.coralDd))),
        );
      case LeapPhase.future:
      case LeapPhase.upcoming:
      case null:
        return CustomPaint(
          foregroundPainter: _DashedCirclePainter(
              color: AppColors.muted2, strokeWidth: 2, dashCount: 14),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
            child: Text('$index',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.muted2)),
          ),
        );
    }
  }
}

// ── Painterlar ───────────────────────────────────────────────────────────────

/// Nod merkezlerini S-kıvrımlarıyla bağlayan patika: noktalı iz + geçilen
/// kısım için düz mercan iz. [pointAt] "Buradasın" konumunu verir.
class _TrailPainter extends CustomPainter {
  final List<Offset> centers;
  final double doneT; // nod indeksi + kesir; <0 → iz yok
  final Color dotColor;
  final Color doneColor;
  _TrailPainter(
      {required this.centers,
      required this.doneT,
      required this.dotColor,
      required this.doneColor});

  Path _segment(int i) {
    final a = centers[i], b = centers[i + 1];
    return Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx, a.dy + 50, b.dx, b.dy - 50, b.dx, b.dy);
  }

  Offset pointAt(double t) {
    final i = t.floor().clamp(0, centers.length - 2);
    final frac = (t - i).clamp(0.0, 1.0);
    final m = _segment(i).computeMetrics().first;
    return m.getTangentForOffset(m.length * frac)!.position;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = dotColor;
    final done = Paint()
      ..color = doneColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < centers.length - 1; i++) {
      final m = _segment(i).computeMetrics().first;
      // noktalı iz (dasharray 1 9 ≈ 10px aralıklı minik noktalar)
      for (double o = 5; o < m.length; o += 10) {
        final p = m.getTangentForOffset(o)!.position;
        canvas.drawCircle(p, 1.75, dot);
      }
      // geçilen kısım
      if (doneT > i) {
        final frac = (doneT - i).clamp(0.0, 1.0);
        canvas.drawPath(m.extractPath(0, m.length * frac), done);
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) =>
      old.centers != centers || old.doneT != doneT || old.dotColor != dotColor;
}

/// Kesikli çember (gelecek nodları, hero/detay yörünge süsleri).
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;
  _DashedCirclePainter(
      {required this.color, required this.strokeWidth, this.dashCount = 20});

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final gap = 2 * math.pi / dashCount;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * gap, gap * 0.55, false,
          paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.dashCount != dashCount;
}
