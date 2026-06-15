import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/units.dart';
import '../../core/who_growth.dart';
import '../../models/baby.dart';
import '../../models/record.dart';

/// Grafik UI'ıyla AYNI hesabı kullanarak doktor PDF raporu için JSON payload üretir.
/// WHO persentil/eğri motoru istemcide tek yer; backend bu veriyi PDF'e render eder.
Map<String, dynamic> buildGrowthReportPayload(
    Baby baby, List<Record> records, Units units) {
  final birth = baby.birthDate;
  final gender = baby.gender;
  final canPct = birth != null && gender != BabyGender.unknown;

  final defs = [
    (key: 'wt', field: 'weight', name: tr('Kilo'), isW: true),
    (key: 'len', field: 'height', name: tr('Boy'), isW: false),
    (key: 'hc', field: 'head_circ', name: tr('Baş çevresi'), isW: false),
  ];

  final measuresOut = <Map<String, dynamic>>[];
  for (final m in defs) {
    final isW = m.isW;
    double toPref(num c) =>
        isW ? units.weightFromCanonical(c) : units.lengthFromCanonical(c);
    final dec = isW ? (units.weight == 'lb' ? 1 : 2) : 1;
    String fmt(num c) => toPref(c).toStringAsFixed(dec);
    final unit = isW ? units.weightLabel : units.lengthLabel;

    final growth = records
        .where((r) => r.type == RecordType.growth && r.data[m.field] is num)
        .toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
    if (growth.isEmpty) continue;

    // Grafik noktaları (tercih biriminde, yaş ay).
    final points = <List<double>>[];
    if (birth != null) {
      for (final r in growth) {
        final age = r.ts.difference(birth).inHours / 24 / 30.4375;
        if (age < 0 || age > WhoGrowth.maxMonth) continue;
        points.add([
          double.parse(age.toStringAsFixed(2)),
          double.parse(toPref(r.data[m.field] as num).toStringAsFixed(dec)),
        ]);
      }
    }
    final axisMax = points.isEmpty
        ? 6
        : points.last[0].ceil().clamp(6, WhoGrowth.maxMonth).toInt();

    // WHO eğrileri (kanonik) → tercih birimi.
    Map<String, List<double>>? curvesOut;
    if (canPct) {
      final curves = WhoGrowth.curves(m.key, gender, axisMax);
      if (curves != null) {
        curvesOut = {};
        for (final p in [3, 15, 50, 85, 97]) {
          final arr = curves[p];
          if (arr != null) {
            curvesOut['$p'] = [
              for (final v in arr) double.parse(toPref(v).toStringAsFixed(dec))
            ];
          }
        }
      }
    }

    final latestCanon = (growth.last.data[m.field] as num).toDouble();
    final latestAge =
        birth != null ? growth.last.ts.difference(birth).inHours / 24 / 30.4375 : null;
    final pct = (canPct && latestAge != null)
        ? WhoGrowth.percentile(m.key, gender, latestAge, latestCanon)
        : null;

    // Bu ayki değişim (~son 25+ gün önceki ölçüme göre).
    String? delta;
    if (growth.length >= 2) {
      final lastTs = growth.last.ts;
      Record? prev;
      for (final r in growth.reversed.skip(1)) {
        prev = r;
        if (lastTs.difference(r.ts).inDays >= 25) break;
      }
      if (prev != null) {
        final d = toPref(growth.last.data[m.field] as num) -
            toPref(prev.data[m.field] as num);
        delta = (d >= 0 ? '+' : '') + d.toStringAsFixed(dec);
      }
    }

    final histRecs =
        growth.length > 12 ? growth.sublist(growth.length - 12) : growth;
    final history = [
      for (final r in histRecs)
        [fmtDayMon(r.ts), fmt(r.data[m.field] as num)]
    ];

    measuresOut.add({
      'name': m.name,
      'unit': unit,
      'latest': fmt(latestCanon),
      'percentile': pct == null
          ? null
          : (pct >= 99.5 ? '>99' : (pct < 0.5 ? '<1' : pct.round().toString())),
      'delta': delta,
      'axis_max': axisMax,
      'curves': curvesOut, // null → backend "eğri yok" sayar
      'points': points,
      'history': history,
    });
  }

  // 7 günlük beslenme/uyku/bez trendi (charts_view ile aynı).
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  final feedByDay = {for (final d in days) d: 0.0};
  final sleepByDay = {for (final d in days) d: 0.0};
  final weekStart = days.first;
  var diaper7 = 0;
  for (final r in records) {
    final day = DateTime(r.ts.year, r.ts.month, r.ts.day);
    if (r.type == RecordType.diaper && !day.isBefore(weekStart)) diaper7++;
    if (!feedByDay.containsKey(day)) continue;
    if (r.type == RecordType.feed) {
      feedByDay[day] = feedByDay[day]! + 1;
    } else if (r.type == RecordType.sleep && r.data['duration'] is num) {
      sleepByDay[day] = sleepByDay[day]! + (r.data['duration'] as num) / 60.0;
    }
  }
  final feedTotal = feedByDay.values.fold<double>(0, (a, b) => a + b);
  final sleepTotal = sleepByDay.values.fold<double>(0, (a, b) => a + b);

  return {
    'baby': {
      'name': baby.name,
      'gender': gender == BabyGender.male
          ? 'male'
          : gender == BabyGender.female
              ? 'female'
              : 'unknown',
      'age_label': _ageLabel(birth, now),
    },
    'generated_at': fmtDayMonthYear(now),
    'measures': measuresOut,
    'trends': {
      'feed_avg': feedTotal > 0 ? (feedTotal / 7).round().toString() : '0',
      'sleep_avg': (sleepTotal / 7).toStringAsFixed(1),
      'diaper_7d': diaper7.toString(),
      'days': [
        for (final d in days)
          [
            fmtWeekdayShort(d),
            feedByDay[d]!.toInt(),
            double.parse(sleepByDay[d]!.toStringAsFixed(1)),
          ]
      ],
    },
  };
}

String _ageLabel(DateTime? birth, DateTime now) {
  if (birth == null) return '';
  final days = now.difference(birth).inDays;
  if (days < 0) return '';
  if (days < 60) return trp('{n} hafta', {'n': (days / 7).floor()});
  return trp('{n} ay', {'n': (days / 30.4375).floor()});
}

/// Payload'ı backend'e gönderir, dönen PDF'i geçici dosyaya yazar ve paylaşım
/// sayfasını açar. Premium değilse backend 403 → çağıran hata gösterir.
Future<void> shareGrowthReport(
    WidgetRef ref, String babyId, Map<String, dynamic> payload) async {
  final dio = ref.read(apiClientProvider).dio;
  final resp = await dio.post(
    '/babies/$babyId/report',
    data: payload,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = resp.data as List<int>;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/adena-saglik-raporu.pdf');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/pdf')],
    subject: tr('Adena Baby · Sağlık Raporu'),
  ));
}
