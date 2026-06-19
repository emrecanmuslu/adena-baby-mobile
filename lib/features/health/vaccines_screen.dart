import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/vaccine.dart';
import '../babies/baby_controller.dart';

/// TR aşı takvimi: doğum tarihinden üretilen aşılar, yapıldı işaretleme.
class VaccinesScreen extends ConsumerWidget {
  const VaccinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final async = ref.watch(vaccinesProvider(baby.id));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Aşı takvimi')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.coral)),
        error: (e, _) => Center(child: Text(apiErrorText(e))),
        data: (vaccines) {
          if (vaccines.isEmpty) {
            return const _Empty();
          }
          final done = vaccines.where((v) => v.done).length;
          // Sıralı + ilk bekleyen aşı vurgulanır (design 'due').
          final sorted = [...vaccines]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
          final firstPending = sorted.where((v) => !v.done).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _SummaryCard(done: done, total: vaccines.length),
              adSec(tr('TR Aşı Takvimi')),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppColors.softShadow,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < sorted.length; i++)
                      _VacRow(
                        vaccine: sorted[i],
                        babyId: baby.id,
                        highlighted: identical(sorted[i], firstPending),
                        last: i == sorted.length - 1,
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int done;
  final int total;
  const _SummaryCard({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? done / total : 0.0;
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.growth.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trp('{done} / {total} aşı yapıldı', {'done': done, 'total': total}),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.7),
              valueColor: const AlwaysStoppedAnimation(AppColors.growth),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aşı zaman-çizelgesi satırı (design .ad-vac): marker + bağlantı çizgisi + body.
/// Marker'a dokununca yapıldı/geri al.
class _VacRow extends ConsumerWidget {
  final Vaccine vaccine;
  final String babyId;
  final bool highlighted; // ilk bekleyen (yaklaşan)
  final bool last;
  const _VacRow({
    required this.vaccine,
    required this.babyId,
    required this.highlighted,
    required this.last,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = vaccine;
    // Durum: done · due (yaklaşan/gecikmiş) · future.
    final state = v.done ? 'done' : ((highlighted || v.isOverdue) ? 'due' : 'future');
    final (Color mbg, Color mfg, String icon) = switch (state) {
      'done' => (AppColors.growth, Colors.white, 'check'),
      'due' => (AppColors.coral, Colors.white, 'syringe'),
      _ => (AppColors.line, AppColors.muted, 'clock'),
    };
    final dateText = v.done && v.doneDate != null
        ? trp('Yapıldı · {d}', {'d': fmtDayMonYear(v.doneDate!)})
        : (v.isOverdue
            ? trp('Gecikti · {d}', {'d': fmtDayMonYear(v.dueDate)})
            : trp('Planlanan · {d}', {'d': fmtDayMonYear(v.dueDate)}));

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // stub: marker + dikey çizgi
          Column(
            children: [
              GestureDetector(
                onTap: () => _toggle(context, ref, !v.done),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: mbg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: AdenaIcon(icon, size: 16, color: mfg, sw: 2.2),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 3)),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // body
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.name,
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: v.done ? AppColors.muted : null)),
                        const SizedBox(height: 2),
                        Text(dateText,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: state == 'due'
                                    ? AppColors.coralDd
                                    : AppColors.muted)),
                      ],
                    ),
                  ),
                  if (state == 'due')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.feedBg, borderRadius: BorderRadius.circular(999)),
                      child: Text(v.isOverdue ? tr('Gecikti') : tr('Yaklaşan'),
                          style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.coralDd)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool done) async {
    // Sağlık kayıtları yalnız owner/parent — bakıcı salt-okunur.
    if (!(ref.read(activeBabyProvider)?.canFullWrite ?? true)) {
      showAdToast(context, tr('Bu işlem için ebeveyn/sahip olmalısın'));
      return;
    }
    try {
      await ref
          .read(healthRepositoryProvider)
          .setVaccineDone(babyId, vaccine.key, done: done);
      ref.invalidate(vaccinesProvider(babyId));
    } catch (e) {
      if (context.mounted) showAdError(context, apiErrorText(e));
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.vaccines_outlined, size: 56, color: AppColors.peach),
            const SizedBox(height: 12),
            Text(tr('Aşı takvimi yok'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              tr('Takvim, bebeğin doğum tarihinden otomatik oluşturulur. '
              'Doğum tarihi girilince burada görünür.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
