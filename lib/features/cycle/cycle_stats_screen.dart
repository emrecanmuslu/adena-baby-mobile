import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import 'cycle_engine.dart';
import 'cycle_kit.dart';
import 'cycle_shell.dart';
import 'cycle_widgets.dart';

/// Analiz — "Bloom" (v3): 3 stat + düzenlilik + döngü uzunluğu çizgi grafiği +
/// adet süresi barları + geçmiş döngüler. Kabuk içinde (logolu header).
class CycleStatsScreen extends ConsumerWidget {
  const CycleStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(cycleSettingsProvider);
    final entriesAsync = ref.watch(cycleEntriesProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          CycleHeader(onSettings: () => context.push('/cycle/settings')),
          Expanded(
            child: settingsAsync.when(
              loading: () =>
                  Center(child: CircularProgressIndicator(color: AppColors.rose)),
              error: (e, _) => Center(child: Text(apiErrorText(e))),
              data: (settings) => entriesAsync.when(
                loading: () =>
                    Center(child: CircularProgressIndicator(color: AppColors.rose)),
                error: (e, _) => Center(child: Text(apiErrorText(e))),
                data: (entries) {
                  final status = computeStatus(settings, entries);
                  if (status.mode != CycleMode.active) {
                    return _waitingState(status.mode);
                  }
                  return _StatsView(status: status);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _waitingState(CycleMode mode) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🌿', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 14),
            Text(
                mode == CycleMode.lochia
                    ? tr('Henüz lohusalık dönemindesin. İlk adetin döndüğünde döngü '
                        'analizi burada oluşur.')
                    : tr('Döngün henüz oturmadı. İlk adetini kaydettiğinde analiz '
                        'burada görünecek.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.muted)),
          ]),
        ),
      );
}

class _StatsView extends StatelessWidget {
  final CycleStatus status;
  const _StatsView({required this.status});

  @override
  Widget build(BuildContext context) {
    final completed = status.spans.where((s) => s.length != null).toList();
    final last6 = completed.length > 6
        ? completed.sublist(completed.length - 6)
        : completed;
    final hist = completed.reversed.toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(18, 2, 18, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(tr('Analiz'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          cycStat(context, '${status.avgCycleLength}', tr('g'), tr('Ort. döngü')),
          const SizedBox(width: 10),
          cycStat(context, '${status.avgPeriodDays}', tr('g'), tr('Ort. süre')),
          const SizedBox(width: 10),
          cycStat(context, '${status.cycleNumber}', '', tr('Döngü')),
        ]),

        CycEyebrow(tr('Düzenlilik')),
        _regularityCard(context, last6),

        if (last6.length >= 2) ...[
          CycEyebrow(tr('Döngü uzunluğu'), suffix: tr('· son 6')),
          cycCard(context, soft: true, child: SizedBox(
            height: 130,
            child: CustomPaint(
              size: Size.infinite,
              painter: _LinePainter(
                values: [for (final s in last6) s.length!.toDouble()],
                avg: status.avgCycleLength.toDouble(),
                rose: AppColors.rose,
                roseD: AppColors.roseD,
                surface: Theme.of(context).colorScheme.surface,
                muted: AppColors.muted,
              ),
            ),
          )),
          CycEyebrow(tr('Adet süresi')),
          cycCard(context, soft: true, child: _durationBars(last6)),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: cycNote(context,
                icon: Icons.lightbulb_outline_rounded,
                body: tr('Henüz yeterli veri yok. 3+ döngü birikince tahminler '
                    'güvenilirleşir — doğum sonrası bu normaldir.'),
                infoTitle: tr('Düzenlilik'),
                info: CycleInfo.regularity),
          ),

        CycEyebrow(tr('Geçmiş döngüler'), link: null),
        if (hist.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(tr('İlk döngün tamamlandığında burada listelenecek.'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
          )
        else
          for (final s in hist) _spanRow(context, s),
      ],
    );
  }

  Widget _regularityCard(BuildContext context, List<CycleSpan> last6) {
    final reg = [
      for (final s in last6) (s.length! - status.avgCycleLength).abs() <= 3,
    ];
    return cycCard(context, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(reg.where((x) => x).length >= reg.length - 1 && reg.isNotEmpty
              ? tr('Düzenli seyir')
              : tr('Değişken seyir'),
              style: cycTitleStyle(size: 17)),
          cycPill(tr('Postpartum normal')),
        ]),
        const SizedBox(height: 13),
        if (reg.isEmpty)
          Text('—',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.muted))
        else
          Row(children: [
            for (var i = 0; i < reg.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                      color: reg[i] ? AppColors.rose : AppColors.line2,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ]),
        const SizedBox(height: 11),
        Text(tr('Doğum sonrası ilk döngülerde dalgalanma beklenir. 3+ döngü '
            'biriktikçe tahminler güçlenir.'),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.5,
                color: AppColors.ink2)),
      ],
    ));
  }

  Widget _durationBars(List<CycleSpan> last6) {
    final vals = [for (final s in last6) s.periodDays];
    final maxV = math.max(7, vals.fold(0, math.max));
    return SizedBox(
      height: 84,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < vals.length; i++) ...[
          if (i > 0) const SizedBox(width: 11),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(
                height: 64 * vals[i] / maxV,
                decoration: BoxDecoration(
                  color: i == vals.length - 1 ? AppColors.rose : AppColors.roseBg,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8), bottom: Radius.circular(3)),
                ),
              ),
              const SizedBox(height: 6),
              Text('${vals[i]}${tr('g')}',
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: i == vals.length - 1 ? AppColors.roseD : AppColors.muted)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _spanRow(BuildContext context, CycleSpan s) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: cycCard(context,
            soft: true,
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            child: Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.roseBg, borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.calendar_today_rounded,
                      size: 18, color: AppColors.roseD)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${fmtDayMonth(s.start)} – ${fmtDayMonth(s.end!)}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 1),
                  Text(
                      '${trp('{n} gün', {'n': s.length})} · '
                      '${trp('{n} gün', {'n': s.periodDays})} · '
                      '${s.dominantFlow == null ? '—' : flowLabel(s.dominantFlow!)} ${tr('akış')}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ]),
              ),
            ])),
      );
}

