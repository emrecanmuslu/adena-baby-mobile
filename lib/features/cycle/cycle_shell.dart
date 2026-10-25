import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/modal_gate.dart';
import '../../core/notif_soft_ask.dart';
import '../../core/onboarding_paywall.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import '../auth/pending_auth_action.dart';
import '../babies/baby_controller.dart';
import '../onboarding/notif_soft_ask_sheet.dart';
import '../onboarding/onboarding_kit.dart';
import 'cycle_calendar_screen.dart';
import 'cycle_pregnancy_bridge.dart';
import 'cycle_setup_screen.dart';
import 'cycle_stats_screen.dart';
import 'cycle_today_screen.dart';

/// "Uygulama içinde uygulama" kabuğu — pembe dünya: logolu header her ekranda,
/// kendi alt menüsü (Bugün · Takvim · Analiz │ Bebek köprüsü). Kurulmamışsa
/// önce sihirbazı gösterir (nav yok).
class CycleShell extends ConsumerStatefulWidget {
  const CycleShell({super.key});

  @override
  ConsumerState<CycleShell> createState() => _CycleShellState();
}

class _CycleShellState extends ConsumerState<CycleShell>
    with WidgetsBindingObserver {
  int _index = 0;
  DateTime _day = _todayOnly();
  bool _softAskChecked = false;

  static DateTime _todayOnly() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotifSoftAsk.wanted.addListener(_onSoftAskWanted);
  }

  /// Adet hatırlatıcısı kuruldu ama ön-izin kabul edilmemiş → uygun anda sor.
  bool _softAskBusy = false;

  Future<void> _onSoftAskWanted() async {
    if (_softAskBusy || !mounted) return;
    _softAskBusy = true;
    try {
      await _softAskNow();
    } finally {
      _softAskBusy = false;
    }
  }

  Future<void> _softAskNow() async {
    await SystemPromptGate.whenClear();
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (!await NotifSoftAsk.mayAskAgain() || !mounted) return;
    final ttc = ref.read(cycleSettingsProvider).asData?.value.lifecycleMode ==
        CycleLifecycleMode.ttc;
    ModalGate.acquire();
    try {
      await showNotifSoftAsk(context,
          branch: ttc ? OnbBranch.ttc : OnbBranch.cycle, force: true);
    } finally {
      ModalGate.release();
    }
  }

  @override
  void dispose() {
    NotifSoftAsk.wanted.removeListener(_onSoftAskWanted);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Bildirim ön-izni — bebeksiz adet dalında kurulumdan sonraki günden
  /// itibaren bir kez (kurulumun hemen ardından değil).
  Future<void> _maybeSoftAsk(bool ttc) async {
    final at = await OnboardingPaywall.onboardedAt();
    if (!mounted || (at != null && DateUtils.isSameDay(at, DateTime.now()))) return;
    ModalGate.acquire();
    try {
      await showNotifSoftAsk(context,
          branch: ttc ? OnbBranch.ttc : OnbBranch.cycle);
    } finally {
      ModalGate.release();
    }
  }

  /// Uzun uykudan/arka plandan dönüşte gün değiştiyse "bugün" yeniden hesaplansın.
  /// Aksi halde Today/Takvim ekranları son build'deki bayat DateTime.now()'da kalır
  /// (gün dönümünü yalnız tam restart yakalardı). Sağlayıcıları geçersiz kılınca
  /// computeStatus taze tarihle yeniden koşar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final t = _todayOnly();
    if (t == _day) return;
    _day = t;
    ref.invalidate(cycleEntriesProvider);
    ref.invalidate(cycleSettingsProvider);
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(cycleSettingsProvider);
    final baby = ref.watch(activeBabyProvider);

    return settingsAsync.when(
      loading: () => Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.rose))),
      error: (e, _) => Scaffold(
          body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(apiErrorText(e))))),
      data: (settings) {
        // Bebeği yoksa "adet & gebelik takibi" (bebeksiz) dalındayız → sihirbaz
        // Flo-tarzı (hedef + son adet), alt menüde "Bebek" yerine "Bebek ekle".
        final hasBaby = baby != null;
        // Kurulmamış → sihirbaz (nav yok, kabuk dışı tam ekran).
        if (settings.breastfeeding == null) {
          return CycleSetupView(
            initial: settings,
            babyBirthDate: baby?.birthDate,
            cycleFirst: !hasBaby,
            onDone: () {}, // ayar yazımı akışa düşer (Stream); yenileme gerekmez
          );
        }
        // Kurulum bitti, asıl ekrandayız → ertelenen sistem izin penceresi
        // (adet hatırlatıcıları) artık açılabilir.
        SystemPromptGate.markAppReady();
        consumePendingAuthAction(context, ref);
        if (!_softAskChecked) {
          _softAskChecked = true;
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _maybeSoftAsk(settings.lifecycleMode == CycleLifecycleMode.ttc));
        }
        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: const [
              CycleTodayScreen(),
              CycleCalendarScreen(),
              CycleStatsScreen(),
            ],
          ),
          // Köprü slotu hedefe duyarlı: bebek varsa "Bebek"e dönüş; bebeksiz
          // TTC'de doğal sonraki adım "Gebe kaldım" (yaşam-döngüsü köprüsü —
          // /baby-add'e doğrudan gitmek lifecycleMode'u atlardı); bebeksiz
          // yalnız-takipte slot GİZLİ ("Bebek ekle" ayarlara taşındı).
          bottomNavigationBar: CycleNav(
            active: _index,
            onTap: (i) => setState(() => _index = i),
            bridge: hasBaby
                ? CycleNavBridge(
                    icon: Icons.child_care_rounded,
                    label: tr('Bebek'),
                    onTap: _back)
                : settings.lifecycleMode == CycleLifecycleMode.ttc
                    ? CycleNavBridge(
                        icon: Icons.pregnant_woman_rounded,
                        label: tr('Gebe kaldım'),
                        onTap: () =>
                            startCyclePregnancy(context, ref, settings))
                    : null,
          ),
        );
      },
    );
  }
}

