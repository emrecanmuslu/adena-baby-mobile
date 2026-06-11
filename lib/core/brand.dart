import 'package:flutter/material.dart';

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

/// "aden❤a baby" kelime-logosu (design .ad-logo / Logo ile birebir).
/// aden=ink · dolu koyu-mercan kalp · a=koyu-mercan · baby=muted(600), ağırlık 900.
class BrandWordmark extends StatelessWidget {
  final double fontSize;
  const BrandWordmark({super.key, this.fontSize = 34});

  @override
  Widget build(BuildContext context) {
    final inkColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF2E8E3)
        : AppColors.ink;
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          fontFamily: 'Nunito',
          letterSpacing: -fontSize * 0.02,
          height: 1.0,
        ),
        children: [
          TextSpan(text: 'aden', style: TextStyle(color: inkColor)),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: fontSize * 0.02),
              child: Icon(Icons.favorite,
                  color: AppColors.coralDark, size: fontSize * 0.42),
            ),
          ),
          const TextSpan(text: 'a', style: TextStyle(color: AppColors.coralDark)),
          TextSpan(
            text: ' baby',
            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
