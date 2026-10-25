import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adena_icons.dart';
import '../../core/brand.dart';
import '../../core/glass.dart';
import '../../core/i18n.dart';
import '../../core/language_quick_pick.dart';
import '../../core/theme.dart';
import '../../data/local_session.dart';
import '../auth/auth_controller.dart';
import '../auth/pending_auth_action.dart';
import '../babies/baby_switcher.dart';
import 'consent_sheet.dart';
import 'onboarding_draft.dart';
import 'onboarding_kit.dart';

/// İlk ekran — karşılama + hedef seçimi (tasarım [1]). Hesap isteğe bağlı:
/// hedef seçmek uygulamayı hesapsız (yerel) başlatır; giriş/kayıt ikincil yol.
class WelcomeChoiceScreen extends ConsumerStatefulWidget {
  const WelcomeChoiceScreen({super.key});

  @override
  ConsumerState<WelcomeChoiceScreen> createState() =>
      _WelcomeChoiceScreenState();
}

class _WelcomeChoiceScreenState extends ConsumerState<WelcomeChoiceScreen>
    with SingleTickerProviderStateMixin {
  // Kademeli giriş: başlık + kartlar aşağıdan süzülür (900ms, 120ms arayla).
  late final AnimationController _intro = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Kurulum yarıda kaldıysa (uygulama kapatıldı / sistem süreci öldürdü)
    // kullanıcıyı karşılamada bırakma — kaldığı forma, girdikleriyle dön.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeDraft());
  }

  Future<void> _resumeDraft() async {
    final d = await OnboardingDraft.read();
    if (d == null || !mounted || !ref.read(localConsentProvider)) return;
    final signedIn = ref.read(authControllerProvider).asData?.value != null;
    if (!signedIn && !ref.read(guestModeProvider)) return;
    context.push(d.route);
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// [i]. öğenin kademeli fade+slide sarmalayıcısı.
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

  /// Hedef seçildi: (gerekirse) rıza → (hesapsızsa) yerel oturum → form.
  Future<void> _choose(OnbBranch b) async {
    if (_busy) return;
    _busy = true;
    try {
      if (!ref.read(localConsentProvider)) {
        final ok = await showConsentSheet(context,
            accent: OnbAccent.of(context, b));
        if (!ok || !mounted) return;
      }
      final signedIn = ref.read(authControllerProvider).asData?.value != null;
      if (!signedIn && !ref.read(guestModeProvider)) {
        await ref.read(guestModeProvider.notifier).enter();
      }
      if (!mounted) return;
      final route = switch (b) {
        OnbBranch.baby => '/onboarding/baby/born',
        OnbBranch.preg => '/onboarding/baby/expecting',
        OnbBranch.cycle => '/onboarding/cycle/track',
        OnbBranch.ttc => '/onboarding/cycle/ttc',
      };
      // Önceki (başka daldaki) taslak varsa yenisiyle değişir.
      final prev = await OnboardingDraft.read();
      if (prev?.route != route) await OnboardingDraft.start(route);
      if (!mounted) return;
      context.push(route);
    } finally {
      _busy = false;
    }
  }

  void _invite() {
    final signedIn = ref.read(authControllerProvider).asData?.value != null;
    if (signedIn) {
      showAcceptInviteDialog(context, ref);
    } else {
      // Davet kabulü oturum ister → önce giriş/kayıt; sonra burada otomatik açılır.
      ref.read(pendingAuthActionProvider.notifier).set(PendingAuthAction.invite);
      context.push('/register?ctx=invite');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final localName = ref.watch(localNameProvider);
    final greetName = user != null
        ? user.displayName.split(' ').first
        : (localName.isNotEmpty ? localName.split(' ').first : '');

    // Hesapsızken "Davet kodum var" seçilip giriş yapıldıysa sayfayı aç.
    consumePendingAuthAction(context, ref);

    final goals = [
      (OnbBranch.baby, 'feed', tr('Bebeğim doğdu'),
          tr('Beslenme, uyku, gelişim — takibe hemen başla')),
      (OnbBranch.preg, 'pregnant', tr('Hamileyim'),
          tr('Hafta hafta gebelik takibi ve bekleme odası')),
      (OnbBranch.cycle, 'drop', tr('Adet takibi'), tr('Döngünü ve adetini izle')),
      (OnbBranch.ttc, 'ttc', tr('Gebe kalmaya çalışıyorum'),
          tr('Ovülasyon ve doğurgan pencereni takip et')),
    ];
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Üst şerit: dil çipi (başta) + marka (ortada).
                      SizedBox(
                        height: 56,
                        child: Stack(alignment: Alignment.center, children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: _LangChip(
                              label: currentLanguageName(ref),
                              onTap: () => showOnbSheet<void>(context,
                                  builder: (_) => const LanguageSheetList()),
                            ),
                          ),
                          const BrandWordmark(fontSize: 20),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      _stagger(
                        0,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trp('Merhaba{name} 👋', {
                                'name': greetName.isNotEmpty ? ' $greetName' : ''
                              }),
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6,
                                  height: 1.15),
                            ),
                            const SizedBox(height: 8),
                            Text(
                                tr('Seni ne getirdi? Sana uygun olanı seç, '
                                    'gerisini biz hazırlayalım.'),
                                style: onbSubStyle()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      for (var i = 0; i < goals.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _stagger(
                          i + 1,
                          _GoalCard(
                            branch: goals[i].$1,
                            icon: goals[i].$2,
                            title: goals[i].$3,
                            sub: goals[i].$4,
                            onTap: () => _choose(goals[i].$1),
                          ),
                        ),
                      ],
                      _stagger(
                        5,
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(children: [
                            if (user == null)
                              _LinkRow(
                                lead: tr('Zaten hesabın var mı?'),
                                action: tr('Giriş yap'),
                                onTap: () => context.push('/login'),
                              )
                            else
                              _AccountChip(
                                name: user.displayName,
                                onSwitch: () => ref
                                    .read(authControllerProvider.notifier)
                                    .logout(),
                              ),
                            _LinkRow(
                                action: tr('Davet kodum var'), onTap: _invite),
                          ]),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: AdenaIcon('lock',
                                  size: 15, color: AppColors.muted, sw: 2),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                tr('Verilerin gizli, yalnızca sana ait. Hesap '
                                    'açmadan kullanabilirsin.'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.muted),
                              ),
                            ),
                          ],
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

/// Dil çipi (cam hap: küre + dil adı).
class _LangChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LangChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Dil / Language: $label',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: onbCardFill(context),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: onbFieldBorder(context)),
              boxShadow: AppColors.softShadow,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AdenaIcon('globe', size: 16, color: AppColors.ink2, sw: 2),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink2)),
            ]),
          ),
        ),
      );
}

