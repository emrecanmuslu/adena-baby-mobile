import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/who_growth.dart';
import '../../models/baby.dart';
import '../../models/record.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';
import '../records/record_controller.dart';

/// Tek ölçü tanımı (kilo/boy/baş çevresi) — alan adı + birim türü + renk.
typedef _Measure = ({
  String key, // who_growth anahtarı: wt|len|hc
  String field, // record.data alanı: weight|height|head_circ
  String seg, // segment etiketi
  String name, // tam ad (başlık/açıklamada)
  bool isWeight, // birim dönüşümü: ağırlık mı uzunluk mu
  Color color,
});

// Getter (top-level `final` DEĞİL) — `final` tr()'yi ilk erişimde dondurur,
// dil değişince eski çeviride kalır. Getter her okumada taze değerlenir.
List<_Measure> get _measures => [
      (key: 'wt', field: 'weight', seg: tr('Kilo'), name: tr('Kilo'), isWeight: true, color: AppColors.growth),
      (key: 'len', field: 'height', seg: tr('Boy'), name: tr('Boy'), isWeight: false, color: AppColors.pump),
      (key: 'hc', field: 'head_circ', seg: tr('Baş'), name: tr('Baş çevresi'), isWeight: false, color: AppColors.doctor),
    ];

/// Grafikler sekmesi — design ScrCharts: WHO persentil eğrisi (kilo/boy/baş) +
/// beslenme/uyku trendi.
class ChartsView extends ConsumerStatefulWidget {
  final String babyId;
  const ChartsView({super.key, required this.babyId});

  @override
  ConsumerState<ChartsView> createState() => _ChartsViewState();
}

class _ChartsViewState extends ConsumerState<ChartsView> {
  int _sel = 0; // seçili ölçü

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recordsProvider(widget.babyId));
    final units = ref.watch(activeUnitsProvider);
    final baby = ref.watch(activeBabyProvider);

    if (async.isLoading) {
      return const SkeletonRecordList(count: 6, padding: EdgeInsets.all(16));
    }
    final records = async.asData?.value ?? const <Record>[];

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 92 + MediaQuery.of(context).padding.bottom),
      children: [
        _Segmented(
          labels: [for (final m in _measures) m.seg],
          selected: _sel,
          onSelect: (i) => setState(() => _sel = i),
        ),
        const SizedBox(height: 14),
        _PercentileSection(
          measure: _measures[_sel],
          baby: baby,
          records: records,
          units: units,
        ),
        _sec(tr('Beslenme & Uyku trendi')),
        _TrendBars(records: records),
      ],
    );
  }
}

