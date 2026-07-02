import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';

/// My Calendar "Tap on date to adjust your period" pariteli **adet ayarlama takvimi**.
/// Hero butonunun ("Adeti başlat" / "Adeti düzenle") arkasında açılır: dikey aylık
/// takvimde günlere dokunarak adet (kanama) günlerini işaretle/kaldır → Kaydet.
///
/// Davranış (MYCALENDAR_INCELEME.md S11/S12):
///  • İşaretli güne dokun → o gün çıkar (tek-gün toggle; kuyruğu silmek = adeti bitir).
///  • Boş güne dokun → o gün eklenir (bitişiklerle birleşip aralık oluşur).
///  • Gelecek günler kilitli (soluk, seçilemez).
///  • [startDate] verilirse (başlatma modu) o gün ön-seçili gelir.
///  • Değişiklik varken kapatınca "Değişiklikleri kaydet?" onayı.
///
/// Flo/My Calendar pariteti: boş bir güne dokununca (yeni başlangıç) o gün
/// [autoFillDays] kadar (ortalama adet süresi) OTOMATİK dolar → tek dokunuşla
/// tam adet loglanır (tek gün değil). Bitişik bir güne dokunmak tek-gün ekler;
/// işaretli güne dokunmak çıkarır (uzat/kısalt). Gelecek günler kilitli (yalnız
/// ≤bugün dolar). Kaydet'te ilk-adet çapası (firstPeriodDate) yeniden hesaplanır.
Future<bool> showCyclePeriodAdjustSheet(
  BuildContext context,
  WidgetRef ref, {
  required CycleSettings settings,
  required List<CycleEntry> entries,
  DateTime? startDate,
  int autoFillDays = 5,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: adSheetShape,
    constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92),
    builder: (ctx) => _PeriodAdjustSheet(
      settings: settings,
      entries: entries,
      startDate: startDate,
      autoFillDays: autoFillDays,
    ),
  );
  return saved ?? false;
}

class _PeriodAdjustSheet extends ConsumerStatefulWidget {
  final CycleSettings settings;
  final List<CycleEntry> entries;
  final DateTime? startDate;
  final int autoFillDays;
  const _PeriodAdjustSheet({
    required this.settings,
    required this.entries,
    this.startDate,
    this.autoFillDays = 5,
  });

  @override
  ConsumerState<_PeriodAdjustSheet> createState() => _PeriodAdjustSheetState();
}

class _PeriodAdjustSheetState extends ConsumerState<_PeriodAdjustSheet> {
  late final DateTime _today;
  late final Set<DateTime> _marked; // adet (kanama) günleri
  late final Set<DateTime> _original; // başlangıç durumu (diff için)
  late final List<DateTime> _months; // eski→yeni (gösterilen aylar)
  final _scroll = ScrollController();
  final _currentMonthKey = GlobalKey(); // mevcut ayı açılışta en üste hizalamak için
  bool _saving = false;

  DateTime _dOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _today = _dOnly(DateTime.now());
    _original = {
      for (final e in widget.entries)
        if (e.isPeriod) _dOnly(e.date),
    };
    _marked = {..._original};
    final s = widget.startDate;
    // Başlatma modu: verilen günden itibaren ortalama adet süresi kadar otomatik
    // doldur (gelecek günler hariç) → tek dokunuşta tam adet, "1 günlük adet" bug'ı yok.
    if (s != null) _fill(_dOnly(s));

    // Önceki + mevcut + sonraki ay (My Calendar dikey takvimi gibi). Sonraki ay
    // tümüyle gelecek → soluk/kilitli, sadece kaydırma boşluğu sağlar; bu boşluk
    // sayesinde mevcut ay açılışta en ÜSTE hizalanabilir (başlıksız kuyruk görünmez).
    // Önceki ay ay-sınırını aşan adetleri işaretlemeye yeter; daha eskisi Takvim'de.
    final base = DateTime(_today.year, _today.month, 1);
    _months = [
      DateTime(base.year, base.month - 1, 1),
      base,
      DateTime(base.year, base.month + 1, 1),
    ];

