import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/medication_plan.dart';
import '../babies/baby_controller.dart';

/// İlaç & Vitamin Takibi — planları (ad/doz/saat) yönetme ekranı. "Verildi"
/// işaretleme burada DEĞİL, ana sayfadaki günlük checklist'te yapılır (bkz.
/// home_screen.dart _MedicationSection) — burası yalnız kurulum.
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('İlaç & Vitamin Takibi')),
            const SizedBox(width: 8),
            AdInfoDot(
              title: tr('İlaç & Vitamin Takibi'),
              body: tr('Her gün düzenli verdiğin ilaç/vitaminleri buraya ekle. Ana '
                  'sayfada bugünün dozları listelenir, verildiğinde işaretlersin — '
                  'aile paylaşımı açıksa diğer ebeveyn de görür, aynı dozu tekrar '
                  'vermezsiniz.'),
              size: 16,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          async.when(
            loading: () => Column(children: [
              for (var i = 0; i < 2; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Skeleton(height: 68, radius: 16),
                ),
            ]),
            error: (_, _) => const SizedBox.shrink(),
            data: (plans) {
              if (plans.isEmpty) return const _Empty();
              return Column(
                children: [
                  for (final p in plans)
                    _PlanTile(plan: p, babyId: baby.id),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          AdSaveButton(
            label: tr('İlaç / vitamin ekle'),
            color: AppColors.coralDd,
            ghost: true,
            onTap: () => _showAddPlanSheet(context, ref, baby.id),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          AdenaIcon('med', size: 40, color: AppColors.peach),
          const SizedBox(height: 10),
          Text(tr('Henüz ilaç/vitamin eklenmedi'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              tr('D vitamini, demir gibi her gün düzenli verdiklerini ekle — ana '
                  'sayfada bugünün dozlarını görür, işaretlersin.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PlanTile extends ConsumerWidget {
  final MedicationPlan plan;
  final String babyId;
  const _PlanTile({required this.plan, required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timesLabel = ([...plan.times]..sort()).join(' · ');
    return Dismissible(
      key: ValueKey(plan.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 22),
        alignment: Alignment.centerRight,
        decoration:
            BoxDecoration(color: AppColors.feverBg, borderRadius: BorderRadius.circular(16)),
        child: const AdenaIcon('trash', size: 20, color: AppColors.fever),
      ),
      onDismissed: (_) async {
        await ref.read(healthRepositoryProvider).deleteMedicationPlan(plan.id);
        await NotificationService.instance.cancelMedicationPlan(plan.id);
        ref.invalidate(medicationPlansProvider(babyId));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.softShadow,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showAddPlanSheet(context, ref, babyId, existing: plan),
          child: Row(
            children: [
              AdIconChip('med', color: AppColors.med, bg: AppColors.medBg),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 1),
                    Text(
                        [
                          if (plan.dose.isNotEmpty) plan.dose,
                          trp('Her gün {t}', {'t': timesLabel}),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: plan.active,
                activeThumbColor: AppColors.coral,
                onChanged: (v) async {
                  await ref
                      .read(healthRepositoryProvider)
                      .updateMedicationPlan(plan.id, active: v);
                  ref.invalidate(medicationPlansProvider(babyId));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showAddPlanSheet(BuildContext context, WidgetRef ref, String babyId,
    {MedicationPlan? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _AddPlanSheet(babyId: babyId, ref: ref, existing: existing),
  );
}

class _AddPlanSheet extends StatefulWidget {
  final String babyId;
  final WidgetRef ref;
  final MedicationPlan? existing;
  const _AddPlanSheet({required this.babyId, required this.ref, this.existing});

  @override
  State<_AddPlanSheet> createState() => _AddPlanSheetState();
}

class _AddPlanSheetState extends State<_AddPlanSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _dose = TextEditingController(text: widget.existing?.dose ?? '');
  late List<String> _times = widget.existing != null
      ? ([...widget.existing!.times]..sort())
      : ['09:00'];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 21, minute: 0));
    if (picked == null) return;
    final t =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (_times.contains(t)) return;
    setState(() => _times = [..._times, t]..sort());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 16, right: 16, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 14),
              child: Text(
                  widget.existing == null ? tr('İlaç / vitamin ekle') : tr('İlaç / vitamin düzenle'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ),
            AdField(
              label: tr('Ad'),
              child: AdInput(
                controller: _name,
                hint: tr('örn. D vitamini'),
                capitalization: TextCapitalization.sentences,
              ),
            ),
            AdField(
              label: tr('Doz (opsiyonel)'),
              child: AdInput(controller: _dose, hint: tr('örn. 1 damla')),
            ),
            AdField(
              label: tr('Günlük saatler'),
              info: tr('Her gün bu saat(ler)de hatırlatma alırsın. Birden fazla '
                  'doz için saat ekleyebilirsin.'),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _times)
                    Chip(
                      label: Text(t,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                      onDeleted: _times.length > 1
                          ? () => setState(() => _times = _times.where((x) => x != t).toList())
                          : null,
                      backgroundColor: AppColors.medBg,
                    ),
                  ActionChip(
                    avatar: const AdenaIcon('plus', size: 14, color: AppColors.coralDark),
                    label: Text(tr('Saat ekle'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.coralDark)),
                    onPressed: _addTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            AdSaveButton(
              label: _saving ? tr('Kaydediliyor…') : tr('Kaydet'),
              color: AppColors.coral,
              onTap: _saving ? () {} : _save,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showAdError(context, tr('İlaç/vitamin adını gir'));
      return;
    }
    setState(() => _saving = true);
    final repo = widget.ref.read(healthRepositoryProvider);
    try {
      if (widget.existing != null) {
        await repo.updateMedicationPlan(widget.existing!.id,
            name: _name.text.trim(), dose: _dose.text.trim(), times: _times);
      } else {
        await repo.createMedicationPlan(widget.babyId,
            name: _name.text.trim(), dose: _dose.text.trim(), times: _times);
      }
      widget.ref.invalidate(medicationPlansProvider(widget.babyId));
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Kaydedildi'));
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }
}
