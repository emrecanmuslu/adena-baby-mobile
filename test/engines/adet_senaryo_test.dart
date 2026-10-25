import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/features/cycle/cycle_anchor.dart';
import 'package:adena_baby/features/cycle/cycle_engine.dart';
import 'package:adena_baby/features/cycle/cycle_guidance.dart';
import 'package:adena_baby/features/cycle/cycle_pregnancy_bridge.dart';
import 'package:adena_baby/models/cycle.dart';

/// ADET-INCELEME.md §3 senaryo tablosu — KALICI sözleşme. Düzeltme turu
/// sonrası (A1–D5) motorun ve saf yönlendirme fonksiyonlarının çıktısı burada
/// sabitlenir; tablo değişirse bu test kırılmalı ve ADET-INCELEME güncellenmeli.
/// Bugün = 11.10.2026; tüm tarihler buna göre.
void main() {
  final today = DateTime(2026, 10, 11);
  DateTime d(int off) => DateTime(2026, 10, 11 + off);
  List<CycleEntry> periods(List<int> starts,
      {int days = 5, Map<int, int>? daysFor}) {
    final out = <CycleEntry>[];
    var i = 0;
    for (final s in starts) {
      for (var k = 0; k < (daysFor?[s] ?? days); k++) {
        out.add(CycleEntry(id: 'e${i++}', date: d(s + k), flow: FlowLevel.medium));
      }
    }
    return out;
  }

  CycleStatus st(CycleSettings s, List<CycleEntry> e) =>
      computeStatus(s, e, today: today);

  /// Aktif senaryo beklentisi: (gün, medyan döngü, sonraki adet, d2n, ovülasyon,
  /// pencere başı–sonu, faz, düşük güven, düzensiz).
  void active(String id, CycleSettings s, List<CycleEntry> e,
      {required int day,
      required int len,
      required DateTime next,
      required int d2n,
      required DateTime ov,
      required DateTime winA,
      required DateTime winB,
      required CyclePhase phase,
      required bool low,
      bool irregular = false,
      List<DateTime> suspected = const [],
      bool longPeriod = false,
      int periodDays = 5}) {
    test(id, () {
      final r = st(s, e);
      expect(r.mode, CycleMode.active, reason: id);
      expect(r.dayInCycle, day, reason: '$id gün');
      expect(r.avgCycleLength, len, reason: '$id medyan döngü');
      expect(r.avgPeriodDays, periodDays, reason: '$id âdet süresi');
      expect(r.nextPeriod, next, reason: '$id sonraki âdet');
      expect(r.daysToNextPeriod, d2n, reason: '$id d2n');
      expect(r.ovulationDay, ov, reason: '$id ovülasyon');
      expect(r.fertileStart, winA, reason: '$id pencere başı');
      expect(r.fertileEnd, winB, reason: '$id pencere sonu');
      expect(r.phase, phase, reason: '$id faz');
      expect(r.lowConfidence, low, reason: '$id düşük güven');
      expect(r.irregular, irregular, reason: '$id düzensiz');
      expect(r.suspectedMissedStarts, suspected, reason: '$id unutulan kayıt');
      expect(longPeriodWarning(e, r), longPeriod, reason: '$id uzun âdet');
      expect(longAmenorrheaWarning(s, r, today: today), isFalse, reason: id);
    });
  }

  const b = CycleSettings();
  group('A — düzenli 28', () {
    active('A1 gün 21', b.copyWith(firstPeriodDate: d(-104)), periods([-104, -76, -48, -20]),
        day: 21, len: 28, next: d(8), d2n: 8, ov: d(-6), winA: d(-11), winB: d(-5),
        phase: CyclePhase.luteal, low: false);
    active('A2 gün 15 (ov)', b.copyWith(firstPeriodDate: d(-98)), periods([-98, -70, -42, -14]),
        day: 15, len: 28, next: d(14), d2n: 14, ov: d(0), winA: d(-5), winB: d(1),
        phase: CyclePhase.ovulation, low: false);
    active('A3 gün 10', b.copyWith(firstPeriodDate: d(-93)), periods([-93, -65, -37, -9]),
        day: 10, len: 28, next: d(19), d2n: 19, ov: d(5), winA: d(0), winB: d(6),
        phase: CyclePhase.follicular, low: false);
    active('A4 1 gün geçti', b.copyWith(firstPeriodDate: d(-113)), periods([-113, -85, -57, -29]),
        day: 30, len: 28, next: d(-1), d2n: -1, ov: d(-15), winA: d(-20), winB: d(-14),
        phase: CyclePhase.luteal, low: false);
    active('A5 12 gün geçti', b.copyWith(firstPeriodDate: d(-124)), periods([-124, -96, -68, -40]),
        day: 41, len: 28, next: d(-12), d2n: -12, ov: d(-26), winA: d(-31), winB: d(-25),
        phase: CyclePhase.luteal, low: false);
  });

  group('B/C — 24 ve 35', () {
    active('B1 24g gün 21', b.copyWith(firstPeriodDate: d(-92)), periods([-92, -68, -44, -20]),
        day: 21, len: 24, next: d(4), d2n: 4, ov: d(-10), winA: d(-15), winB: d(-9),
        phase: CyclePhase.luteal, low: false);
    active('B2 24g gün 10', b.copyWith(firstPeriodDate: d(-81)), periods([-81, -57, -33, -9]),
        day: 10, len: 24, next: d(15), d2n: 15, ov: d(1), winA: d(-4), winB: d(2),
        phase: CyclePhase.follicular, low: false);
    active('C1 35g gün 21', b.copyWith(firstPeriodDate: d(-125)), periods([-125, -90, -55, -20]),
        day: 21, len: 35, next: d(15), d2n: 15, ov: d(1), winA: d(-4), winB: d(2),
        phase: CyclePhase.follicular, low: false);
    active('C2 35g gün 14', b.copyWith(firstPeriodDate: d(-118)), periods([-118, -83, -48, -13]),
        day: 14, len: 35, next: d(22), d2n: 22, ov: d(8), winA: d(3), winB: d(9),
        phase: CyclePhase.follicular, low: false);
  });

  group('D — düzensiz 26/33/29/40 (B2: aralık + düşük güven; B1: medyan 31)', () {
    active('D1 gün 21', b.copyWith(firstPeriodDate: d(-148)), periods([-148, -122, -89, -60, -20]),
        day: 21, len: 31, next: d(11), d2n: 11, ov: d(-3), winA: d(-8), winB: d(-2),
        phase: CyclePhase.luteal, low: true, irregular: true);
    test('D1 aralık 17.10–31.10', () {
      final r = st(b.copyWith(firstPeriodDate: d(-148)), periods([-148, -122, -89, -60, -20]));
      expect(r.nextPeriodEarliest, d(6));
      expect(r.nextPeriodLatest, d(20));
    });
    active('D2 gün 35', b.copyWith(firstPeriodDate: d(-162)), periods([-162, -136, -103, -74, -34]),
        day: 35, len: 31, next: d(-3), d2n: -3, ov: d(-17), winA: d(-22), winB: d(-16),
        phase: CyclePhase.luteal, low: true, irregular: true);
  });

  group('E — tek kayıt', () {
    active('E1', b.copyWith(firstPeriodDate: d(-20)), periods([-20]),
        day: 21, len: 28, next: d(8), d2n: 8, ov: d(-6), winA: d(-11), winB: d(-5),
        phase: CyclePhase.luteal, low: true);
    active('E2 beklenen 30', b.copyWith(firstPeriodDate: d(-20), expectedCycleLength: 30),
        periods([-20]),
        day: 21, len: 30, next: d(10), d2n: 10, ov: d(-4), winA: d(-9), winB: d(-3),
        phase: CyclePhase.luteal, low: true);
  });

  group('F — unutulan ay (B1: dışlanır, sorulur)', () {
    active('F1 (28,56)', b.copyWith(firstPeriodDate: d(-104)), periods([-104, -76, -20]),
        day: 21, len: 28, next: d(8), d2n: 8, ov: d(-6), winA: d(-11), winB: d(-5),
        phase: CyclePhase.luteal, low: true, suspected: [d(-76)]);
    active('F2 (28×5,56)', b.copyWith(firstPeriodDate: d(-216)),
        periods([-216, -188, -160, -132, -104, -76, -20]),
        day: 21, len: 28, next: d(8), d2n: 8, ov: d(-6), winA: d(-11), winB: d(-5),
        phase: CyclePhase.luteal, low: true, suspected: [d(-76)]);
    active('F3 gün 29 → âdet bugün bekleniyor', b.copyWith(firstPeriodDate: d(-112)),
        periods([-112, -84, -28]),
        day: 29, len: 28, next: d(0), d2n: 0, ov: d(-14), winA: d(-19), winB: d(-13),
        phase: CyclePhase.luteal, low: true, suspected: [d(-84)]);
  });

  group('G — uzun âdet (C2)', () {
    active('G1 son âdet 11 gün', b.copyWith(firstPeriodDate: d(-95)),
        periods([-95, -67, -39, -11], daysFor: {-11: 11}),
        day: 12, len: 28, next: d(17), d2n: 17, ov: d(3), winA: d(-2), winB: d(4),
        phase: CyclePhase.follicular, low: false, longPeriod: true);
    active('G2 her âdet 10 gün', b.copyWith(firstPeriodDate: d(-104)),
        periods([-104, -76, -48, -20], days: 10),
        day: 21, len: 28, next: d(8), d2n: 8, ov: d(-6), winA: d(-11), winB: d(-5),
        phase: CyclePhase.luteal, low: false, longPeriod: true, periodDays: 10);
  });

  group('H — TTC', () {
    final ttc = b.copyWith(lifecycleMode: CycleLifecycleMode.ttc);
    active('H1 28g ov−2', ttc.copyWith(firstPeriodDate: d(-96)), periods([-96, -68, -40, -12]),
        day: 13, len: 28, next: d(16), d2n: 16, ov: d(2), winA: d(-3), winB: d(3),
        phase: CyclePhase.follicular, low: false);
    active('H3 32g ov−2', ttc.copyWith(firstPeriodDate: d(-112)), periods([-112, -80, -48, -16]),
        day: 17, len: 32, next: d(16), d2n: 16, ov: d(2), winA: d(-3), winB: d(3),
        phase: CyclePhase.follicular, low: false);
    test('H1/H2 olasılık: ov−2 yüksek, ov çok yüksek', () {
      final h1 = st(ttc.copyWith(firstPeriodDate: d(-96)), periods([-96, -68, -40, -12]));
      expect(conceptionChance(today, h1), ConceptionChance.high); // ov−2
      expect(conceptionChance(d(-1), h1), ConceptionChance.medium); // ov−3
      final h2 = st(ttc.copyWith(firstPeriodDate: d(-98)), periods([-98, -70, -42, -14]));
      expect(conceptionChance(today, h2), ConceptionChance.veryHigh);
    });
  });

  group('I — gebelik (SAT+280)', () {
    test('SAT 70 gün → 10h0g, TDT 09.05.2027; 301 gün → null', () {
      final p = pregnancyFromLmp(d(-70), today: today)!;
      expect((p.weeks, p.days, p.dueDate), (10, 0, DateTime(2027, 5, 9)));
      expect(pregnancyFromLmp(d(-301), today: today), isNull);
    });
  });

  group('J — doğum sonrası', () {
    final pp = b.copyWith(
        lifecycleMode: CycleLifecycleMode.postpartum, predictionsHidden: true);
    void ppRow(String id, CycleSettings s,
        {required CycleMode mode, required LamState lam, required bool amen}) {
      test(id, () {
        final r = st(s, const []);
        expect(r.mode, mode, reason: id);
        expect(lamState(s, today: today), lam, reason: '$id LAM');
        expect(longAmenorrheaWarning(s, r, today: today), amen, reason: '$id amenore');
      });
    }

    ppRow('J1 +3 gün tam emziren', pp.copyWith(birthDate: d(-3), breastfeeding: Breastfeeding.exclusive),
        mode: CycleMode.lochia, lam: LamState.conditions, amen: false);
    ppRow('J2 +21 gün', pp.copyWith(birthDate: d(-21), breastfeeding: Breastfeeding.exclusive),
        mode: CycleMode.lochia, lam: LamState.conditions, amen: false);
    ppRow('J3 +43 gün karışık', pp.copyWith(birthDate: d(-43), breastfeeding: Breastfeeding.mixed),
        mode: CycleMode.waiting, lam: LamState.notProtective, amen: false);
    ppRow('J4 +70 gün emzirmiyor', pp.copyWith(birthDate: d(-70), breastfeeding: Breastfeeding.none),
        mode: CycleMode.waiting, lam: LamState.hidden, amen: false);
    ppRow('J4b +85 gün emzirmiyor → hekim kartı', pp.copyWith(birthDate: d(-85), breastfeeding: Breastfeeding.none),
        mode: CycleMode.waiting, lam: LamState.hidden, amen: true);
    ppRow('J5 +150 gün tam emziren', pp.copyWith(birthDate: d(-150), breastfeeding: Breastfeeding.exclusive),
        mode: CycleMode.waiting, lam: LamState.conditions, amen: false);
    ppRow('J5b +200 gün tam emziren → LAM geçersiz, kart yok', pp.copyWith(birthDate: d(-200), breastfeeding: Breastfeeding.exclusive),
        mode: CycleMode.waiting, lam: LamState.notProtective, amen: false);
    test('J6 +25 gün akış kaydı çapa adayı DEĞİL (A3)', () {
      final s = pp.copyWith(birthDate: d(-25), breastfeeding: Breastfeeding.exclusive);
      expect(inPostpartumLochiaWindow(d(-5), s), isTrue);
      expect(anchorCandidate([d(-5)], s), isNull);
      // 43–56. gün → sorulur.
      final s2 = pp.copyWith(birthDate: d(-50));
      expect(postpartumAskFirstPeriod(today, s2), isTrue);
    });
  });

  group('K — kayıp', () {
    final loss = b.copyWith(lifecycleMode: CycleLifecycleMode.loss, predictionsHidden: true);
    for (final (id, ago, amen) in [('K1 +14', 14, false), ('K2 +42', 42, false), ('K2b +57', 57, true)]) {
      test('$id gün → bekleme, hekim kartı: $amen', () {
        final s = loss.copyWith(lastLossDate: d(-ago));
        final r = st(s, const []);
        expect(r.mode, CycleMode.waiting);
        expect(longAmenorrheaWarning(s, r, today: today), amen);
      });
    }
    active('K4 kayıp +42, ilk âdet T−3',
        loss.copyWith(
            lastLossDate: d(-42),
            lifecycleMode: CycleLifecycleMode.tracking,
            predictionsHidden: false,
            firstPeriodDate: d(-3)),
        periods([-3]),
        day: 4, len: 28, next: d(25), d2n: 25, ov: d(11), winA: d(6), winB: d(12),
        phase: CyclePhase.menstrual, low: true);
  });

  group('L — ayarlar', () {
    active('L1 luteal 12', b.copyWith(firstPeriodDate: d(-98), lutealPhaseLength: 12),
        periods([-98, -70, -42, -14]),
        day: 15, len: 28, next: d(14), d2n: 14, ov: d(2), winA: d(-3), winB: d(3),
        phase: CyclePhase.follicular, low: false);
    active('L2 akıllı tahmin kapalı', b.copyWith(
            firstPeriodDate: d(-134), smartPrediction: false, expectedCycleLength: 28),
        periods([-134, -99, -64, -29]),
        day: 30, len: 28, next: d(-1), d2n: -1, ov: d(-15), winA: d(-20), winB: d(-14),
        phase: CyclePhase.luteal, low: false);
  });
}
