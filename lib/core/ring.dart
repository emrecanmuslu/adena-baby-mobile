import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// İlerleme halkası (design Ring): track + yay + ortada çocuk widget.
class Ring extends StatelessWidget {
  final double size;
  final double pct; // 0..1
  final double strokeWidth;
  final Color color;
  final Color? track;
  final Widget? child;

  const Ring({
    super.key,
    this.size = 44,
    required this.pct,
    this.strokeWidth = 5,
    this.color = AppColors.coralDark,
    this.track,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          pct.clamp(0.0, 1.0),
          strokeWidth,
          color,
          track ?? color.withValues(alpha: 0.18),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final double sw;
  final Color color;
  final Color track;
  _RingPainter(this.pct, this.sw, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - sw) / 2;
    final trackP = Paint()
      ..color = track
      ..strokeWidth = sw
      ..style = PaintingStyle.stroke;
    final arcP = Paint()
      ..color = color
      ..strokeWidth = sw
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, trackP);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * pct,
      false,
      arcP,
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.pct != pct || o.color != color || o.sw != sw || o.track != track;
}
