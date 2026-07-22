import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';

/// Adet Takvimi imza halkası ("Dial") — tasarım "Bloom" cycle-kit Dial'ının
/// Flutter karşılığı. Üç mod: aktif döngü / lohusalık iyileşme / ilk adet bekleme.
/// Rakam/etiket için **Nunito** (serif değil) — uygulama diliyle uyumlu.
enum DialMode { cycle, heal, waiting }

class CycleDial extends StatelessWidget {
  final DialMode mode;
  final int day;
  final int cycleLen;
  final int periodLen;
  final int ovu;
  final List<int> fertile; // [start, end] döngü-günü
  final String? num;
  final double numSize;
  final String? label;
  final String? sub;
  final Color accent;
  final double size;
  final double stroke;
  final Widget? centerIcon; // num yerine ikon (sprout/bloom)

  const CycleDial({
    super.key,
    this.mode = DialMode.cycle,
    this.day = 1,
    this.cycleLen = 28,
    this.periodLen = 5,
    this.ovu = 14,
    this.fertile = const [10, 16],
    this.num,
    this.numSize = 54,
    this.label,
    this.sub,
    Color? accent,
    this.size = 208,
    this.stroke = 13,
    this.centerIcon,
  }) : accent = accent ?? const Color(0xFFC2576E);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DialPainter(
              mode: mode,
              day: day,
              cycleLen: cycleLen,
              periodLen: periodLen,
              ovu: ovu,
              fertile: fertile,
              stroke: stroke,
              accent: accent,
              roseD: AppColors.roseD,
              sage: AppColors.sage,
              gold: AppColors.gold,
              clay: AppColors.lochia,
              clayD: AppColors.lochia,
              track: AppColors.line2,
              surface: Theme.of(context).colorScheme.surface,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ?centerIcon,
                if (num != null)
                  Text(num!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: numSize,
                          height: 1.0,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink)),
                if (label != null) ...[
                  const SizedBox(height: 3),
                  Text(label!.toUpperCaseTr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: AppColors.ink2)),
                ],
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final DialMode mode;
  final int day, cycleLen, periodLen, ovu;
  final List<int> fertile;
  final double stroke;
  final Color accent, roseD, sage, gold, clay, clayD, track, surface;

  _DialPainter({
    required this.mode,
    required this.day,
    required this.cycleLen,
    required this.periodLen,
    required this.ovu,
    required this.fertile,
    required this.stroke,
    required this.accent,
    required this.roseD,
    required this.sage,
    required this.gold,
    required this.clay,
    required this.clayD,
    required this.track,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final r = (size.width - stroke) / 2 - 2;
    final rect = Rect.fromCircle(center: Offset(c, c), radius: r);

    // gün → açı (tepeden saat yönü, derece)
    double ang(num d) =>
        (math.max(0, math.min(cycleLen, d - 1)) / cycleLen) * 360.0;
    // derece(tepeden) → kanvas radyan
    double rad(double deg) => -math.pi / 2 + deg * math.pi / 180;
    Offset pt(double deg) =>
        Offset(c + r * math.cos(rad(deg)), c + r * math.sin(rad(deg)));

    Paint band(Color color, {double opacity = 1, bool round = true}) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
      ..color = color.withValues(alpha: opacity);

    void drawArc(double a0, double a1, Paint p) {
      canvas.drawArc(rect, rad(a0), (a1 - a0) * math.pi / 180, false, p);
    }

    // track
    drawArc(0, 359.99, band(track, opacity: 0.55, round: false));

    switch (mode) {
      case DialMode.cycle:
        // doğurgan pencere (sage, arkada)
        drawArc(ang(fertile[0]), ang(fertile[1]), band(sage, opacity: 0.42));
        // geçen döngü (rose accent)
        if (day > 1) drawArc(0, ang(day), band(accent));
        // adet günleri (koyu rose)
        drawArc(0, ang(periodLen + 1), band(roseD));
        // yumurtlama tiki
        final ov = pt(ang(ovu));
        canvas.drawCircle(ov, 4.5, Paint()..color = gold);
        canvas.drawCircle(
            ov,
            4.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = surface);
      case DialMode.heal:
        if (day > 1) {
          drawArc(0, math.min(360, (day / 42) * 360), band(clay));
        }
      case DialMode.waiting:
        // kesik halka (dashed) — küçük tireler
        final dash = band(accent, opacity: 0.7);
        for (var a = 0.0; a < 360; a += 14) {
          drawArc(a, a + 3, dash);
        }
    }

    // bugün boncuğu
    if (mode != DialMode.waiting) {
      final b = pt(ang(day));
      canvas.drawCircle(b, 8, Paint()..color = surface);
      canvas.drawCircle(
          b,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = mode == DialMode.heal ? clayD : roseD);
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.mode != mode ||
      old.day != day ||
      old.cycleLen != cycleLen ||
      old.accent != accent;
}
