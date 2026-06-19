import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/core/who_growth.dart';
import 'package:adena_baby/data/who_lms.dart';
import 'package:adena_baby/models/baby.dart';

/// WHO LMS persentil motoru (lib/core/who_growth.dart) saf-mantık birim
/// testleri. Yalnız hesaplama: widget/ağ/provider yok.
void main() {
  // wt_M ay 0 LMS katsayıları (gömülü tablodan birebir).
  const lWt = 0.3487;
  const mWt = 3.3464;
  const sWt = 0.14602;

  group('valueAtZ — LMS -> ölçüm değeri', () {
    test('z=0 medyanı (M) verir', () {
      expect(WhoGrowth.valueAtZ(lWt, mWt, sWt, 0), closeTo(mWt, 1e-9));
    });

    test('genel L için M*(1+L*S*z)^(1/L) formülü', () {
      final expected = mWt * math.pow(1 + lWt * sWt * 1.0, 1 / lWt);
      expect(WhoGrowth.valueAtZ(lWt, mWt, sWt, 1.0), closeTo(expected, 1e-9));
    });

    test('L=0 (log-normal dal) M*exp(S*z) verir', () {
      expect(WhoGrowth.valueAtZ(0, 10, 0.1, 1), closeTo(10 * math.exp(0.1), 1e-9));
      expect(WhoGrowth.valueAtZ(0, 10, 0.1, 0), closeTo(10, 1e-9));
    });

    test('|L|<1e-7 eşiği log-normal dalı seçer (tam 0 ile aynı)', () {
      final tiny = WhoGrowth.valueAtZ(1e-9, 10, 0.1, 1);
      final zero = WhoGrowth.valueAtZ(0.0, 10, 0.1, 1);
      expect(tiny, closeTo(zero, 1e-9));
    });

    test('L=1 (lineer dal) M*(1+S*z) verir', () {
      // len/hc tablolarında L=1.0; bu durumda dal lineerdir.
      expect(WhoGrowth.valueAtZ(1.0, 50.0, 0.04, 1),
          closeTo(50.0 * (1 + 0.04), 1e-9));
    });

    test('negatif z medyanın altında değer verir', () {
      expect(WhoGrowth.valueAtZ(lWt, mWt, sWt, -1.0), lessThan(mWt));
    });
  });

  group('zForValue — ölçüm değeri -> z-skoru', () {
    test('x=M iken z=0', () {
      expect(WhoGrowth.zForValue(lWt, mWt, sWt, mWt), closeTo(0, 1e-9));
    });

    test('valueAtZ ile tam tersine çevirim (round-trip)', () {
      for (final z in [-2.0, -1.0, -0.5, 0.5, 1.0, 1.880794, 2.5]) {
        final v = WhoGrowth.valueAtZ(lWt, mWt, sWt, z);
        expect(WhoGrowth.zForValue(lWt, mWt, sWt, v), closeTo(z, 1e-6),
            reason: 'z=$z round-trip');
      }
    });

    test('L=0 dal round-trip (log-normal)', () {
      final v = WhoGrowth.valueAtZ(0, 10, 0.1, 1.3);
      expect(WhoGrowth.zForValue(0, 10, 0.1, v), closeTo(1.3, 1e-9));
    });

    test('M üstü değer pozitif, M altı değer negatif z', () {
      expect(WhoGrowth.zForValue(lWt, mWt, sWt, mWt + 1), greaterThan(0));
      expect(WhoGrowth.zForValue(lWt, mWt, sWt, mWt - 1), lessThan(0));
    });
  });

  group('cdf — standart normal kümülatif', () {
    test('cdf(0)=0.5', () {
      expect(WhoGrowth.cdf(0), closeTo(0.5, 1e-7));
    });

    test('simetri: cdf(-z) = 1 - cdf(z)', () {
      for (final z in [0.3, 1.0, 1.96, 2.5]) {
        expect(WhoGrowth.cdf(-z), closeTo(1 - WhoGrowth.cdf(z), 1e-7),
            reason: 'z=$z');
      }
    });

    test('bilinen z-değerleri (~7 ondalık)', () {
      expect(WhoGrowth.cdf(1.0), closeTo(0.8413447, 1e-6));
      expect(WhoGrowth.cdf(1.96), closeTo(0.9750021, 1e-6));
      expect(WhoGrowth.cdf(-1.96), closeTo(0.0249979, 1e-6));
    });

    test('persentil sabitleri (zForPct) doğru yüzdeleri verir', () {
      WhoGrowth.zForPct.forEach((pct, z) {
        expect(WhoGrowth.cdf(z) * 100, closeTo(pct.toDouble(), 1e-3),
            reason: 'pct=$pct');
      });
    });

    test('pcts ve zForPct anahtar kümeleri eşleşir', () {
      expect(WhoGrowth.pcts.toSet(), equals(WhoGrowth.zForPct.keys.toSet()));
    });

    test('monotonik artan', () {
      expect(WhoGrowth.cdf(-1), lessThan(WhoGrowth.cdf(0)));
      expect(WhoGrowth.cdf(0), lessThan(WhoGrowth.cdf(1)));
    });
  });

  group('lmsAtAge — yaşa göre interpolasyon', () {
    final t = whoLms['wt_M']!;

    test('tam ay indeksinde tablo değerini döner', () {
      final (l, m, s) = WhoGrowth.lmsAtAge(t, 0);
      expect(l, t.l[0]);
      expect(m, t.m[0]);
      expect(s, t.s[0]);
    });

    test('komşu aylar arası lineer interpolasyon (0.5)', () {
      final (l, m, s) = WhoGrowth.lmsAtAge(t, 0.5);
      expect(m, closeTo((t.m[0] + t.m[1]) / 2, 1e-9));
      expect(l, closeTo((t.l[0] + t.l[1]) / 2, 1e-9));
      expect(s, closeTo((t.s[0] + t.s[1]) / 2, 1e-9));
    });

    test('kesirli oran (0.25) doğru ağırlıklanır', () {
      final (_, m, _) = WhoGrowth.lmsAtAge(t, 3.25);
      expect(m, closeTo(t.m[3] + (t.m[4] - t.m[3]) * 0.25, 1e-9));
    });

    test('negatif yaş 0 aya kenetlenir', () {
      final (l, m, s) = WhoGrowth.lmsAtAge(t, -5);
      expect(m, t.m[0]);
      expect(l, t.l[0]);
      expect(s, t.s[0]);
    });

    test('maxMonth üstü yaş son aya kenetlenir', () {
      final (l, m, s) = WhoGrowth.lmsAtAge(t, 200);
      expect(m, t.m[WhoGrowth.maxMonth]);
      expect(l, t.l[WhoGrowth.maxMonth]);
      expect(s, t.s[WhoGrowth.maxMonth]);
    });

    test('tam maxMonth sınırı son ayı döner', () {
      final (_, m, _) = WhoGrowth.lmsAtAge(t, WhoGrowth.maxMonth.toDouble());
      expect(m, t.m[WhoGrowth.maxMonth]);
    });
  });

  group('table / sexKey — cinsiyet anahtarı', () {
    test('sexKey eşlemesi', () {
      expect(WhoGrowth.sexKey(BabyGender.male), 'M');
      expect(WhoGrowth.sexKey(BabyGender.female), 'F');
      expect(WhoGrowth.sexKey(BabyGender.unknown), isNull);
    });

    test('table bilinen ölçü+cinsiyet için tablo döner', () {
      expect(WhoGrowth.table('wt', BabyGender.male), isNotNull);
      expect(WhoGrowth.table('len', BabyGender.female), isNotNull);
      expect(WhoGrowth.table('hc', BabyGender.male), isNotNull);
    });

    test('table unknown cinsiyette null', () {
      expect(WhoGrowth.table('wt', BabyGender.unknown), isNull);
    });

    test('table bilinmeyen ölçüde null', () {
      expect(WhoGrowth.table('xyz', BabyGender.male), isNull);
    });
  });

  group('percentile — ölçümün persentili (0..100)', () {
    test('medyan ölçüm ~%50', () {
      final m0 = whoLms['wt_M']!.m[0];
      final p = WhoGrowth.percentile('wt', BabyGender.male, 0, m0);
      expect(p, isNotNull);
      expect(p!, closeTo(50, 0.01));
    });

    test('p97 değerinde ~%97', () {
      final t = whoLms['wt_M']!;
      final v97 = WhoGrowth.valueAtZ(t.l[0], t.m[0], t.s[0], WhoGrowth.zForPct[97]!);
      final p = WhoGrowth.percentile('wt', BabyGender.male, 0, v97);
      expect(p!, closeTo(97, 0.01));
    });

    test('p3 değerinde ~%3', () {
      final t = whoLms['wt_M']!;
      final v3 = WhoGrowth.valueAtZ(t.l[0], t.m[0], t.s[0], WhoGrowth.zForPct[3]!);
      final p = WhoGrowth.percentile('wt', BabyGender.male, 0, v3);
      expect(p!, closeTo(3, 0.01));
    });

    test('unknown cinsiyette null', () {
      expect(
          WhoGrowth.percentile('wt', BabyGender.unknown, 0, 3.5), isNull);
    });

    test('bilinmeyen ölçüde null', () {
      expect(WhoGrowth.percentile('zzz', BabyGender.male, 0, 3.5), isNull);
    });

    test('aşırı büyük ölçüm 100\'e kenetlenir', () {
      final p = WhoGrowth.percentile('wt', BabyGender.male, 0, 1000);
      expect(p!, lessThanOrEqualTo(100.0));
      expect(p, greaterThan(99.0));
    });

    test('aşırı küçük ölçüm 0\'a kenetlenir', () {
      final p = WhoGrowth.percentile('wt', BabyGender.male, 0, 0.1);
      expect(p!, greaterThanOrEqualTo(0.0));
      expect(p, lessThan(1.0));
    });

    test('kesirli yaşta interpolasyonlu LMS kullanır', () {
      // 1.5 ayda medyan, interpole M değeri ~%50 vermeli.
      final t = whoLms['wt_M']!;
      final (l, m, s) = WhoGrowth.lmsAtAge(t, 1.5);
      final p = WhoGrowth.percentile('wt', BabyGender.male, 1.5, m);
      expect(p!, closeTo(50, 0.01));
      // kullanılan M gerçekten interpole (ham aydan farklı).
      expect(m, isNot(closeTo(t.m[1], 1e-9)));
      expect(l, closeTo((t.l[1] + t.l[2]) / 2, 1e-9));
      expect(s, closeTo((t.s[1] + t.s[2]) / 2, 1e-9));
    });
  });

  group('curves — persentil eğri dizileri', () {
    test('tüm persentil çizgilerini içerir', () {
      final c = WhoGrowth.curves('wt', BabyGender.male, 24);
      expect(c, isNotNull);
      expect(c!.keys.toSet(), equals(WhoGrowth.pcts.toSet()));
    });

    test('her dizi axisMax+1 nokta içerir (0..axisMax dahil)', () {
      final c = WhoGrowth.curves('wt', BabyGender.male, 24)!;
      for (final p in WhoGrowth.pcts) {
        expect(c[p]!.length, 25, reason: 'pct=$p');
      }
    });

    test('p50 eğrisi M dizisine eşit (z=0)', () {
      final t = whoLms['wt_M']!;
      final c = WhoGrowth.curves('wt', BabyGender.male, 12)!;
      for (var month = 0; month <= 12; month++) {
        expect(c[50]![month], closeTo(t.m[month], 1e-9), reason: 'ay=$month');
      }
    });

    test('belirli ayda persentiller artan sırada', () {
      final c = WhoGrowth.curves('wt', BabyGender.male, 24)!;
      const month = 12;
      var prev = -1.0;
      for (final p in WhoGrowth.pcts) {
        final v = c[p]![month];
        expect(v, greaterThan(prev), reason: 'pct=$p monoton değil');
        prev = v;
      }
    });

    test('p97 eğrisi valueAtZ ile tutarlı', () {
      final t = whoLms['wt_M']!;
      final c = WhoGrowth.curves('wt', BabyGender.male, 6)!;
      for (var month = 0; month <= 6; month++) {
        final expected = WhoGrowth.valueAtZ(
            t.l[month], t.m[month], t.s[month], WhoGrowth.zForPct[97]!);
        expect(c[97]![month], closeTo(expected, 1e-9), reason: 'ay=$month');
      }
    });

    test('len (L=1) eğrisi de üretilir', () {
      final c = WhoGrowth.curves('len', BabyGender.female, 36);
      expect(c, isNotNull);
      expect(c![50]!.length, 37);
    });

    test('unknown cinsiyette null', () {
      expect(WhoGrowth.curves('wt', BabyGender.unknown, 24), isNull);
    });

    test('bilinmeyen ölçüde null', () {
      expect(WhoGrowth.curves('nope', BabyGender.male, 24), isNull);
    });
  });

  group('applyWhoLms — çalışma-zamanı tablo güncelleme', () {
    // Bu test global `whoLms` durumunu değiştirir; sonunda geri yükler.
    tearDown(() {
      // Gömülü tabloyu geri yükle (boş veriyle apply gömülünün kopyasını koyar).
      applyWhoLms(const []);
    });

    test('geçerli seri tabloyu üzerine yazar', () {
      final zeros = List<double>.filled(61, 0.0);
      final ones = List<double>.filled(61, 1.0);
      final ms = List<double>.filled(61, 5.0);
      applyWhoLms([
        {'key': 'wt_M', 'l': ones, 'm': ms, 's': zeros}
      ]);
      final t = whoLms['wt_M']!;
      expect(t.m[0], 5.0);
      expect(t.l[0], 1.0);
    });

    test('eksik/bozuk girdiler atlanır, gömülü korunur', () {
      final embeddedWtF = whoLms['wt_F']!.m[0];
      applyWhoLms([
        'not a map',
        {'key': null, 'l': [], 'm': [], 's': []},
        {'key': 'wt_M', 'l': null, 'm': [1.0], 's': [1.0]},
      ]);
      // wt_F gömülüden korunmuş olmalı.
      expect(whoLms['wt_F']!.m[0], embeddedWtF);
      // wt_M bozuk (l=null) olduğu için gömülü kalmalı (üzerine yazılmaz):
      // gömülü tam seri 61 elemanlıdır, bozuk girdideki 1 elemanlı değil.
      expect(whoLms['wt_M']!.m.length, greaterThan(1));
    });

    test('num (int) değerleri double\'a çevirir', () {
      applyWhoLms([
        {
          'key': 'wt_M',
          'l': [1, 2, 3],
          'm': [4, 5, 6],
          's': [0, 0, 0],
        }
      ]);
      expect(whoLms['wt_M']!.m[1], 5.0);
      expect(whoLms['wt_M']!.m[1], isA<double>());
    });
  });
}
