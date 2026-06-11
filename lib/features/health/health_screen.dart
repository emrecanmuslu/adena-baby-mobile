import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/record.dart';
import '../../models/vaccine.dart';
import '../babies/baby_controller.dart';
import '../records/record_controller.dart';
import '../records/record_ui.dart';

/// Sağlık Hub (design ScrHealth): aşı takvimi özeti + doktor randevuları +
/// son ateş & ilaç. Aşı/Hatırlatıcı detaylarına köprü.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final vaccinesAsync = ref.watch(vaccinesProvider(baby.id));
    final records = ref.watch(recordsProvider(baby.id)).asData?.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Sağlık Hub')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Aşı takvimi özeti ──
          _SecHeader(title: tr('TR Aşı Takvimi'), onTap: () => context.push('/vaccines')),
          vaccinesAsync.when(
            loading: () => const Skeleton(height: 120, radius: 16),
            error: (e, _) => _ErrorNote(apiErrorText(e)),
            data: (vaccines) => _VaccineSummary(vaccines: vaccines),
          ),

          // ── Doktor randevuları ──
          const SizedBox(height: 4),
          adSec(tr('Doktor randevuları')),
          _AppointmentSummary(records: records),

          // ── Son ateş & ilaç ──
          adSec(tr('Son ateş & ilaç')),
          _FeverMedSummary(records: records),

          const SizedBox(height: 8),
          // Gelişim / kilometre taşları köprüsü.
          AdMenuItem(
            icon: 'growth',
            color: AppColors.growth,
            bg: AppColors.growthBg,
            title: tr('Gelişim / Kilometre Taşları'),
            meta: tr('Yaşa göre beklenen gelişim basamakları'),
            onTap: () => context.push('/milestones'),
          ),
          // Hatırlatıcılar köprüsü (design'da ayrı ekran; hub'dan erişim).
          AdMenuItem(
            icon: 'bell',
            color: AppColors.coralDd,
            bg: AppColors.feedBg,
            title: tr('Hatırlatıcılar'),
            meta: tr('Vitamin · beslenme · aşı · dürtükleme'),
            onTap: () => context.push('/reminders'),
          ),
        ],
      ),
    );
  }
}

/// "Başlık ··· Tümü ›" — dokununca detay ekranı açan bölüm başlığı.
class _SecHeader extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  const _SecHeader({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(3, 18, 3, 10),
        child: Row(
          children: [
            Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.muted,
                    letterSpacing: 0.7)),
            const Spacer(),
            Text(tr('Tümü'),
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.coralDark)),
            const AdenaIcon('chevR', size: 15, color: AppColors.coralDark),
          ],
        ),
      ),
    );
  }
}

/// En yakın birkaç aşıyı küçük zaman-çizelgesi olarak gösterir (ilk bekleyen vurgulu).
class _VaccineSummary extends StatelessWidget {
  final List<Vaccine> vaccines;
  const _VaccineSummary({required this.vaccines});

  @override
  Widget build(BuildContext context) {
    if (vaccines.isEmpty) {
      return _CardNote(
          tr('Aşı takvimi doğum tarihinden otomatik oluşturulur.'));
    }
    final sorted = [...vaccines]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final firstPending = sorted.where((v) => !v.done).firstOrNull;
    // İlk bekleyen etrafında en fazla 3 aşı (yoksa son 3).
    final List<Vaccine> shown;
    if (firstPending != null) {
      final idx = sorted.indexOf(firstPending);
      final start = (idx - 1).clamp(0, sorted.length);
      shown = sorted.sublist(start, (start + 3).clamp(0, sorted.length));
    } else {
      shown = sorted.sublist((sorted.length - 3).clamp(0, sorted.length));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++)
            _VacMiniRow(
              vaccine: shown[i],
              highlighted: identical(shown[i], firstPending),
              last: i == shown.length - 1,
            ),
        ],
      ),
    );
  }
}

