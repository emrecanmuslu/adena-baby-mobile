import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/glass.dart';
import '../../core/i18n.dart';
import '../../core/onboarding_paywall.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../data/local_session.dart';
import '../../models/cycle.dart';
import 'onboarding_draft.dart';
import 'onboarding_kit.dart';

/// Onboarding 2. adımı — "Adet takibi" / "Gebe kalmaya çalışıyorum" dalı
/// (tasarım [5]). Hedef karşılama ekranında seçildi; burada yalnız son adet
/// tarihi (+ isteğe bağlı döngü süresi). Bitince bebeksiz Adet Takvimi açılır.
class CycleStartScreen extends ConsumerStatefulWidget {
  /// true → gebe kalmaya çalışma (TTC), false → yalnız takip.
  final bool ttc;
  const CycleStartScreen({super.key, required this.ttc});

  @override
  ConsumerState<CycleStartScreen> createState() => _CycleStartScreenState();
}

class _CycleStartScreenState extends ConsumerState<CycleStartScreen> {
  DateTime? _lastPeriod;
  bool _more = false;
  int _cycleLength = 28;
  bool _saving = false;

  static const _minCycle = 21, _maxCycle = 45;

  String get _route =>
      widget.ttc ? '/onboarding/cycle/ttc' : '/onboarding/cycle/track';
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Her değişiklikte durumu yenile + taslağa yaz (uygulama kapanırsa geri gelsin).
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!_restored || _saving) return;
    OnboardingDraft.saveFields(_route, {
      'lastPeriod': OnboardingDraft.day(_lastPeriod),
      'more': _more,
      'cycleLength': _cycleLength,
    });
  }

  Future<void> _restore() async {
    final d = await OnboardingDraft.read();
    _restored = true;
    if (d == null || d.route != _route || !mounted) return;
    setState(() {
      _lastPeriod = OnboardingDraft.parseDay(d.fields['lastPeriod']);
      _more = d.fields['more'] == true;
      _cycleLength = (d.fields['cycleLength'] as num?)?.toInt() ?? _cycleLength;
    });
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showOnbDatePicker(
      context,
      title: tr('Son adet tarihi'),
      initial: _lastPeriod ?? today,
      first: today.subtract(const Duration(days: 365)),
      last: today,
      accent: OnbAccent.of(context, OnbBranch.cycle),
    );
    if (picked != null && mounted) setState(() => _lastPeriod = picked);
  }

  /// Kurulumu yazar. [skipDate] → "Bilmiyorum, sonra gireceğim" (tarihsiz;
  /// ilk adet girilince takip başlar).
  Future<void> _finish({bool skipDate = false}) async {
    setState(() => _saving = true);
    final goal = widget.ttc
        ? CycleLifecycleMode.ttc
        : CycleLifecycleMode.tracking;
    try {
      final repo = ref.read(cycleRepositoryProvider);
      final initial = await repo.getSettings();
      // Bebeksiz dal: doğum sonrası alanları yok; kurulumu tamamlanmış saymak
      // için breastfeeding=none yazılır (bkz. CycleSetupView, aynı sözleşme).
      final next = initial.copyWith(
        birthDate: null,
        breastfeeding: Breastfeeding.none,
        firstPeriodDate: skipDate ? null : _lastPeriod,
        lifecycleMode: goal,
        ttcStartedAt: widget.ttc
            ? (initial.ttcStartedAt ?? DateTime.now())
            : null,
        expectedCycleLength: _more ? _cycleLength : initial.expectedCycleLength,
        enabled: true,
      );
      await repo.patchSettings(next.toPatchJson());
      await OnboardingPaywall.markOnboarded();
      await OnboardingDraft.clear();
      // Router bebeksiz dala geçer → Adet Takvimi.
      await ref.read(cycleFirstProvider.notifier).set(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = OnbAccent.of(context, OnbBranch.cycle);
    final filled = _lastPeriod != null;
    final daysAgo = filled ? DateTime.now().difference(_lastPeriod!).inDays : 0;
    // Bilerek geri → karşılamaya dön, taslağı bırak.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) OnboardingDraft.clear();
      },
      child: Scaffold(
        body: GlassBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OnbTopBar(accent: a),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.ttc) ...[
                            Text(
                              tr('Gebe kalma takibi').toUpperCaseTr(),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: OnbAccent.sage,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            tr('Son adetin ne zaman başladı?'),
                            style: onbTitleStyle,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr(
                              'Tahminlerin başlangıç noktası bu gün. Bilmiyorsan '
                              'sonra da girebilirsin.',
                            ),
                            style: onbSubStyle(),
                          ),
                          const SizedBox(height: 22),
                          // Büyük tarih kartı.
                          Semantics(
                            button: true,
                            child: GestureDetector(
                              onTap: _pick,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: onbCardFill(context),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: filled
                                        ? a.c
                                        : onbFieldBorder(context),
                                    width: filled ? 1.5 : 1,
                                  ),
                                  boxShadow: AppColors.softShadow,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: a.grad,
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      alignment: Alignment.center,
                                      child: const AdenaIcon(
                                        'calendar',
                                        size: 28,
                                        color: Colors.white,
                                        sw: 1.9,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            filled
                                                ? fmtDayMonthYear(_lastPeriod!)
                                                : tr('Son adet tarihini seç'),
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: filled
                                                  ? AppColors.ink
                                                  : a.t,
                                            ),
                                          ),
                                          if (filled) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              daysAgo == 0
                                                  ? tr('bugün')
                                                  : trp('{n} gün önce', {
                                                      'n': daysAgo,
                                                    }),
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.ink2,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Transform.flip(
                                      flipX:
                                          Directionality.of(context) ==
                                          TextDirection.rtl,
                                      child: AdenaIcon(
                                        'chevR',
                                        size: 20,
                                        color: AppColors.muted,
                                        sw: 2.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // "Daha fazla ayar" — döngü süresi (varsayılan 28 gün).
                          Semantics(
                            button: true,
                            expanded: _more,
                            child: InkWell(
                              onTap: () => setState(() => _more = !_more),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 46,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      tr('Daha fazla ayar'),
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.ink2,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    AnimatedRotation(
                                      turns: _more ? 0.5 : 0,
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      child: AdenaIcon(
                                        'chevD',
                                        size: 18,
                                        color: AppColors.ink2,
                                        sw: 2.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_more)
                            Container(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                16,
                                12,
                                12,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: onbFieldFill(context),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: onbFieldBorder(context),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      tr('Döngün genelde kaç gün sürer?'),
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w800,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                  _StepBtn(
                                    icon: 'minus',
                                    accent: a,
                                    label: tr('Azalt'),
                                    onTap: _cycleLength > _minCycle
                                        ? () => setState(() => _cycleLength--)
                                        : null,
                                  ),
                                  SizedBox(
                                    width: 64,
                                    child: Text(
                                      trp('{n} gün', {'n': _cycleLength}),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  _StepBtn(
                                    icon: 'plus',
                                    accent: a,
                                    label: tr('Artır'),
                                    onTap: _cycleLength < _maxCycle
                                        ? () => setState(() => _cycleLength++)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: a.soft,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: AdenaIcon(
                                    'info',
                                    size: 17,
                                    color: a.t,
                                    sw: 2.2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tr(
                                      'Tahminler kesin değildir ve doğum kontrol '
                                      'yöntemi değildir. Birkaç döngü '
                                      'kaydettikçe güçlenir.',
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.45,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ink2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  OnbPrimaryButton(
                    label: widget.ttc
                        ? tr('Doğurgan pencerelerimi göster')
                        : tr('Takvimimi oluştur'),
                    accent: a,
                    loading: _saving,
                    onTap: filled ? () => _finish() : null,
                  ),
                  const SizedBox(height: 4),
                  OnbTextButton(
                    label: tr('Bilmiyorum, sonra gireceğim'),
                    onTap: _saving ? null : () => _finish(skipDate: true),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Döngü süresi −/+ düğmesi (48px daire).
class _StepBtn extends StatelessWidget {
  final String icon;
  final String label;
  final OnbAccent accent;
  final VoidCallback? onTap;
  const _StepBtn({
    required this.icon,
    required this.label,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: accent.soft, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: AdenaIcon(icon, size: 18, color: accent.t, sw: 2.6),
        ),
      ),
    ),
  );
}
