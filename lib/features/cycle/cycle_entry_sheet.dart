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
import 'cycle_widgets.dart';

/// Ekran 4 — Kayıt sheet'i (sekmeli). Gün başına tek kayıt; varsa düzenler.
Future<void> showCycleEntrySheet(
  BuildContext context,
  WidgetRef ref, {
  DateTime? date,
  CycleEntry? existing,
  bool lochiaMode = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _CycleEntrySheet(
        date: date ?? DateTime.now(),
        existing: existing,
        lochiaMode: lochiaMode,
      ),
    ),
  );
}

class _CycleEntrySheet extends ConsumerStatefulWidget {
  final DateTime date;
  final CycleEntry? existing;
  final bool lochiaMode;
  const _CycleEntrySheet(
      {required this.date, this.existing, required this.lochiaMode});

  @override
  ConsumerState<_CycleEntrySheet> createState() => _CycleEntrySheetState();
}

class _CycleEntrySheetState extends ConsumerState<_CycleEntrySheet> {
  late DateTime _date;
  String _tab = 'flow';
  FlowLevel? _flow;
  LochiaColor? _lochia;
  late Set<String> _symptoms;
  int? _mood;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = DateTime(widget.date.year, widget.date.month, widget.date.day);
    _flow = e?.flow;
    _lochia = e?.lochiaColor;
    _symptoms = {...?e?.symptoms};
    _mood = e?.mood;
    _note.text = e?.note ?? '';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: tr('Tarih seç'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final entry = CycleEntry(
      id: widget.existing?.id ?? '',
      date: _date,
      flow: _flow,
      lochiaColor: _lochia,
      symptoms: _symptoms.toList(),
      mood: _mood,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    try {
      await ref.read(cycleRepositoryProvider).saveEntry(entry);
      ref.invalidate(cycleEntriesProvider);
      if (!mounted) return;
      final flags = _symptoms.where(redFlagSymptoms.contains).toList();
      Navigator.pop(context);
      showAdToast(context, tr('Kaydedildi'));
      if (flags.isNotEmpty) showCycleRedFlag(context, flags);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickDate,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.roseBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.rose, width: 1.4),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 14, color: AppColors.roseD),
                          const SizedBox(width: 8),
                          Text(fmtDayMonthYear(_date),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.roseD)),
                          const Spacer(),
                          Text(tr('değiştir'),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.roseD)),
                        ],
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('İptal'),
                      style:
                          TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AdTabs(
              options: {
                'flow': tr('Akış'),
                'symptoms': tr('Belirtiler'),
                'journal': tr('Günlük'),
              },
              selected: _tab,
              onSelect: (k) => setState(() => _tab = k),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: switch (_tab) {
                  'flow' => _flowTab(),
                  'symptoms' => _symptomsTab(),
                  _ => _journalTab(),
                },
              ),
            ),
            const SizedBox(height: 14),
            _saving
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
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {String? info}) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Row(
          children: [
            Text(text.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.muted,
                    letterSpacing: 0.4)),
            if (info != null) ...[
              const SizedBox(width: 6),
              AdInfoDot(title: text, body: info),
            ],
          ],
        ),
      );

  Widget _flowTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(tr('Akış miktarı'), info: CycleInfo.flowAmount),
        Row(
          children: [
            for (final f in FlowLevel.values) ...[
              if (f != FlowLevel.values.first) const SizedBox(width: 7),
              Expanded(child: _flowTile(f)),
            ],
          ],
        ),
        if (widget.lochiaMode) ...[
          const SizedBox(height: 18),
          _label(tr('Lohusalık kanaması rengi'), info: CycleInfo.lochiaColorInfo),
          Row(
            children: [
              for (final c in LochiaColor.values) ...[
                if (c != LochiaColor.values.first) const SizedBox(width: 8),
                Expanded(child: _lochiaTile(c)),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _flowTile(FlowLevel f) {
    final on = _flow == f;
    return GestureDetector(
      onTap: () => setState(() => _flow = on ? null : f),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        decoration: BoxDecoration(
          color: on ? AppColors.roseBg : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: on ? AppColors.rose : AppColors.line, width: 2),
        ),
        child: Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration:
                  BoxDecoration(color: flowColor(f), shape: BoxShape.circle),
            ),
            const SizedBox(height: 7),
            Text(flowLabel(f),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _lochiaTile(LochiaColor c) {
    final on = _lochia == c;
    return GestureDetector(
      onTap: () => setState(() => _lochia = on ? null : c),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: lochiaSwatch(c),
              borderRadius: BorderRadius.circular(12),
              boxShadow: on
                  ? [BoxShadow(color: AppColors.rose, blurRadius: 0, spreadRadius: 2.5)]
                  : null,
            ),
          ),
          const SizedBox(height: 5),
          Text(lochiaLabel(c),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _symptomsTab() {
    Widget chip(String key, String label, {bool danger = false}) {
      final on = _symptoms.contains(key);
      return GestureDetector(
        onTap: () => setState(
            () => on ? _symptoms.remove(key) : _symptoms.add(key)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on
                ? (danger ? AppColors.feverBg : AppColors.roseBg)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on
                    ? (danger ? AppColors.coralDd : AppColors.rose)
                    : AppColors.line,
                width: 1.6),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: on
                      ? (danger ? AppColors.coralDd : AppColors.roseD)
                      : AppColors.ink2)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(tr('Belirtiler')),
        Wrap(
          spacing: 7,
          runSpacing: 8,
          children: [
            for (final s in cycleSymptoms) chip(s.$1, tr(s.$2)),
          ],
        ),
        const SizedBox(height: 18),
        _label(tr('Dikkat belirtileri'), info: CycleInfo.lochiaVsPeriod),
        Wrap(
          spacing: 7,
          runSpacing: 8,
          children: [
            for (final s in cycleRedFlagItems) chip(s.$1, tr(s.$2), danger: true),
          ],
        ),
      ],
    );
  }

  Widget _journalTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(tr('Ruh hali')),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: () => setState(() => _mood = _mood == i ? null : i),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _mood == i ? AppColors.roseBg : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _mood == i ? AppColors.rose : Colors.transparent,
                        width: 2),
                  ),
                  child: Text(moodEmojis[i - 1],
                      style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _label(tr('Not')),
        AdInput(
          controller: _note,
          hint: tr('örn. yorgunluk azaldı, iyi hissediyorum'),
          capitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }
}
