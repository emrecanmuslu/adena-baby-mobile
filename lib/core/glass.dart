import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme.dart';

/// "Gradyan & Cam" tasarım dokunuşu (design/"Welcome Ekranı - Final").
/// Üç parça: [GlassBackground] (yumuşak gradyan zemin + süzülen marka-rengi
/// lekeler), [GlassCard] (buzlu cam yüzey, statik/az sayıda öğe için) ve
/// [glassSurface] (kaydırma listeleri için blur'suz, ucuz cam görünümü).
/// KAPSAM: yalnız welcome ekranı — Home'a denendi, kullanıcı BEĞENMEDİ ve
/// geri alındı (2026-07-06). Başka ekrana yaymadan önce kullanıcıya sor.

/// Yumuşak gradyan zemin + yavaşça gezinip nefes alan üç renk lekesi.
/// Işık teması kremden mercana ısınır; koyu tema gece paletinde kalır.
class GlassBackground extends StatefulWidget {
  final Widget child;

  /// Sürekli leke animasyonu (10 sn tur). Kapatılırsa lekeler sabit durur.
  final bool animate;

  const GlassBackground({super.key, required this.child, this.animate = true});

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
      vsync: this, duration: const Duration(seconds: 10));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _drift.repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        // Zemin gradyanı: en üst durak scaffold/cream ile aynı → appbar
        // şeffafken araya dikiş girmez.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-0.35, -1),
                end: const Alignment(0.35, 1),
                colors: dark
                    ? const [
                        Color(0xFF191320),
                        Color(0xFF221A2A),
                        Color(0xFF251C30),
                      ]
                    : const [
                        Color(0xFFFFF8F4),
                        Color(0xFFFFF1E9),
                        Color(0xFFFFE9E0),
                      ],
              ),
            ),
          ),
        ),
        // Süzülen renk lekeleri (marka gradyanlarının üç rengi).
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (_, _) {
                final t = _drift.value * 2 * math.pi;
                Offset sway(double phase, double rx, double ry) =>
                    Offset(math.sin(t + phase) * rx, math.cos(t + phase) * ry);
                final o1 = sway(0, 18, 12);
                final o2 = sway(2.1, 14, 20);
                final o3 = sway(4.2, 20, 14);
                return Stack(
                  children: [
                    GlassBlob(
                        left: -80 + o1.dx,
                        top: -70 + o1.dy,
                        size: 280,
                        color: AppColors.coral
                            .withValues(alpha: dark ? 0.20 : 0.42)),
                    GlassBlob(
                        right: -100 + o2.dx,
                        top: 230 + o2.dy,
                        size: 300,
                        color: const Color(0xFFE3B255)
                            .withValues(alpha: dark ? 0.16 : 0.34)),
                    GlassBlob(
                        left: -60 + o3.dx,
                        bottom: -80 + o3.dy,
                        size: 280,
                        color: const Color(0xFFD9799A)
                            .withValues(alpha: dark ? 0.18 : 0.32)),
                  ],
                );
              },
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Zemindeki tek yumuşak renk lekesi: radyal gradyanla blur görünümü
/// (ImageFilter'dan çok daha ucuz, her karede animasyonu kaldırır).
class GlassBlob extends StatelessWidget {
  final double? left, top, right, bottom;
  final double size;
  final Color color;
  const GlassBlob({
    super.key,
    this.left,
    this.top,
    this.right,
    this.bottom,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0.15, 1],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kaydırma listelerindeki kartlar için cam yüzey DEKORU (BackdropFilter YOK —
/// scroll performansı için yarı şeffaf beyaz + beyaz kenar yeterli cam hissi
/// verir). Mevcut `colorScheme.surface + softShadow` dekorlarının yerine geçer.
BoxDecoration glassSurface(BuildContext context, {double radius = 18}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.55),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: dark
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.white.withValues(alpha: 0.70),
      width: 1.5,
    ),
    boxShadow: AppColors.softShadow,
  );
}

/// Buzlu cam kart: GERÇEK BackdropFilter blur'u. Ekranda az sayıda (statik)
/// öğe varken kullan — uzun listelerde [glassSurface] tercih et.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double sigma;

  /// Açık temada yüzey opaklığı (ikincil öğeler için düşürülür, ör. 0.35).
  final double lightAlpha;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.sigma = 16,
    this.lightAlpha = 0.52,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // İkincil (daha şeffaf) kartta kenar da yumuşar — mockup'taki .sec gibi.
    final borderAlpha = dark ? 0.16 : (lightAlpha < 0.5 ? 0.65 : 0.8);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Material(
          color: dark
              ? Colors.white.withValues(alpha: lightAlpha < 0.5 ? 0.05 : 0.07)
              : Colors.white.withValues(alpha: lightAlpha),
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: borderAlpha),
                  width: 1.5,
                ),
              ),
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
