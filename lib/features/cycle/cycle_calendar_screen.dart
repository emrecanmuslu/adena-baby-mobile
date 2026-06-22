import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import 'cycle_engine.dart';
import 'cycle_entry_sheet.dart';
import 'cycle_widgets.dart';

/// Ekran 3 + 5 — Aylık takvim (renk kodlu) + seçili gün detay paneli.
class CycleCalendarScreen extends ConsumerStatefulWidget {
  const CycleCalendarScreen({super.key});

  @override
  ConsumerState<CycleCalendarScreen> createState() => _CycleCalendarScreenState();
}

class _CycleCalendarScreenState extends ConsumerState<CycleCalendarScreen> {
  late DateTime _month; // ayın 1'i
  late DateTime _selected;

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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Takvim')),
      ),
      body: settingsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.coral)),
        error: (e, _) => Center(child: Text(apiErrorText(e))),
        data: (settings) => entriesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: AppColors.coral)),
          error: (e, _) => Center(child: Text(apiErrorText(e))),
          data: (entries) {
            final status = computeStatus(settings, entries);
            final byDay = <String, CycleEntry>{
              for (final e in entries) _key(e.date): e,
            };
            return ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                _monthNav(),
                _weekHeader(),
                _grid(byDay, status),
                const SizedBox(height: 12),
                _legend(),
                const SizedBox(height: 8),
                _dayPanel(byDay[_key(_selected)], status, settings),
              ],
            );
          },
        ),
      ),
    );
  }

  String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _monthNav() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _navBtn(Icons.chevron_left,
                () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1))),
            Text(fmtMonthYear(_month),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            _navBtn(Icons.chevron_right,
                () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1))),
          ],
        ),
      );

  Widget _navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              boxShadow: AppColors.smallShadow),
          child: Icon(icon, size: 18, color: AppColors.ink2),
        ),
      );

  Widget _weekHeader() {
    final days = [
      tr('Pzt'), tr('Sal'), tr('Çar'), tr('Per'), tr('Cum'), tr('Cmt'), tr('Paz')
    ];
    return Row(
      children: [
        for (final d in days)
          Expanded(
            child: Text(d,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.muted)),
          ),
      ],
    );
  }

  Widget _grid(Map<String, CycleEntry> byDay, CycleStatus status) {
    final first = _month;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = (first.weekday - 1) % 7; // Pazartesi başı
    final cells = <DateTime?>[
      ...List.filled(lead, null),
      for (var d = 1; d <= daysInMonth; d++) DateTime(_month.year, _month.month, d),
    ];
    final today = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        children: [
          for (final d in cells)
            if (d == null)
              const SizedBox.shrink()
            else
              _dayCell(d, byDay[_key(d)], status, _same(d, today)),
        ],
      ),
    );
  }

  Widget _dayCell(
      DateTime d, CycleEntry? entry, CycleStatus status, bool isToday) {
    final kind = _dayKind(d, entry, status);
    final sel = _same(d, _selected);
    Color? bg;
    Color fg = AppColors.ink;
    Border? border;
    final hasDot = entry != null;
    switch (kind) {
      case 'per':
        bg = AppColors.rose;
        fg = Colors.white;
      case 'lch':
        bg = AppColors.lochia;
        fg = Colors.white;
      case 'ovul':
        bg = const Color(0xFF9B8CE8);
        fg = Colors.white;
      case 'frt':
        bg = AppColors.sleepBg;
        fg = const Color(0xFF6F5FD6);
      case 'pred':
        border = Border.all(color: AppColors.rose, width: 1.5, style: BorderStyle.solid);
        fg = AppColors.rose;
      default:
        break;
    }
    final cd = _cycleDayNum(d, status);
    final faint = fg == Colors.white ? Colors.white70 : AppColors.muted2;
    return GestureDetector(
      // İlk dokunuş günü seçer; seçili güne tekrar dokunmak kayıt sheet'ini açar
      // (Period Calendar'daki gibi hızlı giriş).
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
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: sel
              ? Border.all(color: AppColors.roseD, width: 2)
              : (kind == 'pred'
                  ? Border.all(color: AppColors.rose, width: 1.4)
                  : border),
          boxShadow:
              isToday ? [BoxShadow(color: AppColors.rose.withValues(alpha: 0.35), blurRadius: 8)] : null,
        ),
        child: Stack(
          children: [
            if (cd != null)
              Positioned(
                top: 2,
                right: 4,
                child: Text('$cd',
                    style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: faint)),
              ),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${d.day}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              kind == null ? FontWeight.w700 : FontWeight.w900,
                          color: fg)),
                  if (hasDot)
                    Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: fg == Colors.white
                                ? Colors.white70
                                : AppColors.roseD)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bir günün renk türü: gerçek kayıt > tahmin. (Tahminler yalnız aktif modda.)
  String? _dayKind(DateTime d, CycleEntry? entry, CycleStatus status) {
    if (entry != null) {
      if (entry.isPeriod) return 'per';
      if (entry.lochiaColor != null) return 'lch';
    }
    if (status.mode == CycleMode.active) {
      final ov = status.ovulationDay;
      if (ov != null && _same(d, ov)) return 'ovul';
      if (status.fertileStart != null &&
          !d.isBefore(_dOnly(status.fertileStart!)) &&
          !d.isAfter(_dOnly(status.fertileEnd!))) {
        return 'frt';
      }
      final np = status.nextPeriod;
      if (np != null) {
        final predEnd = np.add(Duration(days: status.avgPeriodDays - 1));
        if (!d.isBefore(_dOnly(np)) && !d.isAfter(_dOnly(predEnd))) return 'pred';
      }
    }
    return null;
  }

  DateTime _dOnly(DateTime x) => DateTime(x.year, x.month, x.day);

  /// Bir günün döngü-günü numarası (Period Calendar tarzı küçük köşe rozeti).
  /// Geçmiş döngülerde gerçek başlangıçtan, son döngüde/gelecekte ortalama
  /// uzunlukla ileri projeksiyondan hesaplanır. Yalnız aktif modda.
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
        if (!dd.isBefore(nextStart)) continue; // sonraki döngüye ait
        return dd.difference(start).inDays + 1;
      }
      // Son gerçek döngü: bugüne/geleceğe ortalama uzunlukla projekte et.
      final avg = status.avgCycleLength;
      var s = start;
      while (avg > 0 && dd.difference(s).inDays >= avg) {
        s = s.add(Duration(days: avg));
      }
      final n = dd.difference(s).inDays + 1;
      return (n >= 1 && n <= avg + 4) ? n : null;
    }
    return null;
  }

  Widget _legend() {
    final items = [
      (AppColors.rose, tr('Adet'), null),
      (AppColors.lochia, tr('Loşia'), null),
      (const Color(0xFF9B8CE8), tr('Ovülasyon'), null),
      (AppColors.sleepBg, tr('Doğurganlık'), const Color(0xFF9B8CE8)),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final it in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                      color: it.$1,
                      borderRadius: BorderRadius.circular(3),
                      border: it.$3 == null ? null : Border.all(color: it.$3!))),
              const SizedBox(width: 5),
              Text(it.$2,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted)),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: AppColors.rose, width: 1.5))),
            const SizedBox(width: 5),
            Text(tr('Tahmini'),
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted)),
          ],
        ),
        AdInfoDot(title: tr('Takvim renkleri'), body: CycleInfo.estimate),
      ],
    );
  }

  // ── Seçili gün paneli (Ekran 5 — gün detayı) ──
  Widget _dayPanel(CycleEntry? entry, CycleStatus status, CycleSettings settings) {
    final isToday = _same(_selected, DateTime.now());
    final pos = _cyclePosition(_selected, status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
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
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
              GestureDetector(
                onTap: () => showCycleEntrySheet(context, ref,
                    date: _selected,
                    existing: entry,
                    lochiaMode: status.mode != CycleMode.active),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.roseBg,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(entry == null ? tr('Ekle') : tr('Düzenle'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.roseD)),
                ),
              ),
            ],
          ),
          if (pos != null) ...[
            const SizedBox(height: 4),
            Text(pos,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
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

  Widget _entryDetail(CycleEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.flow != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      color: flowColor(entry.flow!), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text('${tr('Akış')}: ${flowLabel(entry.flow!)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
        if (entry.lochiaColor != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                      color: lochiaSwatch(entry.lochiaColor!),
                      borderRadius: BorderRadius.circular(6))),
              const SizedBox(width: 10),
              Text('${tr('Loşia rengi')}: ${lochiaLabel(entry.lochiaColor!)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
        ],
        if (entry.symptoms.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
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
            ],
          ),
        ],
        if (entry.mood != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(moodEmojis[(entry.mood! - 1).clamp(0, 4)],
                  style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(moodLabel(entry.mood!),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
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

  /// Aktif modda günün döngüdeki yeri ("Döngü 3 · 14. gün · Folliküler faz").
  String? _cyclePosition(DateTime day, CycleStatus status) {
    if (status.mode != CycleMode.active || status.spans.isEmpty) return null;
    final d = _dOnly(day);
    for (var i = status.spans.length - 1; i >= 0; i--) {
      final s = status.spans[i];
      if (!d.isBefore(s.start) && (s.length == null || d.isBefore(s.start.add(Duration(days: s.length!))))) {
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
