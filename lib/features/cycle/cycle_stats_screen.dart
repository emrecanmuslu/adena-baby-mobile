import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import 'cycle_engine.dart';
import 'cycle_widgets.dart';

/// Ekran 6 — Döngü istatistikleri & geçmiş. Doğum sonrası veri seyrek olduğu
/// için trend minimal; boş durum cesaret verici.
class CycleStatsScreen extends ConsumerWidget {
  const CycleStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(cycleSettingsProvider);
    final entriesAsync = ref.watch(cycleEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Döngü İstatistikleri')),
      ),
      body: settingsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.coral)),
        error: (e, _) => Center(child: Text(apiErrorText(e))),
        data: (settings) => entriesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: AppColors.coral)),
          error: (e, _) => Center(child: Text(apiErrorText(e))),
          data: (entries) {
            final status = computeStatus(settings, entries);
            if (status.mode != CycleMode.active) {
              return _waitingState(status.mode);
            }
            return _stats(context, status);
          },
        ),
      ),
    );
  }

  Widget _waitingState(CycleMode mode) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🌿', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 14),
              Text(
                  mode == CycleMode.lochia
                      ? tr('Henüz lohusalık dönemindesin. İlk adetin döndüğünde '
                          'döngü istatistikleri burada oluşur.')
                      : tr('Döngün henüz oturmadı. İlk adetini kaydettiğinde '
                          'istatistikler burada görünecek.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                      color: AppColors.muted)),
            ],
          ),
        ),
      );

  Widget _stats(BuildContext context, CycleStatus status) {
    final completed = status.spans.where((s) => s.length != null).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        Row(
          children: [
            Expanded(
                child: _statCard(context, '${status.avgCycleLength}', tr('gün'),
                    tr('Ort. Döngü'))),
            const SizedBox(width: 10),
            Expanded(
                child: _statCard(
                    context, '${status.avgPeriodDays}', tr('gün'), tr('Ort. Süre'))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _regularityCard(context, completed, status)),
            const SizedBox(width: 10),
            Expanded(
                child: _statCard(
                    context, '${status.cycleNumber}', '', tr('Toplam Döngü'))),
          ],
        ),
        const SizedBox(height: 12),
        if (status.lowConfidence)
          Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
            decoration: BoxDecoration(
                color: AppColors.roseBg, borderRadius: BorderRadius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      tr('Henüz yeterli veri yok. 3+ döngü birikince tahminler '
                          'güvenilirleşir — doğum sonrası bu normaldir.'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                          color: AppColors.roseD)),
                ),
              ],
            ),
          ),
        if (completed.length >= 2) ...[
          const SizedBox(height: 12),
          _trendCard(context, completed, status.lowConfidence),
        ],
        adSec(tr('Geçmiş Döngüler'), info: CycleInfo.regularity),
        if (completed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(tr('İlk döngün tamamlandığında burada listelenecek.'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
          )
        else
          for (final s in completed.reversed) _spanRow(s),
      ],
    );
  }

  Widget _statCard(BuildContext context, String n, String unit, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.softShadow),
        child: Column(
          children: [
            Text.rich(TextSpan(
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              children: [
                TextSpan(text: n),
                if (unit.isNotEmpty)
                  TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.muted)),
              ],
            )),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
          ],
        ),
      );

  Widget _regularityCard(
      BuildContext context, List<CycleSpan> completed, CycleStatus status) {
    // Her tamamlanmış döngü ort.'a ±3 gün içinde mi → düzenli noktası.
    final dots = [
      for (final s in completed.take(6))
        (s.length! - status.avgCycleLength).abs() <= 3,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.softShadow),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final ok in dots)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: ok ? AppColors.rose : AppColors.line2,
                      borderRadius: BorderRadius.circular(3)),
                ),
              if (dots.isEmpty)
                Text('—',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(tr('Düzenlilik'),
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(tr('Değişken — doğum sonrası normal'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.roseD)),
        ],
      ),
    );
  }

  Widget _trendCard(
      BuildContext context, List<CycleSpan> completed, bool lowConf) {
    final lens = completed.map((s) => s.length!).toList();
    final maxLen = lens.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('Döngü uzunluğu trendi'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
              if (lowConf) const EstBadge(),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < lens.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${lens[i]}g',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: i == lens.length - 1
                                      ? AppColors.roseD
                                      : AppColors.muted)),
                          const SizedBox(height: 4),
                          Container(
                            height: 60 * lens[i] / maxLen,
                            decoration: BoxDecoration(
                              color: i == lens.length - 1
                                  ? AppColors.rose
                                  : AppColors.roseBg,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8), bottom: Radius.circular(3)),
                              border: i == lens.length - 1
                                  ? null
                                  : Border.all(color: AppColors.line, width: 1.5),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(trp('Döngü {n}', {'n': i + 1}),
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _spanRow(CycleSpan s) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: AppColors.roseBg, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            AdIconChip('calendar', color: AppColors.roseD, bg: Colors.white, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${fmtDayMonth(s.start)} – ${fmtDayMonth(s.end!)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                  Text(
                      '${trp('{n} gün', {'n': s.length})} · '
                      '${s.dominantFlow == null ? '—' : flowLabel(s.dominantFlow!)} ${tr('akış')}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );
}
