import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adena_icons.dart';
import '../../core/brand.dart';
import '../../core/glass.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/local_session.dart';
import '../../models/baby.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_switcher.dart';

/// Onboarding giriş kapısı: kullanıcı ne için geldiğini SEÇER, form sonra gelir.
/// Tasarım: design/"Welcome Ekranı - Final (Standalone).html" ("Gradyan & Cam")
/// — ortak kit core/glass.dart (GlassBackground + GlassCard) ile uygulanır.
class WelcomeChoiceScreen extends ConsumerStatefulWidget {
  const WelcomeChoiceScreen({super.key});

  @override
  ConsumerState<WelcomeChoiceScreen> createState() =>
      _WelcomeChoiceScreenState();
}

class _WelcomeChoiceScreenState extends ConsumerState<WelcomeChoiceScreen>
    with SingleTickerProviderStateMixin {
  // Kademeli giriş animasyonu: başlık + kartlar sırayla yukarı süzülür.
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// [i]. öğenin kademeli fade+slide sarmalayıcısı (0=başlık, 1..3=kartlar, 4=alt).
  Widget _stagger(int i, Widget child) {
    final a = CurvedAnimation(
      parent: _intro,
      curve: Interval((i * 0.12).clamp(0, 0.6), (0.5 + i * 0.12).clamp(0, 1),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: a,
      builder: (_, c) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, 22 * (1 - a.value)), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authControllerProvider).asData?.value;
    final localName = ref.watch(localNameProvider);
    final greetName = user != null
        ? user.displayName
        : (localName.isNotEmpty ? localName.split(' ').first : '');

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 14),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Üst şerit: marka + (girişliyse) çıkış.
                      SizedBox(
                        height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Center(child: BrandWordmark(fontSize: 24)),
                            if (user != null)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => ref
                                      .read(authControllerProvider.notifier)
                                      .logout(),
                                  child: Text(tr('Çıkış'),
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.ink2
                                              .withValues(alpha: 0.75))),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _stagger(
                        0,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trp('Merhaba{name} 👋', {
                                'name':
                                    greetName.isNotEmpty ? ' $greetName' : ''
                              }),
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.7,
                                  height: 1.1),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('Nereden başlayalım? Sana uygun olanı seç.'),
                              style: TextStyle(
                                  color: AppColors.ink2,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      _stagger(
                        1,
                        _ChoiceCard(
                          icon: 'baby',
                          gradient: const [AppColors.coral, AppColors.coralDd],
                          title: tr('Bebeğim doğdu'),
                          sub: tr('Beslenme, uyku, gelişim — takibe hemen başla'),
                          onTap: () => context.push('/onboarding/baby',
                              extra: BabyStatus.born),
                        ),
                      ),
                      const SizedBox(height: 13),
                      _stagger(
                        2,
                        _ChoiceCard(
                          icon: 'heart',
                          gradient: const [Color(0xFFE3B255), Color(0xFFCC8A3C)],
                          title: tr('Hamileyim'),
                          sub: tr('Hafta hafta gebelik takibi ve bekleme odası'),
                          onTap: () => context.push('/onboarding/baby',
                              extra: BabyStatus.expecting),
                        ),
                      ),
                      const SizedBox(height: 13),
                      _stagger(
                        3,
                        _ChoiceCard(
                          icon: 'calendar',
                          gradient: const [Color(0xFFD9799A), Color(0xFFB0466B)],
                          title: tr('Adet & gebe kalma takibi'),
                          sub: tr('Döngünü izle, gebeliğe hazırlan — bebek eklemeden'),
                          onTap: () async {
                            // Bebeksiz dal: router'ı bebek zorunluluğundan muaf
                            // tutan bayrak + Adet Takvimi. Bebek sonra eklenebilir.
                            await ref.read(cycleFirstProvider.notifier).set(true);
                            if (context.mounted) context.go('/cycle');
                          },
                        ),
                      ),
                      _stagger(
                        4,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 22),
                              child: Row(
                                children: [
                                  Expanded(child: _VeyaLine(dark: dark)),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14),
                                    child: Text(tr('veya').toUpperCaseTr(),
                                        style: TextStyle(
                                            color: AppColors.ink2
                                                .withValues(alpha: 0.6),
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11.5,
                                            letterSpacing: 2.8)),
                                  ),
                                  Expanded(child: _VeyaLine(dark: dark)),
                                ],
                              ),
                            ),
                            // Oturum açıkken: davet koduyla paylaşımlı bebeğe
                            // katıl; hesapsızsa giriş (davet kabulü oturum ister).
                            if (user != null)
                              _SecondaryLink(
                                label: tr('Davet kodum var'),
                                sub: tr('Eşin veya bakıcın bebeği zaten '
                                    'eklediyse, paylaştığı kodla katıl.'),
                                onTap: () =>
                                    showAcceptInviteDialog(context, ref),
                              )
                            else
                              _SecondaryLink(
                                label: tr('Giriş yap / Hesap oluştur'),
                                sub: tr('Zaten hesabın varsa veya bir bebeğe '
                                    'davet edildiysen giriş yap.'),
                                onTap: () => context.push('/login'),
                              ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _stagger(
                        4,
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 24),
                          child: Center(
                            child: Text(
                              '🔒 ${tr('Verilerin gizli, yalnızca sana ait')}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      AppColors.ink2.withValues(alpha: 0.85)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// VEYA ayracının yarım çizgisi (temaya duyarlı ince hat).
class _VeyaLine extends StatelessWidget {
  final bool dark;
  const _VeyaLine({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.5,
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFF3D2B26).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Buzlu cam hedef kartı: gradyan ikon plakası + başlık + açıklama + ok.
class _ChoiceCard extends StatelessWidget {
  final String icon;
  final List<Color> gradient;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _ChoiceCard({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(15, 17, 15, 17),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF3D2B26).withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 6)),
              ],
            ),
            // İç üst parlaklık: mockup'taki inset highlight taklidi.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0, 0.42],
              ),
            ),
            child: AdenaIcon(icon, size: 26, color: Colors.white),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                        color: AppColors.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded,
              size: 22, color: AppColors.ink2.withValues(alpha: 0.55)),
        ],
      ),
    );
  }
}

/// İkincil yol (davet kodu / giriş): daha şeffaf cam, ortalanmış metin bloğu.
class _SecondaryLink extends StatelessWidget {
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _SecondaryLink({
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      radius: 18,
      sigma: 12,
      lightAlpha: 0.35,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        children: [
          Text(label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  color: AppColors.ink2)),
        ],
      ),
    );
  }
}
