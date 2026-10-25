import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/onboarding_paywall.dart';
import '../../core/theme.dart';
import '../../data/notification_prefs.dart';
import '../../models/baby.dart';
import '../auth/auth_controller.dart';
import '../babies/members_screen.dart';
import '../onboarding/notif_soft_ask_sheet.dart';
import '../onboarding/onboarding_kit.dart';
import '../records/add_record_sheet.dart';
import '../records/record_controller.dart';

/// Kurulumdan sonra kartın görünür kaldığı süre (tamamlanmasa da).
const _visibleFor = Duration(days: 14);

String _kDismissed(String babyId) => 'first_steps_dismissed_$babyId';
String _kWeekSeen(String babyId) => 'first_steps_week_seen_$babyId';

/// Kartın kalıcı durumu: görünür mü (yeni kurulum + kapatılmadı) ve bekleme
/// modunda "bu haftayı keşfet" yapıldı mı.
class _FirstStepsState {
  final bool visible;
  final bool weekSeen;
  const _FirstStepsState(this.visible, this.weekSeen);
}

final _firstStepsProvider =
    FutureProvider.autoDispose.family<_FirstStepsState, String>((ref, babyId) async {
  final at = await OnboardingPaywall.onboardedAt();
  // Bu özellikten önce kurulmuş kullanıcıya gösterilmez.
  if (at == null || DateTime.now().difference(at) > _visibleFor) {
    return const _FirstStepsState(false, false);
  }
  final prefs = await SharedPreferences.getInstance();
  return _FirstStepsState(prefs.getBool(_kDismissed(babyId)) != true,
      prefs.getBool(_kWeekSeen(babyId)) == true);
});

final _notifEnabledProvider = FutureProvider.autoDispose<bool>(
    (ref) => NotificationService.instance.systemEnabled());

final _pregWeekNotifProvider = FutureProvider.autoDispose<bool>(
    (ref) => NotificationPrefs.instance.enabled(NotificationPrefs.pregnancyWeek));

class _Step {
  final String title;
  final String? desc;
  final String action;
  final bool done;
  final Future<void> Function() run;
  const _Step(this.title, this.desc, this.action, this.done, this.run);
}

/// Ana ekran ilk açılış kartı — "İlk adımlar" (tasarım [6]). Tur dialog'u
/// yerine sayfanın içinde, kapatılabilir; buton sıradaki adımı yapar.
/// [onExploreWeek] bekleme modunda "Bu haftayı keşfet" adımı için (ilgili
/// bölüme kaydırır).
class FirstStepsCard extends ConsumerWidget {
  final Baby baby;
  final VoidCallback? onExploreWeek;
  const FirstStepsCard({super.key, required this.baby, this.onExploreWeek});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(_firstStepsProvider(baby.id)).asData?.value;
    if (st == null || !st.visible) return const SizedBox.shrink();

    final preg = baby.isExpecting;
    final signedIn = ref.watch(authControllerProvider).asData?.value != null;
    final notifOn = ref.watch(_notifEnabledProvider).asData?.value ?? false;

    // Eşini davet et — hesap ister; misafirde önce hesap oluşturma.
    final members = signedIn
        ? (ref.watch(membersProvider(baby.id)).asData?.value.length ?? 0)
        : 0;
    final invite = _Step(
      tr('Eşini davet et'),
      preg
          ? null
          : (signedIn
              ? tr('Bebeği birlikte takip edin.')
              : tr('Önce ücretsiz bir hesap oluşturman gerekir.')),
      tr('Eşini davet et'),
      members > 1,
      () async => context.push(signedIn ? '/members' : '/register'),
    );

    final List<_Step> steps;
    if (preg) {
      final weekNotif = notifOn &&
          (ref.watch(_pregWeekNotifProvider).asData?.value ?? false);
      steps = [
        _Step(tr('Bu haftayı keşfet'), null, tr('Bu haftayı keşfet'), st.weekSeen,
            () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_kWeekSeen(baby.id), true);
          ref.invalidate(_firstStepsProvider(baby.id));
          onExploreWeek?.call();
        }),
        _Step(tr('Haftalık bildirimi aç'), null, tr('Haftalık bildirimi aç'),
            weekNotif, () async {
          final ok = await showNotifSoftAsk(context,
              branch: OnbBranch.preg, force: true);
          if (ok) {
            await NotificationPrefs.instance
                .setEnabled(NotificationPrefs.pregnancyWeek, true);
          }
          ref.invalidate(_notifEnabledProvider);
          ref.invalidate(_pregWeekNotifProvider);
        }),
        invite,
      ];
    } else {
      final hasRecord =
          ref.watch(latestByTypeProvider(baby.id)).asData?.value.isNotEmpty ?? false;
      steps = [
        _Step(
            tr('İlk kaydını ekle'),
            tr('Beslenme, bez ya da uyku — ortadaki + ile saniyeler içinde.'),
            tr('İlk kaydı ekle'),
            hasRecord,
            () => showAddRecordMenu(context, ref, baby.id)),
        _Step(tr('Hatırlatıcı kur'), tr('Sonraki beslenmeyi kaçırma.'),
            tr('Hatırlatıcı kur'), notifOn, () async {
          final ok = await showNotifSoftAsk(context,
              branch: OnbBranch.baby, force: true);
          ref.invalidate(_notifEnabledProvider);
          if (ok && context.mounted) context.push('/notifications');
        }),
        invite,
      ];
    }

    final doneCount = steps.where((s) => s.done).length;
    if (doneCount == steps.length) return const SizedBox.shrink();
    final next = steps.firstWhere((s) => !s.done);
    final a = OnbAccent.of(context, preg ? OnbBranch.preg : OnbBranch.baby);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: dark
            ? a.soft
            : (preg ? const Color(0xC7FAF0D8) : const Color(0xBDFFE9DF)),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.85)),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(
                  preg
                      ? tr('Bekleme odana hoş geldin 🤰')
                      : trp('Hoş geldin! {name} ile ilk gün burada başlıyor ✨',
                          {'name': baby.name}),
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                      letterSpacing: -0.2)),
            ),
            Semantics(
              button: true,
              label: MaterialLocalizations.of(context).closeButtonTooltip,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_kDismissed(baby.id), true);
                  ref.invalidate(_firstStepsProvider(baby.id));
                },
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsetsDirectional.only(start: 10),
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.07)
                        : AppColors.ink.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: AdenaIcon('close', size: 16, color: AppColors.ink2, sw: 2.4),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(trp('{n}/3 tamam', {'n': doneCount}),
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
          const SizedBox(height: 12),
          for (final s in steps) ...[
            _StepRow(step: s, accent: a),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          OnbPrimaryButton(
            label: next.action,
            accent: a,
            height: 52,
            onTap: () => next.run(),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _Step step;
  final OnbAccent accent;
  const _StepRow({required this.step, required this.accent});

  @override
  Widget build(BuildContext context) {
    final done = step.done;
    return MergeSemantics(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          checked: done,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: done ? accent.c : Colors.transparent,
              shape: BoxShape.circle,
              border: done ? null : Border.all(color: AppColors.line2, width: 2),
            ),
            alignment: Alignment.center,
            child: done
                ? const AdenaIcon('check', size: 15, color: Colors.white, sw: 3.2)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(step.title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: done ? AppColors.muted : AppColors.ink,
                      decoration: done ? TextDecoration.lineThrough : null)),
              if (step.desc != null) ...[
                const SizedBox(height: 2),
                Opacity(
                  opacity: done ? 0.6 : 1,
                  child: Text(step.desc!,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink2)),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