/// Cam hedef kartı: gradyan ikon plakası + başlık + açıklama + ok.
class _GoalCard extends StatefulWidget {
  final OnbBranch branch;
  final String icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _GoalCard({
    required this.branch,
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  State<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<_GoalCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final plate = OnbAccent.plate(context, widget.branch);
    final shadow = OnbAccent.of(context, widget.branch).shadow;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: '${widget.title}. ${widget.sub}',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          child: GlassCard(
            radius: 22,
            padding: const EdgeInsets.all(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: plate,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: shadow, blurRadius: 14, offset: const Offset(0, 6))
                    ],
                  ),
                  alignment: Alignment.center,
                  child: AdenaIcon(widget.icon,
                      size: 28, color: Colors.white, sw: 1.9),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                              height: 1.25)),
                      const SizedBox(height: 3),
                      Text(widget.sub,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: AppColors.ink2)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Transform.flip(
                  flipX: rtl,
                  child: AdenaIcon('chevR',
                      size: 20, color: AppColors.muted, sw: 2.2),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// İkincil bağlantı satırı ("Zaten hesabın var mı? Giriş yap" / "Davet kodum var").
class _LinkRow extends StatelessWidget {
  final String? lead;
  final String action;
  final VoidCallback onTap;
  const _LinkRow({this.lead, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final coral = Theme.of(context).brightness == Brightness.dark
        ? AppColors.coral
        : AppColors.coralDd;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text.rich(
            TextSpan(children: [
              if (lead != null)
                TextSpan(
                    text: '$lead ',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink2)),
              TextSpan(
                  text: action,
                  style: TextStyle(fontWeight: FontWeight.w900, color: coral)),
            ]),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14.5),
          ),
        ),
      ),
    );
  }
}

/// Giriş yapmış (bebeği olmayan) kullanıcı: "Zeynep olarak giriş yaptın · Hesabı değiştir".
class _AccountChip extends StatelessWidget {
  final String name;
  final VoidCallback onSwitch;
  const _AccountChip({required this.name, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final coral = Theme.of(context).brightness == Brightness.dark
        ? AppColors.coral
        : AppColors.coralDd;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onSwitch,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: onbCardFill(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: onbFieldBorder(context)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                    colors: [AppColors.coral, AppColors.coralDd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
              ),
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '${trp('{name} olarak giriş yaptın', {'name': name})} · ',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.ink2)),
                  TextSpan(
                      text: tr('Hesabı değiştir'),
                      style: TextStyle(fontWeight: FontWeight.w900, color: coral)),
                ]),
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
