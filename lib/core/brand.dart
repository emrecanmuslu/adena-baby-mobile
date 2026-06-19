import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Tasarımdaki amblem: gradient yuvarlak-kare + beyaz kalp (design ScrSplash ile birebir).
class BrandEmblem extends StatelessWidget {
  final double size;
  const BrandEmblem({super.key, this.size = 92});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9E8A), Color(0xFFE2553F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.33),
      ),
      child: Icon(Icons.favorite, color: Colors.white, size: size * 0.5),
    );
  }
}

/// "aden❤a baby" kelime-logosu — Nunito w900 gliflerinden birebir çıkarılmış
/// **vektör** (assets/brand/wordmark.svg). "aden" `currentColor` ile çizilir;
/// karanlık temada açık ink rengine döner (kalp/a=mercan, baby=muted sabit).
/// [fontSize] eski API ile uyumlu: harf em-boyu fontSize'a denk gelir.
class BrandWordmark extends StatelessWidget {
  final double fontSize;
  const BrandWordmark({super.key, this.fontSize = 34});

  // SVG viewBox yüksekliği / 1000 (em) — em-boyu fontSize'a eşitlemek için.
  static const double _vhPerEm = 0.9516;

  @override
  Widget build(BuildContext context) {
    final inkColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF2E8E3)
        : AppColors.ink;
    return SvgPicture.asset(
      'assets/brand/wordmark.svg',
      height: fontSize * _vhPerEm,
      theme: SvgTheme(currentColor: inkColor),
    );
  }
}
