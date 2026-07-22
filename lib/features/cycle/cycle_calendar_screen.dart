import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import 'cycle_engine.dart';
import 'cycle_entry_sheet.dart';
import 'cycle_period_adjust_sheet.dart';
import 'cycle_shell.dart';
import 'cycle_widgets.dart';

/// Takvim — My Calendar pariteli KUTU IZGARA: kenarlıklı büyük hücreler, hücre
/// dolgusu (adet/tahmin/doğurgan/yumurtlama/loşia), döngü-günü köşe numarası,
/// köşe kayıt ikonları, gebe-kalma olasılığı, Ay/Hafta/Liste görünümü, FAQ,
/// haftanın ilk günü ayarı. Takvimden adet başlat/bitir/kaldır.
class CycleCalendarScreen extends ConsumerStatefulWidget {
  const CycleCalendarScreen({super.key});

  @override
  ConsumerState<CycleCalendarScreen> createState() => _CycleCalendarScreenState();
}

class _CycleCalendarScreenState extends ConsumerState<CycleCalendarScreen> {
  late DateTime _month;
  late DateTime _selected;
  String _view = 'month'; // month | week | list
  final Set<int> _faqOpen = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selected = DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
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
                  final byDay = <String, CycleEntry>{
                    for (final e in entries) _key(e.date): e,
                  };
                  final sunday = settings.weekStartsSunday;
                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                        16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
                    children: [
                      _topBar(),
                      const SizedBox(height: 10),
                      if (_view == 'list')
                        _listView(entries, status)
                      else ...[
                        _segment(),
                        const SizedBox(height: 10),
                        _weekHeader(sunday),
                        _gridBox(byDay, status, sunday),
                      ],
                      const SizedBox(height: 14),
                      _dayPanel(byDay, status, settings),
                      const SizedBox(height: 14),
                      _legend(),
                      const SizedBox(height: 14),
                      _faqSection(),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  DateTime _dOnly(DateTime x) => DateTime(x.year, x.month, x.day);

  // ── üst bar: ay gezgini + liste/ızgara geçişi ──
  Widget _topBar() => Row(
        children: [
          _navBtn(Icons.chevron_left_rounded,
              () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1))),
          Expanded(
            child: Text(
                _view == 'list' ? tr('Kayıtlar') : fmtMonthYear(_month),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
          _view == 'list'
              ? const SizedBox(width: 38)
              : _navBtn(Icons.chevron_right_rounded,
                  () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1))),
          const SizedBox(width: 6),
          _navBtn(
              _view == 'list' ? Icons.calendar_view_month_rounded : Icons.view_agenda_outlined,
              () => setState(() => _view = _view == 'list' ? 'month' : 'list')),
        ],
      );

  Widget _navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: AppColors.smallShadow),
          child: Icon(icon, size: 22, color: AppColors.roseD),
        ),
      );

  // ── Ay / Hafta segmenti ──
  Widget _segment() {
    Widget seg(String id, String label) {
      final on = _view == id;
      return GestureDetector(
        onTap: () => setState(() => _view = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: on ? Theme.of(context).colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: on ? AppColors.smallShadow : null,
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: on ? AppColors.roseD : AppColors.muted)),
        ),
      );
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: AppColors.roseBg, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          seg('month', tr('Ay')),
          seg('week', tr('Hafta')),
        ]),
      ),
    );
  }

  // ── haftanın gün başlıkları (hafta başına duyarlı) ──
  Widget _weekHeader(bool sunday) {
    final base = [
      tr('Pzt'), tr('Sal'), tr('Çar'), tr('Per'), tr('Cum'), tr('Cmt'), tr('Paz')
    ];
    final labels = sunday ? [base[6], ...base.sublist(0, 6)] : base;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Text(labels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _isWeekendCol(i, sunday) ? AppColors.roseD : AppColors.muted)),
          ),
      ]),
    );
  }

  bool _isWeekendCol(int col, bool sunday) {
    // sütun → haftanın günü → Cmt/Paz mı
    final weekday = sunday ? (col == 0 ? 7 : col) : col + 1; // 1=Pzt..7=Paz
    return weekday == 6 || weekday == 7;
  }

  int _colOf(DateTime d, bool sunday) =>
      sunday ? d.weekday % 7 : (d.weekday - 1) % 7;

  // ── KUTU IZGARA ──
  Widget _gridBox(Map<String, CycleEntry> byDay, CycleStatus status, bool sunday) {
    final today = DateTime.now();
    List<DateTime?> cells;
    if (_view == 'week') {
      final start = cycleAddDays(_dOnly(_selected), -_colOf(_selected, sunday));
      cells = [for (var i = 0; i < 7; i++) cycleAddDays(start, i)];
    } else {
      final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
      final lead = _colOf(_month, sunday);
      cells = [
        ...List.filled(lead, null),
        for (var d = 1; d <= daysInMonth; d++) DateTime(_month.year, _month.month, d),
      ];
      while (cells.length % 7 != 0) {
        cells.add(null);
      }
    }
    final weeks = [
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
    // dış kenarlık üst+sol; her hücre sağ+alt → temiz 1px ızgara
    return Container(
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: AppColors.line),
              left: BorderSide(color: AppColors.line))),
      child: Column(
        children: [
          for (final week in weeks)
            Row(children: [for (final d in week) _box(d, byDay, status, today)]),
        ],
      ),
    );
  }

  Widget _box(DateTime? d, Map<String, CycleEntry> byDay, CycleStatus status,
      DateTime today) {
    final border = Border(
        right: BorderSide(color: AppColors.line),
        bottom: BorderSide(color: AppColors.line));
    if (d == null) {
      return Expanded(
          child: Container(
              height: 64, decoration: BoxDecoration(border: border)));
    }
    final kind = _kindOf(d, byDay, status); // period/pred/frt/lochia/null
    final isOvu = status.mode == CycleMode.active &&
        status.ovulationDay != null &&
        _same(d, status.ovulationDay!);
    final isToday = _same(d, today);
    final sel = _same(d, _selected);
    final entry = byDay[_key(d)];
    final cd = _cycleDayNum(d, status);

    Color fill = Colors.transparent;
    Color fg = AppColors.ink;
    if (kind == 'period') {
      fill = AppColors.rose;
      fg = Colors.white;
    } else if (kind == 'lochia') {
      fill = AppColors.lochiaBg;
      fg = AppColors.lochia;
    } else if (kind == 'pred') {
      fill = AppColors.roseBg;
      fg = AppColors.roseD;
    } else if (kind == 'frt') {
      fill = AppColors.sageBg;
      fg = AppColors.sageD;
    }
    if (isOvu) {
      fill = AppColors.goldBg;
      fg = AppColors.goldD;
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (sel) {
            showCycleEntrySheet(context, ref,
                date: d,
                existing: entry,
                lochiaMode: status.mode != CycleMode.active);
          } else {
            setState(() => _selected = d);
          }
        },
        child: Container(
          height: 64,
          decoration: BoxDecoration(color: fill, border: border),
          child: Stack(children: [
            // gün numarası (sol üst)
            Positioned(
              top: 5,
              left: 7,
              child: Text('${d.day}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
                      color: fg)),
            ),
            // döngü-günü numarası (sağ üst, soluk)
            if (cd != null)
              Positioned(
                top: 5,
                right: 6,
                child: Text('$cd',
                    style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: fg == Colors.white
                            ? Colors.white70
                            : AppColors.muted2)),
              ),
            // doğurgan filizi / yumurtlama noktası (sol alt)
            if (isOvu)
              Positioned(
                  bottom: 6,
                  left: 7,
                  child: Container(
                      width: 7,
                      height: 7,
                      decoration:
                          BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)))
            else if (kind == 'frt')
              Positioned(
                  bottom: 5,
                  left: 6,
                  child: Icon(Icons.eco_rounded, size: 12, color: AppColors.sageD)),
            // kayıt ikonları (sağ alt): akış damlası + not/belirti
            if (entry != null)
              Positioned(
                bottom: 5,
                right: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (entry.flow != null)
                    Icon(Icons.water_drop_rounded,
                        size: 10,
                        color: kind == 'period' ? Colors.white : flowColor(entry.flow!)),
                  if (entry.symptoms.isNotEmpty || entry.mood != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                              color: kind == 'period' ? Colors.white70 : AppColors.roseD,
                              shape: BoxShape.circle)),
                    ),
                  if (entry.note != null && entry.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(Icons.sticky_note_2_rounded,
                          size: 10,
                          color: kind == 'period' ? Colors.white : AppColors.muted),
                    ),
                ]),
              ),
            // bugün / seçili vurgusu (iç çerçeve)
            if (isToday || sel)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isToday ? AppColors.roseD : AppColors.ink2,
                        width: isToday ? 2 : 1.4),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  /// Bir günün dolgu türü (saf): gerçek kayıt > tahmin.
  String? _kindOf(DateTime d, Map<String, CycleEntry> byDay, CycleStatus status) {
    final e = byDay[_key(d)];
    if (e != null) {
      if (e.isPeriod) return 'period';
      if (e.lochiaColor != null) return 'lochia';
    }
    if (status.mode == CycleMode.active) {
      // Devam eden adetin tahmini kalan günleri: yalnız ilk gün kaydedilse bile
      // takvim adet süresini (avgPeriodDays) doldursun. Yalnız açık/son döngüye
      // uygulanır (eski döngüler kullanıcının işaretlediği kadar kalır). (#3)
      if (status.spans.isNotEmpty) {
        final last = status.spans.last;
        if (last.length == null) {
          final ps = _dOnly(last.start);
          final pe = cycleAddDays(ps, status.avgPeriodDays - 1);
          if (!d.isBefore(ps) && !d.isAfter(pe)) return 'pred';
        }
      }
      final np = status.nextPeriod;
      if (np != null) {
        final predEnd = cycleAddDays(_dOnly(np), status.avgPeriodDays - 1);
        if (!d.isBefore(_dOnly(np)) && !d.isAfter(predEnd)) return 'pred';
      }
      if (status.fertileStart != null &&
          !d.isBefore(_dOnly(status.fertileStart!)) &&
          !d.isAfter(_dOnly(status.fertileEnd!))) {
        return 'frt';
      }
    }
    return null;
  }

  /// Günün döngü-günü numarası (köşe rozeti). Yalnız aktif modda.
  int? _cycleDayNum(DateTime d, CycleStatus status) {
    if (status.mode != CycleMode.active || status.spans.isEmpty) return null;
    final dd = _dOnly(d);
    final firstStart = _dOnly(status.spans.first.start);
    if (dd.isBefore(firstStart)) return null;
    for (var i = status.spans.length - 1; i >= 0; i--) {
      final start = _dOnly(status.spans[i].start);
      if (dd.isBefore(start)) continue;
      final nextStart =
          i + 1 < status.spans.length ? _dOnly(status.spans[i + 1].start) : null;
      if (nextStart != null) {
        if (!dd.isBefore(nextStart)) continue;
        return dd.difference(start).inDays + 1;
      }
      final avg = status.avgCycleLength;
      var s = start;
      while (avg > 0 && dd.difference(s).inDays >= avg) {
        s = cycleAddDays(s, avg);
      }
      final n = dd.difference(s).inDays + 1;
      return (n >= 1 && n <= avg + 4) ? n : null;
    }
    return null;
  }

  // ── LİSTE (kronolojik kayıtlar) ──
  Widget _listView(List<CycleEntry> entries, CycleStatus status) {
    final rows = [...entries]..sort((a, b) => b.date.compareTo(a.date));
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
            child: Text(tr('Henüz kayıt yok.'),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.muted))),
      );
    }
    return Column(children: [
      for (final e in rows) _listRow(e, status),
    ]);
  }

  Widget _listRow(CycleEntry e, CycleStatus status) {
    final parts = <String>[];
    if (e.flow != null) parts.add('${tr('Akış')}: ${flowLabel(e.flow!)}');
    if (e.lochiaColor != null) parts.add(lochiaLabel(e.lochiaColor!));
    if (e.symptoms.isNotEmpty) parts.add(trp('{n} belirti', {'n': e.symptoms.length}));
    if (e.mood != null) parts.add(moodEmojis[(e.mood! - 1).clamp(0, 4)]);
    if (e.note != null && e.note!.isNotEmpty) parts.add(tr('not'));
    final isPeriod = e.isPeriod;
    return GestureDetector(
      onTap: () => showCycleEntrySheet(context, ref,
          date: e.date,
          existing: e,
          lochiaMode: status.mode != CycleMode.active),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.smallShadow),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: isPeriod ? AppColors.rose : AppColors.roseBg,
                borderRadius: BorderRadius.circular(13)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${e.date.day}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: isPeriod ? Colors.white : AppColors.roseD,
                      height: 1)),
              Text(_monthAbbr(e.date.month),
                  style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: isPeriod ? Colors.white70 : AppColors.muted)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isPeriod ? tr('Adet günü') : tr('Kayıt'),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
              if (parts.isNotEmpty)
                Text(parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted2),
        ]),
      ),
    );
  }

  String _monthAbbr(int m) => [
        '', tr('Oca'), tr('Şub'), tr('Mar'), tr('Nis'), tr('May'), tr('Haz'),
        tr('Tem'), tr('Ağu'), tr('Eyl'), tr('Eki'), tr('Kas'), tr('Ara')
      ][m];

  Widget _legend() {
    Widget chip(Color bg, Color? border, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(4),
                    border: border == null ? null : Border.all(color: border, width: 1.5))),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink2)),
          ],
        );
    return Wrap(
      spacing: 14,
      runSpacing: 9,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip(AppColors.rose, null, tr('Adet')),
        chip(AppColors.roseBg, AppColors.rose, tr('Tahmini')),
        chip(AppColors.sageBg, AppColors.sageD, tr('Doğurganlık')),
        chip(AppColors.goldBg, AppColors.gold, tr('Yumurtlama')),
        chip(AppColors.lochiaBg, AppColors.lochia, tr('Loşia')),
        AdInfoDot(title: tr('Takvim renkleri'), body: CycleInfo.estimate),
      ],
    );
  }

  // ── FAQ ──
  Widget _faqSection() {
    final qa = [
      (tr('Adet nasıl başlatılır/bitirilir?'),
          tr('Takvimde bir güne dokun, gün panelinden "Adet başlat" ile başlat; '
              'sonraki günlerde "Adeti burada bitir" ile aralığı işaretle.')),
      (tr('Adet nasıl düzeltilir/silinir?'),
          tr('Adet gününe dokun → "Adet günü değil" ile kaldır; ya da kaydı '
              'panelden "Sil" ile tamamen sil.')),
      (tr('Doğurganlık neden görünmüyor?'),
          tr('Tahminler ilk adetini kaydedince başlar. Doğum sonrası ilk '
              'döngülerde değişken olabilir; 3+ döngü biriktikçe güçlenir.')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(tr('Sık sorulanlar').toUpperCaseTr(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: AppColors.muted)),
        ),
        for (var i = 0; i < qa.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                color: AppColors.roseBg, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() =>
                    _faqOpen.contains(i) ? _faqOpen.remove(i) : _faqOpen.add(i)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                      child: Text(qa[i].$1,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.roseD)),
                    ),
                    Icon(
                        _faqOpen.contains(i)
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: AppColors.roseD),
                  ]),
                ),
              ),
              if (_faqOpen.contains(i))
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(qa[i].$2,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            height: 1.5,
                            color: AppColors.ink2)),
                  ),
                ),
            ]),
          ),
      ],
    );
  }

  // ── Seçili gün paneli ──
  Widget _dayPanel(
      Map<String, CycleEntry> byDay, CycleStatus status, CycleSettings settings) {
    final entry = byDay[_key(_selected)];
    final isToday = _same(_selected, DateTime.now());
    final pos = _cyclePosition(_selected, status);
    final chance = _pregChance(_selected, status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppColors.softShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    isToday
                        ? '${fmtDayMonth(_selected)} — ${tr('Bugün')}'
                        : fmtDayMonthYear(_selected),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              GestureDetector(
                onTap: () => showCycleEntrySheet(context, ref,
                    date: _selected,
                    existing: entry,
                    lochiaMode: status.mode != CycleMode.active),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: AppColors.roseBg,
                      borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(entry == null ? Icons.add_rounded : Icons.edit_outlined,
                        size: 15, color: AppColors.roseD),
                    const SizedBox(width: 5),
                    Text(entry == null ? tr('Ekle') : tr('Düzenle'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.roseD)),
                  ]),
                ),
              ),
            ],
          ),
          if (pos != null) ...[
            const SizedBox(height: 3),
            Text(pos,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ],
          if (chance != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: chance.$2, shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Text('${tr('Gebe kalma olasılığı')}: ${chance.$1}',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800, color: chance.$2)),
            ]),
          ],
          _markersInfo(byDay, status),
          const SizedBox(height: 12),
          _periodAction(byDay),
          // Çok-günlü "günlere dokun" düzenleme takvimi (Flo/My Calendar pariteti):
          // başlangıca dokun → adet otomatik dolar, işaretliye dokun → çıkar. Loşia
          // modunda gizli (o modda adet düzenlemesi anlamsız).
          if (status.mode != CycleMode.lochia) ...[
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showCyclePeriodAdjustSheet(
                context, ref,
                settings: settings,
                entries: byDay.values.toList(),
                autoFillDays: status.avgPeriodDays,
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.edit_calendar_rounded, size: 15, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(tr('Regl tarihlerini düzenle'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted)),
              ]),
            ),
          ],
          if (entry == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('Bu gün için kayıt yok.'),
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
            )
          else
            _entryDetail(entry),
        ],
      ),
    );
  }

  /// Seçili güne tıklanınca: O hücredeki işaretlerin ne anlama geldiğini açıklar
  /// (renk dolgusu + köşe ikonları). Acemi kullanıcı takvimi okuyabilsin diye.
  Widget _markersInfo(Map<String, CycleEntry> byDay, CycleStatus status) {
    final d = _dOnly(_selected);
    final kind = _kindOf(d, byDay, status);
    final isOvu = status.mode == CycleMode.active &&
        status.ovulationDay != null &&
        _same(d, status.ovulationDay!);
    final e = byDay[_key(d)];

    Widget sw(Color bg, {Color? border}) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: border == null ? null : Border.all(color: border, width: 1.5)));
    Widget dot(Color c) => Center(
        child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)));

    final rows = <(Widget, String)>[];
    // 1) Hücre dolgusu (renk).
    if (kind == 'period') {
      rows.add((sw(AppColors.rose), tr('Adet günü')));
    } else if (kind == 'pred') {
      rows.add((sw(AppColors.roseBg, border: AppColors.rose), tr('Tahmini adet günü')));
    } else if (kind == 'lochia') {
      rows.add((sw(AppColors.lochiaBg, border: AppColors.lochia),
          tr('Loşia — doğum sonrası kanama')));
    }
    // 2) Yumurtlama / doğurganlık işareti (sol alt).
    if (isOvu) {
      rows.add((dot(AppColors.gold), tr('Yumurtlama günü — en yüksek doğurganlık')));
    } else if (kind == 'frt') {
      rows.add((Icon(Icons.eco_rounded, size: 15, color: AppColors.sageD),
          tr('Doğurgan gün')));
    }
    // 3) Kayıt ikonları (sağ alt).
    if (e?.flow != null) {
      rows.add((Icon(Icons.water_drop_rounded, size: 14, color: flowColor(e!.flow!)),
          '${tr('Akış kaydı')}: ${flowLabel(e.flow!)}'));
    }
    if ((e?.symptoms.isNotEmpty ?? false) || e?.mood != null) {
      rows.add((dot(AppColors.roseD), tr('Belirti / ruh hali kaydı')));
    }
    if (e?.note != null && e!.note!.isNotEmpty) {
      rows.add((Icon(Icons.sticky_note_2_rounded, size: 14, color: AppColors.muted),
          tr('Not eklenmiş')));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Bu gündeki işaretler').toUpperCaseTr(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: AppColors.muted)),
          const SizedBox(height: 7),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 18, height: 18, child: Center(child: r.$1)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(r.$2,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  /// Gebe kalma olasılığı (My Calendar "Chance of getting pregnant" pariteti).
  /// Kademelendirme motorda ([conceptionChance]) — Bugün ekranıyla tek kaynak.
  (String, Color)? _pregChance(DateTime day, CycleStatus status) {
    if (status.mode != CycleMode.active) return null;
    return switch (conceptionChance(day, status)) {
      ConceptionChance.veryHigh => (tr('Çok yüksek'), AppColors.gold),
      ConceptionChance.high => (tr('Yüksek'), AppColors.sageD),
      ConceptionChance.medium => (tr('Orta'), AppColors.sage),
      ConceptionChance.low => (tr('Düşük'), AppColors.muted),
    };
  }

  // ── My Calendar pariteli: takvimden adet başlat / burada bitir / kaldır ──
  Widget _periodAction(Map<String, CycleEntry> byDay) {
    final sel = _dOnly(_selected);
    final selEntry = byDay[_key(sel)];
    final selIsPeriod = selEntry?.isPeriod ?? false;
    final start = selIsPeriod ? null : _ongoingStart(sel, byDay);

    final String label;
    final IconData icon;
    final VoidCallback onTap;
    if (selIsPeriod) {
      label = tr('Adet günü değil');
      icon = Icons.close_rounded;
      onTap = () => _unmarkPeriod(sel, selEntry!);
    } else if (start != null) {
      label = tr('Adeti burada bitir');
      icon = Icons.water_drop_outlined;
      onTap = () => _fillPeriod(start, sel, byDay);
    } else {
      label = tr('Adet başlat');
      icon = Icons.water_drop_rounded;
      onTap = () => _markPeriodDay(sel, selEntry);
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.roseBg, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: AppColors.roseD),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.roseD)),
        ]),
      ),
    );
  }

  DateTime? _ongoingStart(DateTime sel, Map<String, CycleEntry> byDay) {
    for (var i = 1; i <= 12; i++) {
      final d = cycleAddDays(sel, -i);
      final e = byDay[_key(d)];
      if (e != null && e.isPeriod) {
        var s = d;
        while (true) {
          final prev = cycleAddDays(s, -1);
          final pe = byDay[_key(prev)];
          if (pe != null && pe.isPeriod) {
            s = prev;
          } else {
            break;
          }
        }
        return s;
      }
    }
    return null;
  }

  Future<void> _savePeriod(DateTime d, CycleEntry? existing) =>
      ref.read(cycleRepositoryProvider).saveEntry(CycleEntry(
            id: existing?.id ?? '',
            date: _dOnly(d),
            flow: (existing != null && existing.isPeriod)
                ? existing.flow
                : FlowLevel.medium,
            lochiaColor: existing?.lochiaColor,
            symptoms: existing?.symptoms ?? const [],
            mood: existing?.mood,
            note: existing?.note,
          ));

  Future<void> _markPeriodDay(DateTime d, CycleEntry? existing) async {
    try {
      await _savePeriod(d, existing);
      _afterEdit(tr('Adet başlangıcı kaydedildi'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _fillPeriod(
      DateTime start, DateTime end, Map<String, CycleEntry> byDay) async {
    try {
      var d = start;
      while (!d.isAfter(end)) {
        await _savePeriod(d, byDay[_key(d)]);
        d = cycleAddDays(d, 1);
      }
      _afterEdit(tr('Adet günleri işaretlendi'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _unmarkPeriod(DateTime d, CycleEntry e) async {
    final hasOther = e.lochiaColor != null ||
        e.symptoms.isNotEmpty ||
        e.mood != null ||
        (e.note?.isNotEmpty ?? false);
    try {
      if (hasOther) {
        await ref.read(cycleRepositoryProvider).saveEntry(CycleEntry(
              id: e.id,
              date: _dOnly(d),
              flow: null,
              lochiaColor: e.lochiaColor,
              symptoms: e.symptoms,
              mood: e.mood,
              note: e.note,
            ));
      } else {
        await ref.read(cycleRepositoryProvider).deleteEntry(e.id);
      }
      _afterEdit(tr('Adet günü kaldırıldı'));
    } catch (err) {
      if (mounted) showAdError(context, apiErrorText(err));
    }
  }

  void _afterEdit(String msg) {
    ref.invalidate(cycleEntriesProvider);
    ref.invalidate(cycleSettingsProvider); // ilk adet → mod değişebilir
    if (mounted) showAdToast(context, msg);
  }

  Widget _entryDetail(CycleEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.flow != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Container(
                width: 20,
                height: 20,
                decoration:
                    BoxDecoration(color: flowColor(entry.flow!), shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Text('${tr('Akış')}: ${flowLabel(entry.flow!)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
        ],
        if (entry.lochiaColor != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    color: lochiaSwatch(entry.lochiaColor!),
                    borderRadius: BorderRadius.circular(6))),
            const SizedBox(width: 10),
            Text('${tr('Loşia rengi')}: ${lochiaLabel(entry.lochiaColor!)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
        ],
        if (entry.symptoms.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (final s in entry.symptoms)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                decoration: BoxDecoration(
                    color: redFlagSymptoms.contains(s)
                        ? AppColors.feverBg
                        : AppColors.roseBg,
                    borderRadius: BorderRadius.circular(999)),
                child: Text(symptomLabel(s),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: redFlagSymptoms.contains(s)
                            ? AppColors.coralDd
                            : AppColors.roseD)),
              ),
          ]),
        ],
        if (entry.mood != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Text(moodEmojis[(entry.mood! - 1).clamp(0, 4)],
                style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(moodLabel(entry.mood!),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
          ]),
        ],
        if (entry.note != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.cream, borderRadius: BorderRadius.circular(12)),
            child: Text('"${entry.note!}"',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.ink2)),
          ),
        ],
        const SizedBox(height: 14),
        AdSaveButton(
            label: tr('Sil'),
            color: AppColors.coralDd,
            ghost: true,
            onTap: () => _confirmDelete(entry)),
      ],
    );
  }

  String? _cyclePosition(DateTime day, CycleStatus status) {
    if (status.mode != CycleMode.active || status.spans.isEmpty) return null;
    final d = _dOnly(day);
    for (var i = status.spans.length - 1; i >= 0; i--) {
      final s = status.spans[i];
      if (!d.isBefore(s.start) &&
          (s.length == null || d.isBefore(cycleAddDays(s.start, s.length!)))) {
        final dayIn = d.difference(s.start).inDays + 1;
        return trp('Döngü {c} · {d}. gün', {'c': i + 1, 'd': dayIn});
      }
    }
    return null;
  }

  Future<void> _confirmDelete(CycleEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Kaydı sil')),
        content: Text(tr('Bu güne ait kayıt silinsin mi? Geri alınamaz.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Vazgeç'),
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Sil'),
                  style: const TextStyle(
                      color: AppColors.coralDd, fontWeight: FontWeight.w900))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(cycleRepositoryProvider).deleteEntry(entry.id);
      ref.invalidate(cycleEntriesProvider);
      if (mounted) showAdToast(context, tr('Silindi'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }
}
