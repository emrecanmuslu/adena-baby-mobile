import 'package:intl/intl.dart';

import 'i18n.dart';

/// Locale-duyarlı tarih/saat biçimlendirme. Tüm ekranlar sabit 'tr_TR' yerine
/// bu yardımcıları kullanır; aktif uygulama diline (I18n.instance.locale) göre
/// Türkçe (gg AAA · 24s) veya Amerikan İngilizcesi (AAA gg · 12s AM/PM) verir.

bool get _en => I18n.instance.locale == 'en';

/// DateFormat için aktif intl locale etiketi.
String dfLocale() => _en ? 'en_US' : 'tr_TR';

/// Saat: tr → 14:30, en → 2:30 PM.
String fmtTime(DateTime dt) =>
    DateFormat(_en ? 'h:mm a' : 'HH:mm', dfLocale()).format(dt);

/// Gün+kısa ay: tr → 5 Haz, en → Jun 5.
String fmtDayMon(DateTime dt) =>
    DateFormat(_en ? 'MMM d' : 'd MMM', dfLocale()).format(dt);

/// Gün+kısa ay+yıl: tr → 5 Haz 2026, en → Jun 5, 2026.
String fmtDayMonYear(DateTime dt) =>
    DateFormat(_en ? 'MMM d, y' : 'd MMM y', dfLocale()).format(dt);

/// Gün+tam ay: tr → 5 Haziran, en → June 5.
String fmtDayMonth(DateTime dt) =>
    DateFormat(_en ? 'MMMM d' : 'd MMMM', dfLocale()).format(dt);

/// Gün+tam ay+yıl: tr → 5 Haziran 2026, en → June 5, 2026.
String fmtDayMonthYear(DateTime dt) =>
    DateFormat(_en ? 'MMMM d, y' : 'd MMMM y', dfLocale()).format(dt);

/// Gün+kısa ay · saat: tr → 5 Haz · 14:30, en → Jun 5 · 2:30 PM.
String fmtDayMonTime(DateTime dt) =>
    DateFormat(_en ? 'MMM d · h:mm a' : 'd MMM · HH:mm', dfLocale()).format(dt);

/// Gün+tam ay · saat: tr → 5 Haziran · 14:30, en → June 5 · 2:30 PM.
String fmtDayMonthTime(DateTime dt) =>
    DateFormat(_en ? 'MMMM d · h:mm a' : 'd MMMM · HH:mm', dfLocale()).format(dt);

/// Tam ay+yıl (başlık/gruplama): tr → Haziran 2026, en → June 2026.
String fmtMonthYear(DateTime dt) =>
    DateFormat('MMMM y', dfLocale()).format(dt);

/// Kısa gün adı (E): tr → Pzt, en → Mon.
String fmtWeekdayShort(DateTime dt) =>
    DateFormat('E', dfLocale()).format(dt);

/// Tam gün adı (EEEE): tr → Pazartesi, en → Monday.
String fmtWeekdayFull(DateTime dt) =>
    DateFormat('EEEE', dfLocale()).format(dt);