/// Pembe modülün üst barı — bizim **logomuz** (BrandWordmark) + çan/dişli.
/// Marka sürekliliği: pembe dünyaya geçsek de hâlâ Adena.
class CycleHeader extends StatelessWidget {
  final VoidCallback? onSettings;
  final VoidCallback? onBell;
  const CycleHeader({super.key, this.onSettings, this.onBell});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 12, 2),
      child: Row(
        children: [
          const BrandWordmark(fontSize: 26),
          const Spacer(),
          if (onBell != null) _iconBtn(context, Icons.notifications_none_rounded, onBell!),
          _iconBtn(context, Icons.settings_outlined, onSettings ?? () {}),
        ],
      ),
    );
  }

  Widget _iconBtn(BuildContext context, IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: AppColors.smallShadow),
          child: Icon(icon, size: 20, color: AppColors.ink2),
        ),
      );
}

/// Köprü slotunun içeriği (ikon + etiket + aksiyon). null → slot gizlenir.
class CycleNavBridge {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const CycleNavBridge(
      {required this.icon, required this.label, required this.onTap});
}

/// Pembe alt menü — yüzen ada (hap). Bugün · Takvim · Analiz │ köprü (opsiyonel:
/// "Bebek" dönüşü veya TTC'de "Gebe kaldım"). Ortada + FAB YOK; ekleme bağlamsal.
class CycleNav extends StatelessWidget {
  final int active;
  final ValueChanged<int> onTap;
  final CycleNavBridge? bridge;
  const CycleNav(
      {super.key, required this.active, required this.onTap, this.bridge});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
          boxShadow: AppColors.softShadow,
        ),
        child: Row(
          children: [
            _item(0, Icons.favorite_rounded, tr('Bugün')),
            _item(1, Icons.calendar_month_rounded, tr('Takvim')),
            _item(2, Icons.insights_rounded, tr('Analiz')),
            if (bridge != null) ...[
              Container(width: 1, height: 28, color: AppColors.line2),
              _bridgeItem(bridge!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final on = active == i;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: on
              ? BoxDecoration(
                  color: AppColors.roseBg, borderRadius: BorderRadius.circular(16))
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: on ? AppColors.roseD : AppColors.muted),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                      color: on ? AppColors.roseD : AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bridgeItem(CycleNavBridge b) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: b.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(b.icon, size: 22, color: AppColors.coralDd),
                const SizedBox(height: 3),
                Text(b.label,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.coralDd)),
              ],
            ),
          ),
        ),
      );
}
