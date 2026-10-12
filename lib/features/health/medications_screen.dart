import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../data/sync_gate.dart';
import '../../core/medication.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../data/notification_prefs.dart';
import '../../models/medication_plan.dart';
import '../babies/baby_controller.dart';
import '../settings/notification_prefs_controller.dart';
import 'medication_plan_sheet.dart';
import 'medication_widgets.dart';

/// İlaç & Vitamin — planları (ad/doz/saat) yönetme ekranı. Aktif planların
/// bugünkü saatleri kartın içinde çip olarak durur ve ana sayfadakiyle AYNI
/// kurallarla işaretlenebilir (bkz. medTapDose). Duraklatılan planlar ayrı
/// bölümde, tek dokunuşla devam ettirilir.
class MedicationsScreen extends ConsumerWidget {
  const MedicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final async = ref.watch(medicationPlansProvider(baby.id));
    final day = ref.watch(medicationDayProvider(baby.id));
    final plans = async.asData?.value;
    final isEmpty = plans != null && plans.isEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('İlaç & Vitamin')),
            if (day != null && day.total > 0)
              Text(
                  trp('Bugün {done}/{total} doz verildi',
                      {'done': day.done, 'total': day.total}),
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ],
        ),
        actions: [
          if (!isEmpty)
            if (baby.canFullWrite) // KB-8: bakıcı plan ekleyemez
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14),
              child: Semantics(
                button: true,
                label: tr('İlaç / vitamin ekle'),
                child: GestureDetector(
                  onTap: () => showMedicationPlanSheet(context, baby.id),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.coral,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Color(0x4DE2553F), blurRadius: 14, offset: Offset(0, 6)),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const AdenaIcon('plus', size: 20, color: Colors.white, sw: 2.4),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: isEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: baby.canFullWrite
                    ? AdSaveButton(
                        label: tr('Kendi planını ekle'),
                        color: AppColors.coral,
                        onTap: () => showMedicationPlanSheet(context, baby.id),
                      )
                    : const SizedBox.shrink(), // KB-8
              ),
            )
          : null,
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            for (var i = 0; i < 2; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Skeleton(height: 96, radius: 20),
              ),
          ],
        ),
        error: (_, _) => const SizedBox.shrink(),
        data: (plans) => plans.isEmpty
            ? _EmptyBody(babyId: baby.id)
            : _PlansBody(babyId: baby.id, plans: plans, day: day),
      ),
    );
  }
}

