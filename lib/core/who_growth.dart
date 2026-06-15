import 'dart:math' as math;

import '../data/who_lms.dart';
import '../models/baby.dart';

/// WHO büyüme standardı (0–60 ay) — LMS yöntemiyle persentil eğrisi ve
/// bir ölçümün persentilini hesaplar. Ölçü anahtarları: wt (kg) · len/hc (cm).
/// len: 0–24 ay uzunluk (yatarak), 24–60 ay boy (ayakta).
class WhoGrowth {
  WhoGrowth._();

  static const int maxMonth = 60;

  /// Çizilen persentil çizgileri ve karşılık gelen z-skorları.
  static const List<int> pcts = [3, 15, 50, 85, 97];
  static const Map<int, double> zForPct = {
    3: -1.880794,
    15: -1.036433,
    50: 0.0,
    85: 1.036433,
    97: 1.880794,
  };

  static String? sexKey(BabyGender g) => switch (g) {
        BabyGender.male => 'M',
        BabyGender.female => 'F',
        BabyGender.unknown => null,
      };

  static WhoLms? table(String measure, BabyGender g) {
    final s = sexKey(g);
    if (s == null) return null;
    return whoLms['${measure}_$s'];
  }

  /// LMS'den z-skoru için ölçüm değeri. L≈0 ise log-normal.
  static double valueAtZ(double l, double m, double s, double z) {
    if (l.abs() < 1e-7) return m * math.exp(s * z);
    return m * math.pow(1 + l * s * z, 1 / l).toDouble();
  }

  /// Ölçüm değerinden z-skoru.
  static double zForValue(double l, double m, double s, double x) {
    if (l.abs() < 1e-7) return math.log(x / m) / s;
    return (math.pow(x / m, l).toDouble() - 1) / (l * s);
  }

  /// Kesirli ay için (L,M,S) — komşu aylar arası lineer interpolasyon.
  static (double l, double m, double s) lmsAtAge(WhoLms t, double ageMonths) {
    final a = ageMonths.clamp(0.0, maxMonth.toDouble());
    if (a <= 0) return (t.l[0], t.m[0], t.s[0]);
    if (a >= maxMonth) return (t.l[maxMonth], t.m[maxMonth], t.s[maxMonth]);
    final i = a.floor();
    final f = a - i;
    double lerp(List<double> v) => v[i] + (v[i + 1] - v[i]) * f;
    return (lerp(t.l), lerp(t.m), lerp(t.s));
  }

  /// Standart normal CDF (Abramowitz–Stegun 26.2.17 yaklaşımı, ~7 ondalık).
  static double cdf(double z) {
    final az = z.abs();
    final t = 1 / (1 + 0.2316419 * az);
    final d = 0.3989422804014327 * math.exp(-az * az / 2);
    final upper = d *
        t *
        (0.319381530 +
            t *
                (-0.356563782 +
                    t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))));
    final p = 1 - upper; // P(Z <= az)
    return z >= 0 ? p : 1 - p;
  }

  /// Bir ölçümün persentili (0..100). Veri yoksa null.
  static double? percentile(
      String measure, BabyGender g, double ageMonths, double value) {
    final t = table(measure, g);
    if (t == null) return null;
    final (l, m, s) = lmsAtAge(t, ageMonths);
    return (cdf(zForValue(l, m, s, value)) * 100).clamp(0.0, 100.0);
  }

  /// 0..axisMax ayları için her persentil çizgisinin değer dizisi.
  /// Dönen harita: {3: [...], 15: [...], 50: [...], 85: [...], 97: [...]}.
  static Map<int, List<double>>? curves(
      String measure, BabyGender g, int axisMax) {
    final t = table(measure, g);
    if (t == null) return null;
    final out = <int, List<double>>{for (final p in pcts) p: <double>[]};
    for (var month = 0; month <= axisMax; month++) {
      for (final p in pcts) {
        out[p]!.add(valueAtZ(t.l[month], t.m[month], t.s[month], zForPct[p]!));
      }
    }
    return out;
  }
}