    // Açılışta mevcut ayı viewport'un en üstüne hizala.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _currentMonthKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _dirty {
    if (_marked.length != _original.length) return true;
    for (final d in _marked) {
      if (!_original.contains(d)) return true;
    }
    return false;
  }

  /// [d]'den itibaren ortalama adet süresi kadar ardışık günü işaretle; gelecek
  /// (>bugün) günleri atla. setState DIŞINDA çağrılır (initState / _toggle içi).
  void _fill(DateTime d) {
    final n = widget.autoFillDays.clamp(1, 10);
    for (var i = 0; i < n; i++) {
      final day = d.add(Duration(days: i));
      if (day.isAfter(_today)) break;
      _marked.add(day);
    }
  }

  void _toggle(DateTime d) {
    if (d.isAfter(_today)) return; // gelecek kilitli
    final adjacent = _marked.contains(d.subtract(const Duration(days: 1))) ||
        _marked.contains(d.add(const Duration(days: 1)));
    setState(() {
      if (_marked.contains(d)) {
        _marked.remove(d); // işaretliyi çıkar (kısalt/bitir)
      } else if (adjacent) {
        _marked.add(d); // mevcut adete bitişik → tek gün uzat
      } else {
        _fill(d); // yalıtık boş gün → yeni adet başlangıcı, otomatik doldur
      }
    });
  }

  /// İşaretli günün, ait olduğu bitişik blok içindeki sırası (1-based) — köşe no.
  int _periodDayNum(DateTime d) {
    var start = d;
    while (_marked.contains(start.subtract(const Duration(days: 1)))) {
      start = start.subtract(const Duration(days: 1));
    }
    return d.difference(start).inDays + 1;
  }

  int _colOf(DateTime d, bool sunday) =>
      sunday ? d.weekday % 7 : (d.weekday - 1) % 7;

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(cycleRepositoryProvider);
    final byDay = {for (final e in widget.entries) _dOnly(e.date): e};
    final toAdd = _marked.difference(_original);
    final toRemove = _original.difference(_marked);
    try {
      for (final d in toAdd) {
        final existing = byDay[d];
        await repo.saveEntry(CycleEntry(
          id: existing?.id ?? '',
          date: d,
          flow: (existing != null && existing.isPeriod)
              ? existing.flow
              : FlowLevel.medium,
          lochiaColor: existing?.lochiaColor,
          symptoms: existing?.symptoms ?? const [],
          mood: existing?.mood,
          note: existing?.note,
        ));
      }
      for (final d in toRemove) {
        final existing = byDay[d];
        if (existing == null) continue;
        final hasOther = existing.lochiaColor != null ||
            existing.symptoms.isNotEmpty ||
            existing.mood != null ||
            (existing.note?.isNotEmpty ?? false);
        if (hasOther) {
          // Adet dışı veriyi koru, yalnız akışı temizle.
          await repo.saveEntry(CycleEntry(
            id: existing.id,
            date: d,
            flow: null,
            lochiaColor: existing.lochiaColor,
            symptoms: existing.symptoms,
            mood: existing.mood,
            note: existing.note,
          ));
        } else {
          await repo.deleteEntry(existing.id);
        }
      }
      // İlk-adet çapası (firstPeriodDate) bakımı: adet günleri değişince çapa en
      // erken işaretli güne eşitlenir; hiç adet kalmadıysa null → bekleme moduna
      // döner. Bu olmadan silinen adette çapa bayat kalıp tahmini bozardı (bug #2).
      final newAnchor =
          _marked.isEmpty ? null : (_marked.toList()..sort()).first;
      final curAnchor = widget.settings.firstPeriodDate;
      final curD = curAnchor == null ? null : _dOnly(curAnchor);
      if (newAnchor != curD) {
        await repo.patchSettings(
            {'first_period_date': newAnchor == null ? null : _iso(newAnchor)});
      }
      ref.invalidate(cycleEntriesProvider);
      ref.invalidate(cycleSettingsProvider); // ilk adet → mod değişebilir
      if (!mounted) return;
      Navigator.pop(context, true);
      showAdToast(context, tr('Kaydedildi'));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  Future<void> _close() async {
    if (!_dirty) {
      Navigator.pop(context, false);
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: adSheetShape,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: adGrabHandle()),
            const SizedBox(height: 6),
            Text(tr('Değişiklikleri kaydet?'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, 'discard'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.cream,
                        borderRadius: BorderRadius.circular(14)),
                    child: Text(tr('Vazgeç'),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.muted)),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, 'save'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.rose,
                        borderRadius: BorderRadius.circular(14)),
                    child: Text(tr('Kaydet'),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      await _save();
    } else if (action == 'discard') {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sunday = widget.settings.weekStartsSunday;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          adGrabHandle(),
          // ── başlık çubuğu ──
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(children: [
              IconButton(
                onPressed: _saving ? null : _close,
                icon: Icon(Icons.close_rounded, color: AppColors.muted),
              ),
              Expanded(
                child: Text(tr('Adet günlerini düzenle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 48),
            ]),
          ),
          // ── ipucu şeridi ──
          Container(
            width: double.infinity,
            color: AppColors.roseBg,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.water_drop_rounded, size: 15, color: AppColors.roseD),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                    tr('Başlangıç gününe dokun → adet otomatik dolar; işaretliye dokun = kaldır'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.roseD)),
              ),
            ]),
          ),
          _weekHeader(sunday),
          // ── dikey aylık takvim ──
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                for (var i = 0; i < _months.length; i++)
                  KeyedSubtree(
                    key: i == 1 ? _currentMonthKey : null,
                    child: _monthGrid(_months[i], sunday),
                  ),
              ],
            ),
          ),
          // ── Kaydet ──
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: _saving
                ? FilledButton(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.rose,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    child: const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white)),
                  )
                : AdSaveButton(
                    label: tr('Kaydet'), color: AppColors.rose, onTap: _save),
          ),
        ],
      ),
    );
  }

  Widget _weekHeader(bool sunday) {
    final base = [
      tr('Pzt'), tr('Sal'), tr('Çar'), tr('Per'), tr('Cum'), tr('Cmt'), tr('Paz')
    ];
    final labels = sunday ? [base[6], ...base.sublist(0, 6)] : base;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Text(labels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted)),
          ),
      ]),
    );
  }

  Widget _monthGrid(DateTime month, bool sunday) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = _colOf(DateTime(month.year, month.month, 1), sunday);
    final cells = <DateTime?>[
      ...List.filled(lead, null),
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rows = [
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(fmtMonthYear(month),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [for (final d in row) _dayCell(d)]),
          ),
      ],
    );
  }

  Widget _dayCell(DateTime? d) {
    if (d == null) return const Expanded(child: SizedBox(height: 62));
    final isFuture = d.isAfter(_today);
    final marked = _marked.contains(d);
    final isToday = d == _today;
    final numColor = isFuture
        ? AppColors.muted2
        : (marked ? AppColors.roseD : AppColors.ink);

    Widget circle;
    if (marked) {
      circle = Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: AppColors.rose, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
      );
    } else {
      circle = Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: isFuture ? AppColors.line2 : AppColors.line, width: 1.6),
        ),
      );
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isFuture ? null : () => _toggle(d),
        child: SizedBox(
          height: 62,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 13,
                child: isToday
                    ? Text(tr('BUGÜN'),
                        style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            color: AppColors.roseD))
                    : Text('${d.day}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight:
                                isToday ? FontWeight.w900 : FontWeight.w700,
                            color: numColor)),
              ),
              const SizedBox(height: 2),
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  circle,
                  if (isToday && !marked)
                    Text('${d.day}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: numColor)),
                  if (marked)
                    Positioned(
                      top: -3,
                      right: 2,
                      child: Text('${_periodDayNum(d)}',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink2)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