class _PlansBody extends ConsumerWidget {
  final String babyId;
  final List<MedicationPlan> plans;
  final MedicationDay? day;
  const _PlansBody({required this.babyId, required this.plans, required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final completed = plans.where((p) => p.isCompletedAt(now)).toList();
    final active = plans.where((p) => p.active && !p.isCompletedAt(now)).toList();
    final paused = plans.where((p) => !p.active && !p.isCompletedAt(now)).toList();
    // M11: sahip premium'u bitti / erişim 403 → aile senkronu durdu.
    final readonly = ref.watch(cloudReadonlyBabiesProvider).contains(babyId);
    final rows = {for (final r in day?.rows ?? const <MedicationPlanDay>[]) r.plan.id: r};
    final notifOn = ref.watch(notifPrefProvider(NotificationPrefs.medication));

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        if (readonly) ...[
          const SizedBox(height: 4),
          _InfoNote(
              icon: 'cloud',
              text: tr('Aile senkronu durdu — değişikliklerin yalnız bu telefonda kalır.')),
          const SizedBox(height: 6),
        ],
        if (active.isNotEmpty) ...[
          adSec(trp('Aktif planlar · {n}', {'n': active.length})),
          for (final p in active)
            _PlanCard(babyId: babyId, plan: p, row: rows[p.id]),
        ],
        if (paused.isNotEmpty) ...[
          adSec(tr('Duraklatılan')),
          for (final p in paused) _PausedCard(babyId: babyId, plan: p),
        ],
        if (completed.isNotEmpty) ...[
          adSec(tr('Tamamlananlar')),
          for (final p in completed) _PausedCard(babyId: babyId, plan: p, completed: true),
        ],
        adSec(tr('Hatırlatma')),
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Doz bildirimleri'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 1),
                    Text(tr('Her doz saatinde hatırlatır'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: notifOn,
                activeThumbColor: AppColors.coral,
                onChanged: (v) => ref
                    .read(notifPrefsProvider.notifier)
                    .set(NotificationPrefs.medication, v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _InfoNote(
          icon: 'family',
          // KB-8: rol farkı — bakıcı yalnız doz işaretler.
          text: ref.watch(canFullWriteProvider(babyId)) // N1
              ? tr('Verilen dozlar ve plan listesi ailenle paylaşılır.')
              : tr('Bakıcı rolünde planları ebeveyn/sahip düzenler; sen dozları işaretleyebilirsin.'),
        ),
      ],
    );
  }
}

class _PlanCard extends ConsumerWidget {
  final String babyId;
  final MedicationPlan plan;
  final MedicationPlanDay? row;
  const _PlanCard({required this.babyId, required this.plan, required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // KB-8/N1: kilit KARTIN bebeğinin rolüne göre (aktif bebek değil); bakıcı
    // düzenleyemez (düğme çizilmez; repo da StateError ile korur).
    final canEdit = ref.watch(canFullWriteProvider(babyId));
    void edit() => showMedicationPlanSheet(context, babyId, existing: plan);
    final meta = [
      if (plan.dose.isNotEmpty) plan.dose,
      medPlanSchedule(plan),
      if (plan.localOnly) tr('Bu plan yalnız bu cihazda; ailenle paylaşılmadı'), // N2
      if (plan.syncError != null) tr('Sunucu bu değişikliği kabul etmedi — planı düzenle'),
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdIconChip('med', color: AppColors.med, bg: AppColors.medBg),
              const SizedBox(width: 12),
              Expanded(child: _PlanTitle(name: plan.name, meta: meta)),
              const SizedBox(width: 8),
              if (plan.localOnly) // N2/KB-10: yerel-only plan — bakıcı silebilir
                Semantics(
                  button: true,
                  label: tr('Sil'),
                  child: GestureDetector(
                    onTap: () async {
                      await ref.read(healthRepositoryProvider).deleteMedicationPlan(plan.id);
                      ref.invalidate(medicationPlansProvider(babyId));
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: fieldBg(context), borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: AdenaIcon('trash', size: 18, color: AppColors.ink2),
                    ),
                  ),
                )
              else if (canEdit)
              Semantics(
                button: true,
                label: tr('Düzenle'),
                child: GestureDetector(
                  onTap: edit,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: fieldBg(context), borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: AdenaIcon('edit', size: 18, color: AppColors.ink2),
                  ),
                ),
              ),
            ],
          ),
          if (row != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 50, top: 11),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final d in row!.doses) MedTimeChip(babyId: babyId, dose: d),
                ],
              ),
            ),
          _HistoryLink(babyId: babyId, plan: plan),
        ],
      ),
    );
  }
}

