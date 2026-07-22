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
          // Sağlık (aşı/gelişim/diş) local-first: katalog anonim erişilebilir,
          // veri telefonda tutulur → misafir dahil hesapsız çalışır.
          if (!expecting) ...[
            adSec(tr('Bebeğin sağlığı')),
            AdMenuItem(
              icon: 'syringe',
              color: AppColors.med,
              bg: AppColors.medBg,
              title: tr('Aşı Takvimi'),
              meta: tr('Doğum tarihinden otomatik · yapıldıkça işaretle'),
              onTap: () => context.push('/vaccines'),
            ),
            AdMenuItem(
              icon: 'growth',
              color: AppColors.growth,
              bg: AppColors.growthBg,
              title: tr('Gelişim / Kilometre Taşları'),
              meta: tr('Yaşa göre beklenen gelişim basamakları'),
              onTap: () => context.push('/milestones'),
            ),
            AdMenuItem(
              icon: 'tooth',
              color: AppColors.pump,
              bg: AppColors.pumpBg,
              title: tr('Diş Gelişimi'),
              meta: tr('Süt dişleri haritası — çıkanları işaretle'),
              onTap: () => context.push('/teeth'),
            ),
            AdMenuItem(
              icon: 'star',
              color: AppColors.coralDd,
              bg: AppColors.feedBg,
              title: tr('Gelişim Atakları'),
              meta: tr('Huzursuz dönemler ve yeni beceriler'),
              onTap: () => context.push('/leaps'),
            ),
            AdMenuItem(
              icon: 'bell',
              color: AppColors.coralDd,
              bg: AppColors.feedBg,
              title: tr('Hatırlatıcılar'),
              meta: tr('Vitamin · beslenme · aşı · dürtükleme'),
              onTap: () => context.push('/reminders'),
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