/// Döngü uzunluğu çizgi grafiği (alan dolgulu + ort. kesik çizgi).
class _LinePainter extends CustomPainter {
  final List<double> values;
  final double avg;
  final Color rose, roseD, surface, muted;
  _LinePainter({
    required this.values,
    required this.avg,
    required this.rose,
    required this.roseD,
    required this.surface,
    required this.muted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const padX = 18.0, top = 12.0, bot = 24.0;
    final lo = (values.reduce(math.min)).floorToDouble() - 2;
    final hi = (values.reduce(math.max)).ceilToDouble() + 2;
    final range = (hi - lo) == 0 ? 1 : (hi - lo);
    double x(int i) => padX + (i / (values.length - 1)) * (size.width - padX * 2);
    double y(double v) => top + (1 - (v - lo) / range) * (size.height - top - bot);

    // ort. kesik çizgi
    final avgY = y(avg);
    final dash = Paint()
      ..color = rose.withValues(alpha: 0.5)
      ..strokeWidth = 1.2;
    for (var dx = padX; dx < size.width - padX; dx += 8) {
      canvas.drawLine(Offset(dx, avgY), Offset(dx + 4, avgY), dash);
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(x(i), y(values[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    // alan dolgu
    final area = Path.from(path)
      ..lineTo(x(values.length - 1), size.height - bot)
      ..lineTo(x(0), size.height - bot)
      ..close();
    canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [rose.withValues(alpha: 0.20), rose.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    // çizgi
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = rose);
    // noktalar
    for (var i = 0; i < values.length; i++) {
      final p = Offset(x(i), y(values[i]));
      final last = i == values.length - 1;
      canvas.drawCircle(p, last ? 4.5 : 3, Paint()..color = last ? roseD : surface);
      canvas.drawCircle(
          p,
          last ? 4.5 : 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = rose);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values || old.avg != avg;
}