class _VacMiniRow extends StatelessWidget {
  final Vaccine vaccine;
  final bool highlighted;
  final bool last;
  const _VacMiniRow(
      {required this.vaccine, required this.highlighted, required this.last});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM', 'tr_TR');
    final v = vaccine;
    final state = v.done ? 'done' : ((highlighted || v.isOverdue) ? 'due' : 'future');
    final (Color mbg, Color mfg, String icon) = switch (state) {
      'done' => (AppColors.growth, Colors.white, 'check'),
      'due' => (AppColors.coral, Colors.white, 'syringe'),
      _ => (AppColors.line, AppColors.muted, 'clock'),
    };
    final dateText = v.done
        ? tr('Yapıldı')
        : (v.isOverdue
            ? 'Gecikti · ${dateFmt.format(v.dueDate)}'
            : 'Planlanan · ${dateFmt.format(v.dueDate)}');

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 13),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: mbg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: AdenaIcon(icon, size: 15, color: mfg, sw: 2.2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(v.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: v.done ? AppColors.muted : null)),
          ),
          const SizedBox(width: 8),
          Text(dateText,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: state == 'due' ? AppColors.coralDd : AppColors.muted)),
        ],
      ),
    );
  }
}

/// Yaklaşan doktor randevuları (RecordType.appointment, datetime ≥ şimdi).
class _AppointmentSummary extends StatelessWidget {
  final List<Record> records;
  const _AppointmentSummary({required this.records});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = records
        .where((r) => r.type == RecordType.appointment && _apptTime(r).isAfter(now))
        .toList()
      ..sort((a, b) => _apptTime(a).compareTo(_apptTime(b)));

    if (upcoming.isEmpty) {
      return _CardNote(tr('Yaklaşan randevu yok. Kayıt eklerken randevu girebilirsin.'));
    }
    return Column(
      children: [for (final r in upcoming.take(3)) _ApptRow(record: r)],
    );
  }
}

class _ApptRow extends StatelessWidget {
  final Record record;
  const _ApptRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final t = _apptTime(record);
    final title = record.data['title'] as String? ?? tr('Randevu');
    final note = record.data['note'] as String?;
    final whenStr = DateFormat('d MMMM · HH:mm', 'tr_TR').format(t);
    final meta = (note != null && note.isNotEmpty) ? '$whenStr · $note' : whenStr;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          AdIconChip('calendar', color: AppColors.doctor, bg: AppColors.doctorBg),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 2),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Son ateş + son ilaç kaydı (design .ad-entry).
class _FeverMedSummary extends StatelessWidget {
  final List<Record> records;
  const _FeverMedSummary({required this.records});

  @override
  Widget build(BuildContext context) {
    final sorted = [...records]..sort((a, b) => b.ts.compareTo(a.ts));
    final lastFever =
        sorted.where((r) => r.type == RecordType.temperature).firstOrNull;
    final lastMed =
        sorted.where((r) => r.type == RecordType.medication).firstOrNull;

    if (lastFever == null && lastMed == null) {
      return _CardNote(tr('Henüz ateş veya ilaç kaydı yok.'));
    }
    return Column(
      children: [
        if (lastFever != null) _EntryRow(record: lastFever),
        if (lastMed != null) _EntryRow(record: lastMed),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  final Record record;
  const _EntryRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final (title, meta) = _entryText(r);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(RecordUi.time(r.ts),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.muted)),
          ),
          RecordUi.chip(r.type, size: 40, radius: 13),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 1),
                Text(meta,
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardNote extends StatelessWidget {
  final String text;
  const _CardNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String text;
  const _ErrorNote(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
      );
}

DateTime _apptTime(Record r) =>
    DateTime.tryParse(r.data['datetime'] as String? ?? '')?.toLocal() ?? r.ts;

/// Ateş/ilaç kaydı için (başlık, alt-metin).
(String, String) _entryText(Record r) {
  if (r.type == RecordType.temperature) {
    final value = (r.data['value'] as num?)?.toDouble();
    final unit = r.data['unit'] as String? ?? 'C';
    final title = value != null
        ? '${value.toStringAsFixed(1)} °$unit'
        : tr('Ateş');
    final meta = value == null
        ? tr('Ölçüm')
        : (unit == 'C'
            ? (value >= 38 ? tr('yüksek') : (value < 36 ? tr('düşük') : tr('normal aralık')))
            : tr('ölçüm'));
    return (title, meta);
  }
  // medication
  final name = r.data['name'] as String? ?? tr('İlaç');
  final dose = r.data['dose'] as String?;
  final given = r.data['given'] as bool? ?? true;
  final title = (dose != null && dose.isNotEmpty) ? '$name · $dose' : name;
  return (title, given ? tr('verildi') : tr('planlandı'));
}
