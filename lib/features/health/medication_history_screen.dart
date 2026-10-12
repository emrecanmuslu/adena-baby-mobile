import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/medication.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../data/record_repository.dart';
import '../../models/medication_plan.dart';
import '../../models/record.dart';
import 'medication_widgets.dart';

/// Geçmiş penceresinin kayıtları (son 31 gün; bugünden geriye) — canlı.
final _historyRecordsProvider =
    StreamProvider.autoDispose.family<List<Record>, String>((ref, babyId) {
  final now = DateTime.now();
  return ref
      .watch(recordRepositoryProvider)
      .watchSince(babyId, DateTime(now.year, now.month, now.day - 31));
});

/// K11 — plan başına doz geçmişi (son 7 / 30 gün): verildi (kim, saat),
/// atlandı (neden), kaçırıldı, çift işaretlenmiş; duraklatılan günler ve
/// zamanlama değişikliği öncesi (yalnız kayıtlar) ayrıca belirtilir.
class MedicationHistoryScreen extends ConsumerStatefulWidget {
  final String babyId;
  final int planId;
  const MedicationHistoryScreen({super.key, required this.babyId, required this.planId});

  @override
  ConsumerState<MedicationHistoryScreen> createState() => _MedicationHistoryScreenState();
}

class _MedicationHistoryScreenState extends ConsumerState<MedicationHistoryScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(medicationPlansProvider(widget.babyId)).asData?.value;
    final records = ref.watch(_historyRecordsProvider(widget.babyId)).asData?.value;
    final plan = plans?.where((p) => p.id == widget.planId).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(plan?.name ?? tr('Doz geçmişi'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: plan == null || records == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.coral))
          : _body(context, plan, records),
    );
  }

  Widget _body(BuildContext context, MedicationPlan plan, List<Record> records) {
    final now = DateTime.now();
    final to = DateTime(now.year, now.month, now.day);
    final from = DateTime(to.year, to.month, to.day - (_days - 1));
    final h = medicationHistory(plan, records, from: from, to: to, now: now);
    final muted = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        AdTabs(
          options: {'7': tr('7 gün'), '30': tr('30 gün')},
          selected: '$_days',
          onSelect: (v) => setState(() => _days = int.parse(v)),
        ),
        const SizedBox(height: 12),
        Text(
            plan.isPrn
                ? trp('{n} kez verildi', {'n': h.prnGiven})
                : trp('{g} verildi · {s} atlandı · {m} kaçırıldı · {x} çift', {
                    'g': h.given,
                    's': h.skipped,
                    'm': h.missed,
                    'x': h.multiple,
                  }),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        for (final d in h.days) ..._day(d, muted),
      ],
    );
  }

  List<Widget> _day(MedHistoryDay d, TextStyle muted) {
    final head = Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(fmtDayMonth(d.day),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
    );
    final rows = <Widget>[
      for (final dose in d.doses) _doseRow(dose, muted),
      for (final r in d.extra) _recordRow(r, muted, extra: true),
    ];
    if (d.paused && d.doses.isEmpty) rows.add(Text(tr('Duraklatıldı'), style: muted));
    if (rows.isEmpty) rows.add(Text(tr('Planlanmış doz yok'), style: muted));
    return [head, ...rows];
  }

  Widget _line(String icon, Color color, String title, String meta, TextStyle muted) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdenaIcon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  if (meta.isNotEmpty) Text(meta, style: muted),
                ],
              ),
            ),
          ],
        ),
      );

  String _who(Record r) => medWhoName(ref, widget.babyId, r);

  Widget _doseRow(MedicationDose d, TextStyle muted) {
    if (d.multiple) {
      return _line(
          'shieldAlert',
          AppColors.coralDd,
          trp('{t} · {n} kez verildi', {'t': d.time, 'n': d.givenRecords.length}),
          d.givenRecords.map((r) => '${_who(r)} ${fmtTime(r.ts)}').join(' · '),
          muted);
    }
    return switch (d.status) {
      MedicationDoseStatus.given => _line('check', AppColors.growth,
          trp('{t} · verildi', {'t': d.time}), '${_who(d.record!)} · ${fmtTime(d.record!.ts)}', muted),
      MedicationDoseStatus.skipped => _line(
          'close',
          AppColors.muted,
          trp('{t} · atlandı', {'t': d.time}),
          [_who(d.record!), ?medSkipReasonText(d.record!)].join(' · '),
          muted),
      MedicationDoseStatus.missed =>
        _line('close', AppColors.coralDd, trp('{t} · kaçırıldı', {'t': d.time}), '', muted),
      MedicationDoseStatus.overdue =>
        _line('clock', AppColors.coral, trp('{t} · saati geçti', {'t': d.time}), '', muted),
      MedicationDoseStatus.upcoming =>
        _line('clock', AppColors.muted, trp('{t} · bekliyor', {'t': d.time}), '', muted),
    };
  }

  Widget _recordRow(Record r, TextStyle muted, {bool extra = false}) {
    final skipped = r.data['skipped'] == true;
    return _line(
      skipped ? 'close' : 'check',
      skipped ? AppColors.muted : AppColors.growth,
      skipped ? trp('{t} · atlandı', {'t': fmtTime(r.ts)}) : trp('{t} · verildi', {'t': fmtTime(r.ts)}),
      _who(r),
      muted,
    );
  }
}
