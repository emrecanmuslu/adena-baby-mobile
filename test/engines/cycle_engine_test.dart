import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/models/cycle.dart';

/// Saf döngü motoru testleri — tüm tarihler sabit; `today:` enjekte edilir,
/// hiçbir assert DateTime.now()'a dayanmaz.

CycleEntry _period(String id, DateTime date, [FlowLevel flow = FlowLevel.medium]) =>
    CycleEntry(id: id, date: date, flow: flow);

/// Bir başlangıç tarihinden itibaren `days` gün boyunca adet kaydı üretir.
List<CycleEntry> _periodRun(String prefix, DateTime start, int days,
    [FlowLevel flow = FlowLevel.medium]) {
  return [
    for (var i = 0; i < days; i++)
      _period('$prefix-$i', start.add(Duration(days: i)), flow),
  ];
}

void main() {
  group('periodStarts', () {
    test('ardışık adet günlerinden tek başlangıç çıkarır', () {
      final entries = _periodRun('a', DateTime(2025, 1, 1), 5);
      final starts = periodStarts(entries);
      expect(starts, [DateTime(2025, 1, 1)]);
    });

    test('iki ayrı döngüden iki başlangıç çıkarır ve sıralar', () {
      final entries = [
        ..._periodRun('a', DateTime(2025, 1, 29), 4),
        ..._periodRun('b', DateTime(2025, 1, 1), 5), // sırasız eklendi
      ];
      final starts = periodStarts(entries);
      expect(starts, [DateTime(2025, 1, 1), DateTime(2025, 1, 29)]);
    });

    test('spotting/none adet sayılmaz (isPeriod=false)', () {
      final entries = [
        _period('p', DateTime(2025, 1, 1), FlowLevel.light),
        CycleEntry(id: 's', date: DateTime(2025, 1, 2), flow: FlowLevel.spotting),
        CycleEntry(id: 'n', date: DateTime(2025, 1, 3), flow: FlowLevel.none),
      ];
      // spotting ve none düşer → 1 Ocak tek başlangıç, 2/3 boşluk açmaz.
      expect(periodStarts(entries), [DateTime(2025, 1, 1)]);
    });

    test('saat bileşeni göz ardı edilir (yalnız gün)', () {
      final entries = [
        _period('a', DateTime(2025, 1, 1, 23, 59)),
        _period('b', DateTime(2025, 1, 2, 0, 1)),
      ];
      expect(periodStarts(entries), [DateTime(2025, 1, 1)]);
    });

    test('boş giriş listesi → boş başlangıç', () {
      expect(periodStarts(const []), isEmpty);
    });
  });

  group('computeStatus — mod tayini (tahmin yok)', () {
    test('ilk adet dönmediyse ve doğumdan <=42 gün → lochia modu', () {
      final settings = CycleSettings(birthDate: DateTime(2025, 1, 1));
      final status = computeStatus(settings, const [], today: DateTime(2025, 1, 20));
      expect(status.mode, CycleMode.lochia);
      expect(status.lochiaDay, 19);
      expect(status.lochiaStart, DateTime(2025, 1, 1));
      expect(status.nextPeriod, isNull);
    });

    test('ilk adet dönmedi, doğum lochia penceresinin ötesinde → waiting', () {
      final settings = CycleSettings(birthDate: DateTime(2025, 1, 1));
      final status = computeStatus(settings, const [], today: DateTime(2025, 3, 1));
      expect(status.mode, CycleMode.waiting);
      expect(status.nextPeriod, isNull);
      expect(status.ovulationDay, isNull);
    });

    test('doğum tarihi yok, ilk adet yok → waiting', () {
      final status = computeStatus(const CycleSettings(), const [],
          today: DateTime(2025, 3, 1));
      expect(status.mode, CycleMode.waiting);
    });

    test('lochia rengi girilmiş ve doğumdan <=60 gün → lochia (pencere dışı olsa da)', () {
      final settings = CycleSettings(birthDate: DateTime(2025, 1, 1));
      final entries = [
        CycleEntry(
            id: 'l', date: DateTime(2025, 2, 20), lochiaColor: LochiaColor.brown),
      ];
      // sinceBirth = 50 (>42 ama <=60) + lochia rengi var → lochia.
      final status = computeStatus(settings, entries, today: DateTime(2025, 2, 20));
      expect(status.mode, CycleMode.lochia);
    });
  });

  group('computeStatus — aktif döngü tahminleri', () {
    // Düzenli 28 günlük döngüler: başlangıçlar 1 Ocak, 29 Ocak, 26 Şubat 2025.
    final settings = CycleSettings(
      birthDate: DateTime(2024, 12, 1),
      firstPeriodDate: DateTime(2025, 1, 1),
    );
    final entries = [
      ..._periodRun('c1', DateTime(2025, 1, 1), 5),
      ..._periodRun('c2', DateTime(2025, 1, 29), 5),
      ..._periodRun('c3', DateTime(2025, 2, 26), 5),
    ];

    test('mod aktif, döngü sayısı = başlangıç sayısı', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 3, 5));
      expect(s.mode, CycleMode.active);
      expect(s.cycleNumber, 3);
    });

    test('ortalama döngü uzunluğu = 28', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 3, 5));
      expect(s.avgCycleLength, 28);
    });

    test('ortalama adet günü = 5', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 3, 5));
      expect(s.avgPeriodDays, 5);
    });

    test('dayInCycle = son başlangıçtan bu yana gün + 1', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 3, 5));
      // 26 Şubat → 5 Mart = 7 gün + 1 = 8.
      expect(s.dayInCycle, 8);
    });

    test('sonraki adet = son başlangıç + ortalama uzunluk', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 3, 5));
      expect(s.nextPeriod, DateTime(2025, 3, 26));
      expect(s.daysToNextPeriod, 21);
    });

    test('ovülasyon = sonraki adet - 14 gün; fertile pencere = ovülasyon-5..ovülasyon+1', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 3, 5));
      expect(s.ovulationDay, DateTime(2025, 3, 12));
      expect(s.fertileStart, DateTime(2025, 3, 7));
      // My Calendar pariteti: pencere ovülasyondan 1 gün sonra biter.
      expect(s.fertileEnd, DateTime(2025, 3, 13));
    });

    test('3 başlangıç (2 tam döngü) hâlâ düşük güven (lengths.length<3)', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 3, 5));
      expect(s.lowConfidence, isTrue);
    });

    test('4 başlangıç (3 tam döngü) → yüksek güven', () {
      final more = [
        ...entries,
        ..._periodRun('c4', DateTime(2025, 3, 26), 5),
      ];
      final s = computeStatus(settings, more, today: DateTime(2025, 4, 2));
      expect(s.lowConfidence, isFalse);
      expect(s.cycleNumber, 4);
    });
  });

  group('computeStatus — faz hesabı', () {
    final settings = CycleSettings(
      firstPeriodDate: DateTime(2025, 1, 1),
    );
    final entries = [
      ..._periodRun('c1', DateTime(2025, 1, 1), 5),
      ..._periodRun('c2', DateTime(2025, 1, 29), 5),
    ];
    // avgLen 28, avgPeriod 5, son başlangıç 29 Ocak.
    // ovülasyon = (29 Oca + 28) - 14 = 26 Şub - 14 = 12 Şub.

    test('adet günlerinde menstrual faz (dayInCycle <= avgPeriod)', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 1, 31));
      // 29 Oca → 31 Oca = dayInCycle 3 (<=5).
      expect(s.phase, CyclePhase.menstrual);
    });

    test('ovülasyon öncesi follicular', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 2, 5));
      expect(s.phase, CyclePhase.follicular);
    });

    test('ovülasyon gününde ovulation', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 2, 12));
      expect(s.phase, CyclePhase.ovulation);
    });

    test('ovülasyon sonrası luteal', () {
      final s = computeStatus(settings, entries, today: DateTime(2025, 2, 20));
      expect(s.phase, CyclePhase.luteal);
    });
  });

  group('computeStatus — kenar durumları', () {
    test('tek başlangıç → ortalama varsayılan 28/5, düşük güven, 1 döngü', () {
      final settings = CycleSettings(firstPeriodDate: DateTime(2025, 1, 1));
      final entries = _periodRun('c1', DateTime(2025, 1, 1), 4);
      final s = computeStatus(settings, entries, today: DateTime(2025, 1, 10));
      expect(s.cycleNumber, 1);
      expect(s.avgCycleLength, 28);
      expect(s.lowConfidence, isTrue);
      expect(s.nextPeriod, DateTime(2025, 1, 29));
      expect(s.spans.single.length, isNull); // son döngünün uzunluğu yok
    });

    test('düzensiz döngüler → ortalama yuvarlanır', () {
      // başlangıçlar: 1 Oca, 31 Oca (30), 26 Şub (26), 1 Nis (34) → avg 30.
      final settings = CycleSettings(firstPeriodDate: DateTime(2025, 1, 1));
      final entries = [
        ..._periodRun('a', DateTime(2025, 1, 1), 4),
        ..._periodRun('b', DateTime(2025, 1, 31), 4),
        ..._periodRun('c', DateTime(2025, 2, 26), 4),
        ..._periodRun('d', DateTime(2025, 4, 1), 4),
      ];
      final s = computeStatus(settings, entries, today: DateTime(2025, 4, 5));
      // lengths [30,26,34] → ortalama 30.
      expect(s.avgCycleLength, 30);
      // 4 başlangıç ama lengths 3 → yüksek güven.
      expect(s.lowConfidence, isFalse);
    });

    test('artık yıl ay sınırı: 1 Şubat 2024 + 28 = 29 Şubat 2024', () {
      final settings = CycleSettings(firstPeriodDate: DateTime(2024, 2, 1));
      final entries = _periodRun('c1', DateTime(2024, 2, 1), 4);
      final s = computeStatus(settings, entries, today: DateTime(2024, 2, 10));
      expect(s.nextPeriod, DateTime(2024, 2, 29));
    });

    test('ay sınırı: 31 Aralık + 28 = 28 Ocak (yıl artar)', () {
      final settings = CycleSettings(firstPeriodDate: DateTime(2024, 12, 31));
      final entries = _periodRun('c1', DateTime(2024, 12, 31), 4);
      final s = computeStatus(settings, entries, today: DateTime(2025, 1, 5));
      expect(s.nextPeriod, DateTime(2025, 1, 28));
    });

    test('firstPeriodDate başlangıç kümesine her zaman dahildir', () {
      // entries içinde firstPeriodDate ile aynı gün kaydı YOK; yine de sayılmalı.
      final settings = CycleSettings(firstPeriodDate: DateTime(2025, 1, 1));
      final entries = _periodRun('c2', DateTime(2025, 1, 29), 4);
      final s = computeStatus(settings, entries, today: DateTime(2025, 2, 1));
      expect(s.cycleNumber, 2); // 1 Oca (ayar) + 29 Oca (kayıt)
    });

    test('dayInCycle alt sınırı 1 (gelecekteki son başlangıçta bile)', () {
      // today son başlangıçtan önce ise dayInCycle 1'e kıstırılır.
      final settings = CycleSettings(firstPeriodDate: DateTime(2025, 1, 1));
      final entries = [
        ..._periodRun('a', DateTime(2025, 1, 1), 4),
        ..._periodRun('b', DateTime(2025, 2, 1), 4),
      ];
      final s = computeStatus(settings, entries, today: DateTime(2025, 1, 15));
      expect(s.dayInCycle, greaterThanOrEqualTo(1));
    });
  });

  group('CycleSettings.periodReturned', () {
    test('firstPeriodDate null → false', () {
      expect(const CycleSettings().periodReturned, isFalse);
    });
    test('firstPeriodDate dolu → true', () {
      expect(CycleSettings(firstPeriodDate: DateTime(2025, 1, 1)).periodReturned,
          isTrue);
    });
  });

  group('manuel beklenen döngü uzunluğu (#12)', () {
    test('ölçülmüş döngü yokken expectedCycleLength kullanılır', () {
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), expectedCycleLength: 32);
      final status = computeStatus(settings, _periodRun('a', DateTime(2025, 1, 1), 4),
          today: DateTime(2025, 1, 10));
      expect(status.avgCycleLength, 32);
      expect(status.nextPeriod, DateTime(2025, 2, 2)); // 1 Oca + 32 gün
    });

    test('geçersiz (21–40 dışı) expectedCycleLength → 28 varsayılan', () {
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), expectedCycleLength: 90);
      final status = computeStatus(settings, _periodRun('a', DateTime(2025, 1, 1), 4),
          today: DateTime(2025, 1, 10));
      expect(status.avgCycleLength, 28);
    });

    test('ölçülmüş döngü varsa manuel değer YOK sayılır', () {
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), expectedCycleLength: 35);
      final entries = [
        ..._periodRun('a', DateTime(2025, 1, 1), 4),
        ..._periodRun('b', DateTime(2025, 1, 29), 4), // 28 günlük ölçülmüş döngü
      ];
      final status = computeStatus(settings, entries, today: DateTime(2025, 2, 1));
      expect(status.avgCycleLength, 28); // ölçülen kazanır
    });
  });

  group('manuel adet (kanama) süresi', () {
    test('ölçülmüş adet günü yokken periodLength kullanılır', () {
      // firstPeriodDate var ama hiç flow kaydı yok → pdays boş → manuel süre.
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), periodLength: 7);
      final s = computeStatus(settings, const [], today: DateTime(2025, 1, 3));
      expect(s.avgPeriodDays, 7);
      // dayInCycle 3 <= 7 → hâlâ menstrual faz.
      expect(s.phase, CyclePhase.menstrual);
    });

    test('geçersiz (2–10 dışı) periodLength → 5 varsayılan', () {
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), periodLength: 20);
      final s = computeStatus(settings, const [], today: DateTime(2025, 1, 3));
      expect(s.avgPeriodDays, 5);
    });

    test('TAMAMLANMIŞ döngüde ölçülmüş adet günü varsa manuel süre YOK sayılır', () {
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), periodLength: 9);
      // Ortalama yalnız TAMAMLANMIŞ döngülerden alınır (devam eden döngü hariç) →
      // ikinci başlangıç ilk döngüyü kapatır, ölçülen 4 gün kazanır.
      final s = computeStatus(
          settings, [
            ..._periodRun('a', DateTime(2025, 1, 1), 4),
            ..._periodRun('b', DateTime(2025, 1, 29), 4),
          ],
          today: DateTime(2025, 2, 1));
      expect(s.avgPeriodDays, 4); // ölçülen (4 gün) kazanır
    });
  });

  group('manuel luteal faz uzunluğu', () {
    test('lutealPhaseLength ovülasyon + fertil pencereyi kaydırır', () {
      // 28 günlük döngü, 1 Oca; luteal 12 → ovülasyon = 29 Oca − 12 = 17 Oca.
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), lutealPhaseLength: 12);
      final s = computeStatus(
          settings, _periodRun('a', DateTime(2025, 1, 1), 4),
          today: DateTime(2025, 1, 3));
      expect(s.nextPeriod, DateTime(2025, 1, 29));
      expect(s.ovulationDay, DateTime(2025, 1, 17));
      expect(s.fertileStart, DateTime(2025, 1, 12)); // ovülasyon − 5
      expect(s.fertileEnd, DateTime(2025, 1, 18)); // ovülasyon + 1 (My Calendar pariteti)
    });

    test('geçersiz (10–16 dışı) lutealPhaseLength → 14 varsayılan', () {
      final settings = CycleSettings(
          firstPeriodDate: DateTime(2025, 1, 1), lutealPhaseLength: 20);
      final s = computeStatus(
          settings, _periodRun('a', DateTime(2025, 1, 1), 4),
          today: DateTime(2025, 1, 3));
      expect(s.ovulationDay, DateTime(2025, 1, 15)); // 29 − 14
    });
  });

  group('yaklaşan doğurganlık penceresi (#11)', () {
    test('luteal fazda (pencere geçmiş) → sonraki döngünün penceresi', () {
      // 28 günlük döngü: 1 Oca başlangıç → ovülasyon ~15 Oca, pencere 10–15 Oca.
      // 20 Oca'da pencere geçmiş → yaklaşan = sonraki döngününki (Şubat).
      final settings = CycleSettings(firstPeriodDate: DateTime(2025, 1, 1));
      final status = computeStatus(
          settings, _periodRun('a', DateTime(2025, 1, 1), 4),
          today: DateTime(2025, 1, 20));
      expect(status.fertileWindowIsNextCycle, isTrue);
      // Mevcut pencere (calendar) geçmişte kalır.
      expect(status.fertileEnd!.isBefore(DateTime(2025, 1, 20)), isTrue);
      // Yaklaşan pencere bugünden sonra.
      expect(status.upcomingFertileEnd!.isAfter(DateTime(2025, 1, 20)), isTrue);
    });

    test('foliküler fazda (pencere gelecekte) → mevcut döngünün penceresi', () {
      final settings = CycleSettings(firstPeriodDate: DateTime(2025, 1, 1));
      final status = computeStatus(
          settings, _periodRun('a', DateTime(2025, 1, 1), 4),
          today: DateTime(2025, 1, 8));
      expect(status.fertileWindowIsNextCycle, isFalse);
      expect(status.upcomingFertileStart, status.fertileStart);
      expect(status.upcomingFertileEnd, status.fertileEnd);
    });
  });

  group('CycleEntry.isPeriod', () {
    test('medium/heavy/light adettir', () {
      for (final f in [FlowLevel.light, FlowLevel.medium, FlowLevel.heavy]) {
        expect(CycleEntry(id: 'x', date: DateTime(2025, 1, 1), flow: f).isPeriod,
            isTrue);
      }
    });
    test('none/spotting/null adet değildir', () {
      expect(CycleEntry(id: 'x', date: DateTime(2025, 1, 1), flow: FlowLevel.none)
          .isPeriod, isFalse);
      expect(
          CycleEntry(id: 'x', date: DateTime(2025, 1, 1), flow: FlowLevel.spotting)
              .isPeriod,
          isFalse);
      expect(CycleEntry(id: 'x', date: DateTime(2025, 1, 1)).isPeriod, isFalse);
    });
    test('loşia rengi taşıyan gün adet değildir (akış olsa bile)', () {
      // Doğum sonrası loşia günü: akış girilmiş olsa da loşia rengi varsa adet
      // sayılmaz → yanlış döngü başlangıcı üretmez (regresyon).
      expect(
          CycleEntry(
                  id: 'x',
                  date: DateTime(2025, 1, 1),
                  flow: FlowLevel.heavy,
                  lochiaColor: LochiaColor.red)
              .isPeriod,
          isFalse);
    });
  });
}
