import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:adena_baby/core/dates.dart';
import 'package:adena_baby/core/i18n.dart';

/// dates.dart: locale-duyarlı tarih/saat biçimlendirme. Aktif dile (I18n.instance)
/// göre tr_TR (24s, "gg AAA") veya en_US (12s AM/PM, "AAA gg") verir.
/// I18n saf bir singleton (binding gerekmez); intl tarih sembolleri yüklenir.

void main() {
  // intl yerel tarih sembollerini yükle (tr_TR + en_US adlandırmaları için).
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  // Her testten sonra varsayılan dile (tr) dön — global singleton.
  tearDown(() => I18n.instance.apply('tr', const {}));

  // Sabit referans an: 5 Haziran 2026, Cuma, 14:30.
  final dt = DateTime(2026, 6, 5, 14, 30);

  group('dfLocale — aktif dile göre intl etiketi', () {
    test('varsayılan (tr) → tr_TR', () {
      expect(dfLocale(), 'tr_TR');
    });

    test('dil en → en_US', () {
      I18n.instance.apply('en', const {});
      expect(dfLocale(), 'en_US');
    });
  });

  group('Türkçe biçimlendirme (varsayılan)', () {
    test('fmtTime → 24 saat (14:30)', () {
      expect(fmtTime(dt), '14:30');
    });

    test('fmtDayMon → "5 Haz"', () {
      expect(fmtDayMon(dt), '5 Haz');
    });

    test('fmtDayMonYear → "5 Haz 2026"', () {
      expect(fmtDayMonYear(dt), '5 Haz 2026');
    });

    test('fmtDayMonth → "5 Haziran"', () {
      expect(fmtDayMonth(dt), '5 Haziran');
    });

    test('fmtDayMonthYear → "5 Haziran 2026"', () {
      expect(fmtDayMonthYear(dt), '5 Haziran 2026');
    });

    test('fmtMonthYear → "Haziran 2026"', () {
      expect(fmtMonthYear(dt), 'Haziran 2026');
    });

    test('fmtDayMonTime → "5 Haz · 14:30"', () {
      expect(fmtDayMonTime(dt), '5 Haz · 14:30');
    });

    test('fmtWeekdayFull → "Cuma"', () {
      expect(fmtWeekdayFull(dt), 'Cuma');
    });
  });

  group('İngilizce biçimlendirme (dil=en)', () {
    setUp(() => I18n.instance.apply('en', const {}));

    test('fmtTime → 12 saat AM/PM (2:30 PM)', () {
      expect(fmtTime(dt), '2:30 PM');
    });

    test('fmtTime sabah → AM', () {
      expect(fmtTime(DateTime(2026, 6, 5, 9, 5)), '9:05 AM');
    });

    test('fmtDayMon → "Jun 5"', () {
      expect(fmtDayMon(dt), 'Jun 5');
    });

    test('fmtDayMonYear → "Jun 5, 2026"', () {
      expect(fmtDayMonYear(dt), 'Jun 5, 2026');
    });

    test('fmtDayMonth → "June 5"', () {
      expect(fmtDayMonth(dt), 'June 5');
    });

    test('fmtMonthYear → "June 2026"', () {
      expect(fmtMonthYear(dt), 'June 2026');
    });

    test('fmtDayMonTime → "Jun 5 · 2:30 PM"', () {
      expect(fmtDayMonTime(dt), 'Jun 5 · 2:30 PM');
    });

    test('fmtWeekdayFull → "Friday"', () {
      expect(fmtWeekdayFull(dt), 'Friday');
    });
  });
}
