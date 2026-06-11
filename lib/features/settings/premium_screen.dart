import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/subscription_repository.dart';

/// Premium / paywall (design ScrPremium): özellik listesi + planlar + dene CTA.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  String _plan = 'yearly'; // monthly|yearly
  bool _saving = false;

  static final _feats = [
    (tr('AI veri dışa aktarımı'), tr('Doktora hazır özetler')),
    (tr('Sınırsız bakıcı'), tr('Tüm aile + bakıcılar')),
    (tr('Gelişmiş grafikler'), tr('Uyku/beslenme trendleri, korelasyon')),
    (tr('AI uyku önerileri'), tr('Yakında · Faz 1.5')),
  ];

  @override
  Widget build(BuildContext context) {
    final isPremium =
        ref.watch(subscriptionProvider).asData?.value.isPremium ?? false;

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // Başlık — altın yıldız
          Column(
            children: [
              Container(
                width: 56,
                height: 56,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.premiumGoldLight, AppColors.premiumGold],
                  ),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x59FFB43C), blurRadius: 24, offset: Offset(0, 10)),
                  ],
                ),
                alignment: Alignment.center,
                child: const AdenaIcon('star', size: 28, color: Colors.white, sw: 2.2),
              ),
              Text(tr('Adena Premium'),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(tr('Ücretsiz katman zaten cömert — Premium ekstra güç katar.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 16),

          // Özellik listesi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.softShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < _feats.length; i++)
                  _FeatureRow(
                    title: _feats[i].$1,
                    desc: _feats[i].$2,
                    last: i == _feats.length - 1,
                  ),
              ],
            ),
          ),

          if (isPremium) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.premiumBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const AdenaIcon('check', size: 20, color: AppColors.premiumInk, sw: 2.4),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr('Premium aktif — teşekkürler 💛'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppColors.premiumInk)),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _PlanCard(
                    selected: _plan == 'monthly',
                    period: tr('Aylık'),
                    price: '₺79',
                    onTap: () => setState(() => _plan = 'monthly'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlanCard(
                    selected: _plan == 'yearly',
                    period: tr('Yıllık'),
                    price: '₺59',
                    tag: tr('2 ay bedava'),
                    onTap: () => setState(() => _plan = 'yearly'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdSaveButton(
              label: _saving ? tr('İşleniyor…') : tr("Premium'u dene · 7 gün ücretsiz"),
              color: AppColors.coral,
              onTap: _saving ? () {} : _subscribe,
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(tr('İstediğin zaman iptal et · baskı yok 💛'),
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _subscribe() async {
    setState(() => _saving = true);
    try {
      await ref.read(subscriptionRepositoryProvider).verify(platform: 'android');
      ref.invalidate(subscriptionProvider);
      if (mounted) {
        showAdToast(context, tr('Premium etkinleştirildi 🎉'));
        Navigator.maybePop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showAdToast(context, tr('İşlem tamamlanamadı'));
      }
    }
  }
}

class _FeatureRow extends StatelessWidget {
  final String title;
  final String desc;
  final bool last;
  const _FeatureRow({required this.title, required this.desc, required this.last});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.growthBg),
            alignment: Alignment.center,
            child: const AdenaIcon('check', size: 14, color: Color(0xFF349970), sw: 2.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool selected;
  final String period;
  final String price;
  final String? tag;
  final VoidCallback onTap;
  const _PlanCard({
    required this.selected,
    required this.period,
    required this.price,
    required this.onTap,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.feedBg
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: selected ? AppColors.coral : AppColors.line, width: 2),
            ),
            child: Column(
              children: [
                Text(period.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                        letterSpacing: 0.3)),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                    children: [
                      TextSpan(text: price),
                      TextSpan(
                          text: tr('/ay'),
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (tag != null)
            Positioned(
              top: -9,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                        colors: [AppColors.premiumGoldLight, AppColors.premiumGold]),
                  ),
                  child: Text(tag!,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.premiumInk)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