class _PausedCard extends ConsumerWidget {
  final String babyId;
  final MedicationPlan plan;
  /// K8: kürü biten plan — "Yeniden başlat" düzenleme sayfasını açar.
  final bool completed;
  const _PausedCard({required this.babyId, required this.plan, this.completed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = [
      if (plan.dose.isNotEmpty) plan.dose,
      completed && plan.endDate != null
          ? trp('{d} tarihinde bitti', {'d': fmtDayMon(plan.endDate!)})
          : tr('hatırlatma yok'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CustomPaint(
        painter: MedDashedBorder(color: AppColors.line2, radius: 20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: ref.watch(canFullWriteProvider(babyId)) // N1
              ? () => showMedicationPlanSheet(context, babyId, existing: plan)
              : null, // KB-8
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                AdIconChip('med', color: AppColors.muted, bg: AppColors.line),
                const SizedBox(width: 12),
                Expanded(child: _PlanTitle(name: plan.name, meta: meta)),
                const SizedBox(width: 8),
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: completed
                        ? () => showMedicationPlanSheet(context, babyId, existing: plan)
                        : () async {
                            await ref
                                .read(healthRepositoryProvider)
                                .updateMedicationPlan(plan.id, active: true);
                            ref.invalidate(medicationPlansProvider(babyId));
                          },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      alignment: Alignment.center,
                      child: Text(completed ? tr('Yeniden başlat') : tr('Devam ettir'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: AppColors.coralDark)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanTitle extends StatelessWidget {
  final String name;
  final String meta;
  const _PlanTitle({required this.name, required this.meta});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, height: 1.25)),
        const SizedBox(height: 2),
        Text(meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ],
    );
  }
}

class _InfoNote extends StatelessWidget {
  final String icon;
  final String text;
  const _InfoNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AdenaIcon(icon, size: 16, color: AppColors.muted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

/// Boş durum: kısa tanıtım + "Hızlı başla" önerileri (dokun → dolu plan sayfası).
class _EmptyBody extends StatelessWidget {
  final String babyId;
  const _EmptyBody({required this.babyId});

  @override
  Widget build(BuildContext context) {
    final suggestions = medicationSuggestions();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 16),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
                color: AppColors.medBg, borderRadius: BorderRadius.circular(28)),
            alignment: Alignment.center,
            child: const AdenaIcon('med', size: 40, color: AppColors.med, sw: 1.6),
          ),
        ),
        const SizedBox(height: 14),
        Text(tr('Henüz plan yok'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
              tr('Her gün düzenli verdiğin vitamin ve ilaçları ekle. Saatinde '
                  'hatırlatalım, tek dokunuşla işaretle.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
        ),
        adSec(tr('Hızlı başla')),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.softShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < suggestions.length; i++)
                InkWell(
                  onTap: () => showMedicationPlanSheet(context, babyId,
                      presetName: suggestions[i].name, presetTime: suggestions[i].time),
                  child: Container(
                    decoration: BoxDecoration(
                      border:
                          i > 0 ? Border(top: BorderSide(color: AppColors.line)) : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        AdIconChip('med',
                            color: AppColors.med, bg: AppColors.medBg, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PlanTitle(
                            name: suggestions[i].name,
                            meta: trp('Önerilen: {n} kez · {t}',
                                {'n': 1, 't': suggestions[i].time}),
                          ),
                        ),
                        const AdenaIcon('plus', size: 20, color: AppColors.coralDark, sw: 2.4),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _InfoNote(
          icon: 'shield',
          text: tr('Doz ve saatleri doktorunun önerisine göre ayarla.'),
        ),
      ],
    );
  }
}


/// Planın sıklık özeti (yönetim kartı meta satırı).
String medPlanSchedule(MedicationPlan p) {
  if (p.isPrn) return tr('ihtiyaç halinde');
  final n = p.times.length;
  final base = switch (p.freq) {
    MedFreq.interval => trp('her {h} saatte', {'h': p.intervalHours ?? 0}),
    MedFreq.everyNDays => p.everyNDays == 2
        ? trp('gün aşırı · {n} doz', {'n': n})
        : trp('{d} günde bir · {n} doz', {'d': p.everyNDays ?? 0, 'n': n}),
    MedFreq.weekly => trp('{days} · {n} doz', {
        'days': [for (final d in [...p.weekdays]..sort()) fmtWeekdayShort(DateTime(2026, 10, 11 + d))]
            .join(', '),
        'n': n,
      }),
    MedFreq.daily => trp('her gün · {n} doz', {'n': n}),
  };
  final end = p.endDate;
  return end == null ? base : '$base · ${trp('bitiş {d}', {'d': fmtDayMon(end)})}';
}

/// K11: "Geçmiş" bağlantısı (plan başına 7/30 gün).
class _HistoryLink extends StatelessWidget {
  final String babyId;
  final MedicationPlan plan;
  const _HistoryLink({required this.babyId, required this.plan});

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          onPressed: () => context.push('/medications/history/$babyId/${plan.id}'),
          child: Text(tr('Geçmiş'),
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.coralDark)),
        ),
      );
}
