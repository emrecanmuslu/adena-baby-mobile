import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/subscription_repository.dart';

/// Açılış ekranı — design ScrSplash ile birebir:
/// şeftali radyal ışıma + gradient amblem + kelime-logo + altta 3 nokta.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    return Scaffold(
      backgroundColor: AppColors.cream, // --bg = #FFF8F4
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandEmblem(),
                const SizedBox(height: 22),
                const BrandWordmark(fontSize: 38),
                // Premium → logonun altında küçük altın rozet (cache → flaş yok).
                if (isPremium) ...[
                  const SizedBox(height: 12),
                  const AdProBadge(),
                ],
                const SizedBox(height: 14),
                Text(
                  tr('Bir bebekle başladı, her bebek için.'),
                  style: TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ],
            ),
            // altta 3 nokta (ilk aktif)
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 34),
                child: _Dots(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Altta yükleniyor göstergesi — 3 nokta sırayla parlayıp büyür (faz kaydırmalı
/// dalga), sürekli döngü.
class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (k) {
            // Her nokta için faz kaydırmalı üçgen dalga (0→1→0).
            final phase = (_c.value - k * 0.18) % 1.0;
            final wave = Curves.easeInOut
                .transform(phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: 0.8 + 0.4 * wave,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.peach.withValues(alpha: 0.35 + 0.65 * wave),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
