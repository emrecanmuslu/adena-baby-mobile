import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/premium_gate.dart';
import '../../core/theme.dart';
import '../babies/baby_controller.dart';

/// Keşfet hub'ı — takip dışı yüzeyleri tek mantıklı yerde toplar:
/// Bebeğin Sağlığı · Topluluk · Uzman Rehberi · Anılar. Alt menüdeki ✨ slotu
/// (takip modu) ve bekleme modunda ayarlardan açılır.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    final expecting = baby?.isExpecting ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Keşfet')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          // Bebeğin Sağlığı — bekleme modunda aşı/ateş/ilaç anlamsız → gizli.
          if (!expecting) ...[
            adSec(tr('Bebeğin sağlığı')),
            AdMenuItem(
              icon: 'heart',
              color: AppColors.fever,
              bg: AppColors.feverBg,
              title: tr('Bebeğin Sağlığı'),
              meta: tr('Aşı · randevu · ateş & ilaç · diş · gelişim'),
              // Sağlık (aşı/gelişim/diş) takvimi cloud'dan üretilir → hesap gerekir.
              onTap: () => requireAccount(context, ref,
                  feature: tr('Bebeğin Sağlığı'),
                  desc: tr('Aşı takvimi, gelişim ve diş takibi buluttan gelir; '
                      'ücretsiz bir hesap oluşturman yeterli.'),
                  onAllowed: () => context.push('/health')),
            ),
          ],

          // Annenin Sağlığı — doğum sonrası anneye özel (bekleme modunda gizli).
          if (!expecting) ...[
            adSec(tr('Annenin sağlığı')),
            AdMenuItem(
              icon: 'heart',
              color: AppColors.roseD,
              bg: AppColors.roseBg,
              title: tr('Adet Takvimi'),
              meta: tr('Doğum sonrası döngü & loşia takibi · kişisel'),
              onTap: () => context.push('/cycle'),
            ),
          ],

          adSec(tr('Topluluk & Rehber')),
          AdMenuItem(
            icon: 'family',
            color: AppColors.sleep,
            bg: AppColors.sleepBg,
            title: tr('Topluluk'),
            meta: tr('Ebeveynlere soru sor, deneyim paylaş'),
            // Topluluk cloud + hesap gerektirir (free'ye açık).
            onTap: () => requireAccount(context, ref,
                feature: tr('Topluluk'),
                desc: tr('Sorular sormak ve deneyim paylaşmak için ücretsiz bir '
                    'hesap oluştur.'),
                onAllowed: () => context.push('/community')),
          ),
          AdMenuItem(
            icon: 'star',
            color: AppColors.premiumInk,
            bg: AppColors.premiumBg,
            title: tr('Uzman Rehberi'),
            meta: tr('Yaşa uygun bakım & gelişim yazıları'),
            onTap: () => context.push('/content'),
          ),

          adSec(tr('Anılar')),
          AdMenuItem(
            icon: 'camera',
            color: AppColors.coralDd,
            bg: AppColors.feedBg,
            title: tr('Anılar / Fotoğraf Günlüğü'),
            meta: tr('İlk\'ler · fotoğraflar · özel anlar'),
            onTap: () => context.push('/memories'),
          ),
        ],
      ),
    );
  }
}
