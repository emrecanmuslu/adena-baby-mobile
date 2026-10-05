import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/yesterday_recap.dart';
import 'package:adena_baby/models/medication_plan.dart';
import 'package:adena_baby/models/record.dart';

final _day = DateTime(2026, 10, 4); // "dün"
var _n = 0;

Record _r(RecordType t, DateTime ts, Map<String, dynamic> data, {String? by}) =>
    Record(id: 'r${_n++}', baby: 'b1', type: t, ts: ts, data: data, createdBy: by);

DateTime _at(int dayOffset, int h, [int m = 0]) =>
    _day.add(Duration(days: dayOffset, hours: h, minutes: m));

Record _sleep(int dayOffset, int h, int m, int dur) => _r(
    RecordType.sleep,
    _at(dayOffset, h, m),
    {'start_ts': _at(dayOffset, h, m).toUtc().toIso8601String(), 'duration': dur});

Record _breast(int dayOffset, int h, [int m = 0]) => _r(
    RecordType.feed, _at(dayOffset, h, m), {'sub': 'breast', 'left_min': 7, 'right_min': 6});

Record _diaper(int h, String sub) => _r(RecordType.diaper, _at(0, h), {'sub': sub});

/// Önceki 5 gün: gece 240 dk + gündüz 60 dk uyku (ortalama oluşsun).
List<Record> _pastSleeps({int longest = 240, int nap = 60}) => [
      for (var d = -5; d <= -1; d++) ...[
        _sleep(d, 20, 0, longest),
        _sleep(d, 13, 0, nap),
      ],
    ];