/// Segment kontrol (design .ad-segmented).
class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Segmented(
      {required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF251D2E) : AppColors.cream,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == selected
                        ? Theme.of(context).colorScheme.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: i == selected ? AppColors.softShadow : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: i == selected ? AppColors.coralDark : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Persentil bölümü: stat satırı + eğri kartı + açıklama. Eksik veride yönlendirir.
class _PercentileSection extends StatelessWidget {
  final _Measure measure;
  final Baby? baby;
  final List<Record> records;
  final Units units;
  const _PercentileSection({
    required this.measure,
    required this.baby,
    required this.records,
    required this.units,
  });

  double _toPref(num canonical) => measure.isWeight
      ? units.weightFromCanonical(canonical)
      : units.lengthFromCanonical(canonical);
  int get _dec => measure.isWeight ? (units.weight == 'lb' ? 1 : 2) : 1;
  String get _unitLabel =>
      measure.isWeight ? units.weightLabel : units.lengthLabel;
  String _fmtPref(num canonical) => _toPref(canonical).toStringAsFixed(_dec);

  @override
  Widget build(BuildContext context) {
    final birth = baby?.birthDate;
    final gender = baby?.gender ?? BabyGender.unknown;

    // Seçili ölçünün ölçümleri (eskiden yeniye), yaş (ay) + kanonik değer.
    final growth = records
        .where((r) => r.type == RecordType.growth && r.data[measure.field] is num)
        .toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));

    final canPct = birth != null && gender != BabyGender.unknown;

    // Grafikte işaretlenecek noktalar (0–24 ay).
    final babyPts = <({double age, double v})>[];
    if (birth != null) {
      for (final r in growth) {
        final age = r.ts.difference(birth).inHours / 24 / 30.4375;
        if (age < 0 || age > WhoGrowth.maxMonth) continue;
        babyPts.add((age: age, v: (r.data[measure.field] as num).toDouble()));
      }
    }
    final int axisMax = babyPts.isEmpty
        ? 6
        : babyPts.last.age.ceil().clamp(6, WhoGrowth.maxMonth).toInt();
    final curves = canPct ? WhoGrowth.curves(measure.key, gender, axisMax) : null;

    // Güncel ölçüm + persentil + bu ayki değişim.
    final hasData = growth.isNotEmpty;
    final latestCanon =
        hasData ? (growth.last.data[measure.field] as num).toDouble() : null;
    double? latestAge;
    if (birth != null && hasData) {
      latestAge = growth.last.ts.difference(birth).inHours / 24 / 30.4375;
    }
    final pct = (canPct && latestCanon != null && latestAge != null)
        ? WhoGrowth.percentile(measure.key, gender, latestAge, latestCanon)
        : null;
    final deltaStr = _delta(growth);

    final children = <Widget>[
      // Stat satırı
      Row(
        children: [
          _Stat(
              n: latestCanon != null ? _fmtPref(latestCanon) : '—',
              small: latestCanon != null ? ' $_unitLabel' : null,
              label: tr('Güncel')),
          const SizedBox(width: 10),
          _Stat(
              n: pct != null ? _pctText(pct) : '—',
              small: pct != null ? '.p' : null,
              label: tr('Persentil')),
          const SizedBox(width: 10),
          _Stat(
              n: deltaStr ?? '—',
              small: deltaStr != null ? ' $_unitLabel' : null,
              label: tr('Bu ay')),
        ],
      ),
      const SizedBox(height: 12),
    ];

    if (curves == null) {
      children.add(_Guidance(
        message: birth == null
            ? tr('Persentil eğrisi için doğum tarihi gerekli.\nAyarlar → Bebek bilgileri\'nden ekle.')
            : tr('Persentil için bebeğin cinsiyetini seç.\nAyarlar → Bebek bilgileri.'),
      ));
    } else {
      children.add(_ChartCard(
        measure: measure,
        axisMax: axisMax,
        curves: curves,
        babyPts: babyPts,
        fmtPref: (v) => _toPref(v).toStringAsFixed(_dec),
        babyName: baby?.name ?? tr('Bebek'),
        pct: pct,
        hasData: hasData,
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  /// Bu ayki değişim (~son 1 ay) — tercih biriminde işaretli metin.
  String? _delta(List<Record> growth) {
    if (growth.length < 2) return null;
    final lastTs = growth.last.ts;
    Record? prev;
    for (final r in growth.reversed.skip(1)) {
      prev = r;
      if (lastTs.difference(r.ts).inDays >= 25) break;
    }
    if (prev == null) return null;
    final d = _toPref(growth.last.data[measure.field] as num) -
        _toPref(prev.data[measure.field] as num);
    return (d >= 0 ? '+' : '') + d.toStringAsFixed(_dec);
  }

  String _pctText(double p) =>
      p >= 99.5 ? '>99' : (p < 0.5 ? '<1' : p.round().toString());
}

class _Stat extends StatelessWidget {
  final String n;
  final String? small;
  final String label;
  const _Stat({required this.n, required this.label, this.small});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.softShadow,
        ),
        child: Column(
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                children: [
                  TextSpan(text: n),
                  if (small != null)
                    TextSpan(
                        text: small,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted,
                    letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}

/// Persentil eğri kartı (design .ad-chartcard + PercentileChart).
class _ChartCard extends StatelessWidget {
  final _Measure measure;
  final int axisMax;
  final Map<int, List<double>> curves;
  final List<({double age, double v})> babyPts;
  final String Function(double) fmtPref;
  final String babyName;
  final double? pct;
  final bool hasData;

  const _ChartCard({
    required this.measure,
    required this.axisMax,
    required this.curves,
    required this.babyPts,
    required this.fmtPref,
    required this.babyName,
    required this.pct,
    required this.hasData,
  });

  @override
  Widget build(BuildContext context) {
    final healthy = pct != null && pct! >= 3 && pct! <= 97;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(trp('{name} · WHO eğrisi', {'name': measure.name}),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              if (pct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: healthy ? AppColors.growthBg : AppColors.feverBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(healthy ? tr('Sağlıklı seyir') : tr('Hekimine danış'),
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: healthy
                              ? const Color(0xFF349970)
                              : AppColors.coralDd)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 300 / 188,
            child: CustomPaint(
              painter: _PctPainter(
                axisMax: axisMax,
                curves: curves,
                babyPts: babyPts,
                fmt: fmtPref,
                line: AppColors.line,
                line2: AppColors.line2,
                peach: AppColors.peach,
                coral: AppColors.coral,
                coralD: AppColors.coralDark,
                surface: Theme.of(context).colorScheme.surface,
                muted: AppColors.muted,
                band: AppColors.feedBg,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _legend(AppColors.coral,
                  '$babyName${pct != null ? ' · ${pct!.round()}p' : ''}'),
              _legend(AppColors.peach, tr('Medyan (50)')),
              _legend(AppColors.feedBg, tr('3–97 aralığı'), block: true),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.feedBg,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                trp('{name} {pct}. persentilde — {note}', {
                  'name': babyName,
                  'pct': pct!.round(),
                  'note': healthy
                      ? tr('yaşına göre sağlıklı seyir.')
                      : tr('değerlendirme için hekimine danış.'),
                }),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.coralDd),
              ),
            ),
          ] else if (!hasData) ...[
            const SizedBox(height: 10),
            Text(tr('Kilo/boy/baş çevresi ölçümü ekleyince eğri üzerinde işaretlenir.'),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }

  Widget _legend(Color c, String label, {bool block = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: block ? 14 : 14,
          height: block ? 9 : 3,
          decoration: BoxDecoration(
              color: c, borderRadius: BorderRadius.circular(block ? 2 : 2)),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
      ],
    );
  }
}

class _PctPainter extends CustomPainter {
  final int axisMax;
  final Map<int, List<double>> curves;
  final List<({double age, double v})> babyPts;
  final String Function(double) fmt;
  final Color line, line2, peach, coral, coralD, surface, muted, band;

  _PctPainter({
    required this.axisMax,
    required this.curves,
    required this.babyPts,
    required this.fmt,
    required this.line,
    required this.line2,
    required this.peach,
    required this.coral,
    required this.coralD,
    required this.surface,
    required this.muted,
    required this.band,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 34.0, padR = 14.0, padT = 10.0, padB = 22.0;
    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;

    final p3 = curves[3]!, p97 = curves[97]!;
    var yMin = p3.reduce(math.min);
    var yMax = p97.reduce(math.max);
    for (final b in babyPts) {
      if (b.v < yMin) yMin = b.v;
      if (b.v > yMax) yMax = b.v;
    }
    final padY = (yMax - yMin) * 0.08;
    yMin -= padY;
    yMax += padY;

    double xAt(double month) => padL + plotW * (month / axisMax);
    double yAt(double v) => padT + plotH * (1 - (v - yMin) / (yMax - yMin));

    void label(String s, Offset pos,
        {required TextAlign align, double fs = 9}) {
      final tp = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(color: muted, fontSize: fs, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      var dx = pos.dx;
      if (align == TextAlign.right) dx -= tp.width;
      if (align == TextAlign.center) dx -= tp.width / 2;
      tp.paint(canvas, Offset(dx, pos.dy - tp.height / 2));
    }

    // y gridlines + etiket (tercih biriminde)
    const ticks = 4;
    final gridP = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var i = 0; i <= ticks; i++) {
      final v = yMin + (yMax - yMin) * i / ticks;
      final y = yAt(v);
      canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), gridP);
      label(fmt(v), Offset(padL - 5, y), align: TextAlign.right);
    }

    Path poly(List<double> v) {
      final p = Path();
      for (var i = 0; i < v.length; i++) {
        final o = Offset(xAt(i.toDouble()), yAt(v[i]));
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      return p;
    }

    Path bandPath(List<double> hi, List<double> lo) {
      final p = Path();
      for (var i = 0; i < hi.length; i++) {
        final o = Offset(xAt(i.toDouble()), yAt(hi[i]));
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      for (var i = lo.length - 1; i >= 0; i--) {
        final o = Offset(xAt(i.toDouble()), yAt(lo[i]));
        p.lineTo(o.dx, o.dy);
      }
      return p..close();
    }

    // bantlar (3–97 ve 15–85)
    canvas.drawPath(bandPath(p97, p3),
        Paint()..color = band.withValues(alpha: 0.55));
    canvas.drawPath(bandPath(curves[85]!, curves[15]!),
        Paint()..color = band.withValues(alpha: 0.85));

    // ince persentil çizgileri
    final thin = Paint()
      ..color = line2
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    for (final p in [97, 85, 15, 3]) {
      canvas.drawPath(poly(curves[p]!), thin);
    }

    // medyan (kesikli)
    final medP = Paint()
      ..color = peach
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final metric in poly(curves[50]!).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final n = math.min(d + 4.0, metric.length);
        canvas.drawPath(metric.extractPath(d, n), medP);
        d += 7.0;
      }
    }

    // bebek eğrisi + noktalar
    if (babyPts.isNotEmpty) {
      final lp = Path();
      for (var i = 0; i < babyPts.length; i++) {
        final o = Offset(
            xAt(babyPts[i].age.clamp(0.0, axisMax.toDouble()).toDouble()),
            yAt(babyPts[i].v));
        i == 0 ? lp.moveTo(o.dx, o.dy) : lp.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        lp,
        Paint()
          ..color = coral
          ..strokeWidth = 3.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (var i = 0; i < babyPts.length; i++) {
        final last = i == babyPts.length - 1;
        final o = Offset(
            xAt(babyPts[i].age.clamp(0.0, axisMax.toDouble()).toDouble()),
            yAt(babyPts[i].v));
        canvas.drawCircle(o, last ? 4.5 : 2.6, Paint()..color = last ? coralD : coral);
        canvas.drawCircle(o, last ? 2.0 : 1.0, Paint()..color = surface);
      }
    }

    // x etiketleri (ay)
    final every = (axisMax / 6).ceil().clamp(1, axisMax).toInt();
    for (var m = 0; m <= axisMax; m++) {
      if (m % every == 0 || m == axisMax) {
        label(m == axisMax ? trp('{m} ay', {'m': m}) : '$m',
            Offset(xAt(m.toDouble()), size.height - 9),
            align: TextAlign.center);
      }
    }
  }

  @override
  bool shouldRepaint(_PctPainter o) =>
      o.axisMax != axisMax || o.curves != curves || o.babyPts != babyPts;
}

/// Eksik veri yönlendirmesi (doğum tarihi/cinsiyet yok).
class _Guidance extends StatelessWidget {
  final String message;
  const _Guidance({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          Icon(Icons.show_chart, size: 40, color: AppColors.peach),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.muted, fontWeight: FontWeight.w600, height: 1.4)),
        ],
      ),
    );
  }
}

/// Beslenme + uyku 7 gün trend kartları (design alt bölümü).
class _TrendBars extends StatelessWidget {
  final List<Record> records;
  const _TrendBars({required this.records});

  @override
  Widget build(BuildContext context) {
    final days = _last7Days();
    final feedByDay = <DateTime, double>{for (final d in days) d: 0};
    final sleepByDay = <DateTime, double>{for (final d in days) d: 0};
    for (final r in records) {
      final day = DateTime(r.ts.year, r.ts.month, r.ts.day);
      if (!feedByDay.containsKey(day)) continue;
      if (r.type == RecordType.feed) {
        feedByDay[day] = feedByDay[day]! + 1;
      } else if (r.type == RecordType.sleep && r.data['duration'] is num) {
        sleepByDay[day] = sleepByDay[day]! + (r.data['duration'] as num) / 60.0;
      }
    }
    final feedTotal = feedByDay.values.fold<double>(0, (a, b) => a + b);
    final avgFeed = feedTotal > 0 ? (feedTotal / 7).round() : 0;

    return Column(
      children: [
        _BarCard(
          title: tr('Günlük beslenme (7 gün)'),
          trailing: avgFeed > 0 ? trp('ort. {n}×/gün', {'n': avgFeed}) : null,
          color: AppColors.feed,
          days: days,
          values: days.map((d) => feedByDay[d]!).toList(),
          fmt: (v) => v.toInt().toString(),
        ),
        const SizedBox(height: 12),
        _BarCard(
          title: tr('Günlük uyku (7 gün)'),
          color: AppColors.sleep,
          days: days,
          values: days.map((d) => sleepByDay[d]!).toList(),
          fmt: (v) => v == 0 ? '0' : '${v.toStringAsFixed(1)}s',
        ),
      ],
    );
  }

  List<DateTime> _last7Days() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }
}

class _BarCard extends StatelessWidget {
  final String title;
  final String? trailing;
  final Color color;
  final List<DateTime> days;
  final List<double> values;
  final String Function(double) fmt;

  const _BarCard({
    required this.title,
    required this.color,
    required this.days,
    required this.values,
    required this.fmt,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    final dayFmt = DateFormat('E', 'tr_TR');
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
              if (trailing != null)
                Text(trailing!,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(days.length, (i) {
                final v = values[i];
                final ratio = max > 0 ? v / max : 0.0;
                final isToday = days[i] == todayKey;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(v > 0 ? fmt(v) : '',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.muted)),
                      const SizedBox(height: 4),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 6 + ratio * 64,
                        decoration: BoxDecoration(
                          color: v == 0
                              ? color.withValues(alpha: 0.14)
                              : (isToday ? color : AppColors.peach),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6), bottom: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(dayFmt.format(days[i]),
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.muted)),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bölüm başlığı (design .ad-sec).
Widget _sec(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 18, 3, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: AppColors.muted,
          letterSpacing: 0.7,
        ),
      ),
    );