void main() {
  test('dün hiç kayıt yoksa özet yok', () {
    expect(buildYesterdayRecap(day: _day, history: _pastSleeps()), isNull);
  });

  test('kaydı olmayan kategori hiç görünmez (yalnız uyku)', () {
    final r = buildYesterdayRecap(
        day: _day, history: [_sleep(0, 20, 0, 200), _sleep(0, 13, 0, 50)])!;
    expect(r.ribbon.feeds, isEmpty);
    expect(r.ribbon.diapers, isEmpty);
    expect(r.ribbon.sleeps.length, 2);
    expect(
        r.highlights.map((h) => h.kind),
        isNot(anyOf(contains(RecapHighlightKind.diaper),
            contains(RecapHighlightKind.breast))));
    expect(r.headline.kind, RecapHeadlineKind.sleepTotal);
    expect(r.headline.minutes, 250);
    expect(r.littleData, isTrue); // geçmiş < 3 gün → karşılaştırma yok
    expect(r.highlights.every((h) => h.deltaMin == null), isTrue);
  });

  test('en uzun uyku ortalamanın ≥%15 üstünde → başlık + rozet + "en uzunu"', () {
    final r = buildYesterdayRecap(
        day: _day, history: [..._pastSleeps(), _sleep(0, 20, 0, 290), _sleep(0, 13, 0, 60)])!;
    expect(r.headline.kind, RecapHeadlineKind.longestSleep);
    expect(r.headline.minutes, 290);
    final h = r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.longestSleep);
    expect(h.deltaMin, 50);
    expect(h.flag, isTrue);
    expect(r.littleData, isFalse);
  });

  test('fark eşiğin altındaysa rozet yok, başlık varsayılana düşer', () {
    final r = buildYesterdayRecap(
        day: _day, history: [..._pastSleeps(), _sleep(0, 20, 0, 250), _sleep(0, 13, 0, 60)])!;
    expect(r.headline.kind, RecapHeadlineKind.sleepTotal);
    expect(
        r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.longestSleep).deltaMin,
        isNull);
  });

  test('ilk ek gıda: bilinmeyen ad → "bir ilk" başlığı; bilinen ad → değil', () {
    final carrot = _r(RecordType.feed, _at(0, 12, 15),
        {'sub': 'solid', 'food_name': 'Havuç püresi', 'amount': 2, 'reaction': 'sevdi'});
    final first = buildYesterdayRecap(day: _day, history: [carrot, _breast(0, 9)])!;
    expect(first.headline.kind, RecapHeadlineKind.firstFood);
    expect(first.headline.text, 'Havuç püresi');
    expect(first.highlights.first.kind, RecapHighlightKind.firstFood);
    expect(first.highlights.first.first, isTrue);

    final known = buildYesterdayRecap(
        day: _day, history: [carrot, _breast(0, 9)], knownFoods: {'havuç püresi'})!;
    expect(known.headline.kind, isNot(RecapHeadlineKind.firstFood));
    expect(known.highlights.any((h) => h.first), isFalse);
  });

  test('ateş kaydı → "yakın takip" başlığı; tepe ve son ölçüm', () {
    final r = buildYesterdayRecap(day: _day, history: [
      _r(RecordType.temperature, _at(0, 10), {'value': 37.9, 'unit': 'C'}),
      _r(RecordType.temperature, _at(0, 15), {'value': 38.2, 'unit': 'C'}),
      _r(RecordType.temperature, _at(0, 21, 40), {'value': 37.4, 'unit': 'C'}),
      _breast(0, 9),
    ])!;
    expect(r.headline.kind, RecapHeadlineKind.closeWatch);
    final f = r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.fever);
    expect(f.value, 38.2);
    expect(f.value2, 37.4);
    expect(f.count, 3);
  });

  group('ilaç planı', () {
    MedicationPlan plan({DateTime? created}) => MedicationPlan(
        id: 1,
        name: 'Demir',
        dose: '2,5 ml',
        times: const ['08:00', '20:00'],
        active: true,
        createdAt: created ?? DateTime(2026, 9, 1));
    Record given(int h) => _r(RecordType.medication, _at(0, h, 5), {'name': 'Demir', 'given': true});

    test('hepsi kayıtlı → ✓, eksik yok', () {
      final r = buildYesterdayRecap(
          day: _day, history: [given(8), given(20), _breast(0, 9)], plans: [plan()])!;
      final m = r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.medication);
      expect((m.count, m.count2), (2, 2));
      expect(m.ok, isTrue);
      expect(m.missing, isEmpty);
    });

    test('eksik doz → "kayıtlı değil" (✓ yok), eklenebilir doz = sıradaki', () {
      final r = buildYesterdayRecap(
          day: _day, history: [given(8), _breast(0, 9)], plans: [plan()])!;
      final m = r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.medication);
      expect((m.count, m.count2), (1, 2));
      expect(m.ok, isFalse);
      expect(m.missing.single.time, '20:00');
    });

    test('atlanan doz eksik sayılmaz ama ✓ da değil', () {
      final skip = _r(RecordType.medication, _at(0, 21),
          {'name': 'Demir', 'given': false, 'skipped': true});
      final r = buildYesterdayRecap(
          day: _day, history: [given(8), skip, _breast(0, 9)], plans: [plan()])!;
      final m = r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.medication);
      expect(m.missing, isEmpty);
      expect(m.ok, isFalse);
      expect(m.minutes, 1); // atlanan adet
    });

    test('plan dün öğleden sonra oluşturulduysa sabah dozu "kayıtlı değil" sayılmaz', () {
      final r = buildYesterdayRecap(
          day: _day, history: [given(20), _breast(0, 9)], plans: [plan(created: _at(0, 15))])!;
      final m = r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.medication);
      // 08:00 dozu plan yokken geçmişti; 20:00 kaydı sıralı eşlemede ilk doza
      // düşer → görünen tek doz o, eksik yok.
      expect(m.missing.where((d) => d.time == '08:00'), isEmpty);
    });

    test('plan bugün oluşturulduysa dünün özetinde hiç yok', () {
      final r = buildYesterdayRecap(
          day: _day, history: [_breast(0, 9)], plans: [plan(created: _at(1, 7))])!;
      expect(r.highlights.any((h) => h.kind == RecapHighlightKind.medication), isFalse);
    });
  });

  test('şerit: önceki geceden sarkan uyku kırpılır, gece yarısını aşan 24:00\'te kesilir', () {
    final r = buildYesterdayRecap(day: _day, history: [
      _sleep(-1, 22, 0, 300), // 22:00 → 03:00 (dünde 0–180)
      _sleep(0, 23, 0, 240), // 23:00 → 03:00 (dünde 1380–1440)
      _breast(0, 9),
    ])!;
    final s = r.ribbon.sleeps;
    expect((s.first.start, s.first.end), (0, 180));
    expect((s.last.start, s.last.end), (1380, 1440));
    // Süre kaydın TAMAMI; toplam yalnız dün BAŞLAYANLAR.
    expect(r.ribbon.longestMin, 240);
    expect(r.ribbon.sleepTotalMin, 240);
    expect(r.ribbon.sleeps[r.ribbon.longest!].start, 1380);
  });

  test('bez türleri + sayılar (karışık ikisine de sayılır)', () {
    final r = buildYesterdayRecap(day: _day, history: [
      _diaper(8, 'pee'),
      _diaper(11, 'poo'),
      _diaper(15, 'poopee'),
    ])!;
    expect(r.ribbon.diapers.map((d) => d.kind),
        [RecapDiaperKind.pee, RecapDiaperKind.poo, RecapDiaperKind.both]);
    final d = r.highlights.firstWhere((h) => h.kind == RecapHighlightKind.diaper);
    expect((d.count, d.count2), (2, 2)); // kaka: poo+karışık · çiş: pee+karışık
    expect(r.headline.kind, RecapHeadlineKind.diaperCount);
  });

  test('aile: kendi kayıtlarım (null + selfIds) tek kişi; başka üye varsa satır çıkar', () {
    final mine = [
      _r(RecordType.feed, _at(0, 9), {'sub': 'formula', 'ml': 120}),
      _r(RecordType.feed, _at(0, 12), {'sub': 'formula', 'ml': 130}, by: 'me'),
    ];
    final solo = buildYesterdayRecap(day: _day, history: mine, selfIds: {'me'})!;
    expect(solo.contributors, isEmpty);

    final shared = buildYesterdayRecap(
        day: _day,
        history: [...mine, _r(RecordType.diaper, _at(0, 13), {'sub': 'pee'}, by: 'dad')],
        selfIds: {'me'})!;
    expect(shared.contributors.map((c) => (c.userId, c.count)), [(null, 2), ('dad', 1)]);
    expect(shared.headline.kind, RecapHeadlineKind.family);
  });

  test('en fazla 3 öne çıkan; puan sırası: plan > nadir > ritim', () {
    final r = buildYesterdayRecap(
      day: _day,
      history: [
        _breast(0, 6),
        _breast(0, 9),
        _diaper(8, 'pee'),
        _sleep(0, 13, 0, 60),
        _r(RecordType.bath, _at(0, 18), {}),
        _r(RecordType.medication, _at(0, 9, 5), {'name': 'D', 'given': true}),
      ],
      plans: [
        MedicationPlan(
            id: 1,
            name: 'D',
            dose: '',
            times: const ['09:00'],
            active: true,
            createdAt: DateTime(2026, 9, 1)),
      ],
    )!;
    expect(r.highlights.length, 3);
    expect(r.highlights.map((h) => h.kind).take(2),
        [RecapHighlightKind.medication, RecapHighlightKind.bath]);
  });

  test('aynı aday son 2 günde de aynı sıradaysa bir alttakiyle yer değiştirir', () {
    final hist = [_breast(0, 6), _breast(0, 9), _diaper(8, 'pee')];
    final base = buildYesterdayRecap(day: _day, history: hist)!;
    final ids = [for (final h in base.highlights) h.id];
    expect(ids, ['breast', 'diaper']);
    final rotated =
        buildYesterdayRecap(day: _day, history: hist, recentIds: [ids, ids])!;
    expect([for (final h in rotated.highlights) h.id], ['diaper', 'breast']);
  });

  test('bugünkü randevu "bugüne dair" satırına gelir', () {
    final r = buildYesterdayRecap(day: _day, history: [
      _breast(0, 9),
      _r(RecordType.appointment, _at(1, 10, 30), {'title': '6. ay kontrolü'}),
    ])!;
    expect(r.nextAppointment!.data['title'], '6. ay kontrolü');
  });
}
