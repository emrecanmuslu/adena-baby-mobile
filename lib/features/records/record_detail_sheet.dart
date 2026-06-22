import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../models/record.dart';
import '../../models/symptom.dart';
import '../auth/auth_controller.dart';
import '../babies/family_settings.dart';
import '../babies/members_screen.dart';
import 'delete_record_sheet.dart';
import 'record_form.dart';
import 'record_ui.dart';

/// Bir kaydın SALT-OKUNUR detayını gösterir: timeline özetinde görünmeyen
/// not/doz/alerji-tepki/zamanlama gibi alanları açıkça listeler. İçinden
/// "Düzenle" (form) ve "Sil" (onay sheet'i) erişilir. Düzenleme artık doğrudan
/// dokunma yerine bu sheet'in arkasında — kritik bilgi (alerji vb.) gözden kaçmaz.
Future<void> showRecordDetailSheet(
    BuildContext context, WidgetRef ref, Record record) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => _RecordDetailSheet(record: record),
  );
}

class _RecordDetailSheet extends ConsumerWidget {
  final Record record;
  const _RecordDetailSheet({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(activeUnitsProvider);
    final accent = RecordUi.color(record.type);
    final rows = _rows(record, units);
    final who = _resolveWho(ref);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            // Başlık: kategori çipi + tür + tam tarih/saat.
            Row(children: [
              RecordUi.chip(record.type, size: 38, radius: 13),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(RecordUi.label(record.type),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                    Text(fmtDayMonthTime(record.ts),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(tr('Ek detay yok.'),
                            style: TextStyle(
                                color: AppColors.muted, fontWeight: FontWeight.w600)),
                      )
                    else
                      ...rows,
                    if (who != null) ...[
                      const SizedBox(height: 4),
                      _DetailRow(label: tr('Ekleyen'), value: who),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AdSaveButton(
                    label: tr('Düzenle'),
                    color: accent,
                    ghost: true,
                    onTap: () {
                      Navigator.pop(context);
                      showRecordForm(context, ref, record.baby, record.type,
                          existing: record);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AdSaveButton(
                    label: tr('Sil'),
                    color: AppColors.fever,
                    ghost: true,
                    onTap: () {
                      Navigator.pop(context);
                      showDeleteRecordSheet(context, ref, record);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Türüne göre detay satırları. Boş değerler atlanır. Serbest metin (not,
  /// tepki/alerji) tam genişlik blok; diğerleri etiket+değer satırı.
  List<Widget> _rows(Record r, Units units) {
    final d = r.data;
    final out = <Widget>[];
    void row(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        out.add(_DetailRow(label: label, value: value));
      }
    }

    void note(String label, String? value, {bool highlight = false}) {
      if (value != null && value.trim().isNotEmpty) {
        out.add(_NoteBlock(label: label, value: value, highlight: highlight));
      }
    }

    switch (r.type) {
      case RecordType.diaper:
        row(
            tr('Tür'),
            switch (d['sub']) {
              'pee' => tr('Çiş'),
              'poo' => tr('Kaka'),
              'poopee' => tr('Karışık'),
              _ => tr('Bez'),
            });
        row(tr('Renk / kıvam'), d['stool'] as String?);
      case RecordType.feed:
        switch (d['sub']) {
          case 'breast':
            final l = d['left_min'] is num ? d['left_min'] as num : 0;
            final rt = d['right_min'] is num ? d['right_min'] as num : 0;
            row(tr('Tür'), tr('Anne sütü'));
            row(tr('Toplam süre'), trp('{n} dk', {'n': l + rt}));
            row(tr('Sol (dk)'), '$l');
            row(tr('Sağ (dk)'), '$rt');
          case 'formula':
            row(tr('Tür'), tr('Mama'));
            row(tr('Miktar'), d['ml'] is num ? units.fmtVolume(d['ml'] as num) : null);
          case 'pumped':
            row(tr('Tür'), tr('Sağılmış süt'));
            row(tr('Miktar'), d['ml'] is num ? units.fmtVolume(d['ml'] as num) : null);
          case 'solid':
            row(tr('Tür'), tr('Katı'));
            row(tr('Yiyecek'), d['food_name'] as String?);
            final amt = d['amount'];
            row(tr('Miktar'), amt is num ? trp('{n} kaşık', {'n': amt}) : amt?.toString());
            note(tr('Tepki / alerji notu'), d['reaction'] as String?, highlight: true);
          default:
            row(tr('Tür'), tr('Beslenme'));
        }
      case RecordType.pumping:
        row(tr('Miktar'), d['ml'] is num ? units.fmtVolume(d['ml'] as num) : null);
        row(
            tr('Zamanlama'),
            switch (d['timing']) {
              'before' => tr('Beslenmeden önce'),
              'after' => tr('Sonra'),
              _ => null,
            });
        note(tr('Not'), d['note'] as String?);
      case RecordType.sleep:
        final start = DateTime.tryParse(d['start_ts'] as String? ?? '')?.toLocal();
        final end = DateTime.tryParse(d['end_ts'] as String? ?? '')?.toLocal();
        if (start != null) row(tr('Başlangıç'), fmtTime(start));
        if (end != null) row(tr('Bitiş'), fmtTime(end));
        final mins = d['duration'];
        if (mins is num) {
          final h = mins ~/ 60, m = (mins % 60).toInt();
          row(tr('Süre'),
              h > 0 ? trp('{h} sa {m} dk', {'h': h, 'm': m}) : trp('{m} dk', {'m': m}));
        }
      case RecordType.growth:
        row(trp('Kilo ({unit})', {'unit': units.weightLabel}),
            d['weight'] is num ? units.fmtWeight(d['weight'] as num) : null);
        row(trp('Boy ({unit})', {'unit': units.lengthLabel}),
            d['height'] is num ? units.fmtLength(d['height'] as num) : null);
        row(trp('Baş çevresi ({unit})', {'unit': units.lengthLabel}),
            d['head_circ'] is num ? units.fmtLength(d['head_circ'] as num) : null);
      case RecordType.temperature:
        row(tr('Sıcaklık'),
            trp('{v} °{u}', {'v': d['value'] ?? '?', 'u': d['unit'] ?? 'C'}));
      case RecordType.medication:
        row(tr('İlaç / vitamin'), d['name'] as String?);
        row(tr('Doz'), d['dose'] as String?);
      case RecordType.bath:
        note(tr('Not'), d['note'] as String?);
      case RecordType.appointment:
        row(tr('Başlık'), d['title'] as String?);
        final dt = DateTime.tryParse(d['datetime'] as String? ?? '')?.toLocal();
        if (dt != null) row(tr('Tarih'), fmtDayMonthTime(dt));
        final lead = (d['reminder_lead_min'] as num?)?.toInt();
        if (d['reminder_id'] != null && lead != null) {
          row(tr('Hatırlatıcı'), _leadLabel(lead));
        }
        note(tr('Not'), d['note'] as String?);
      case RecordType.symptom:
        final key = d['key'] as String? ?? '';
        row(tr('Belirti'), trSymptom(key));
        row(tr('Şiddet'), SymptomSeverity.fromString(d['severity'] as String?).label);
        note(tr('Not'), d['note'] as String?);
        final s = symptomByKey(key);
        if (s != null) out.add(_SymptomGuide(symptom: s));
    }
    return out;
  }

  String _leadLabel(int min) => switch (min) {
        30 => tr('30 dk önce'),
        60 => tr('1 saat önce'),
        1440 => tr('1 gün önce'),
        _ => trp('{hours} saat önce', {'hours': (min / 60).round()}),
      };

  /// created_by → görünen ad. Kendi kaydı → "Sen". Bilinmiyorsa null.
  String? _resolveWho(WidgetRef ref) {
    final cb = record.createdBy;
    if (cb == null) return null;
    final me = ref.watch(authControllerProvider).asData?.value;
    if (me != null && cb == me.id) return tr('Sen');
    final members = ref.watch(membersProvider(record.baby)).asData?.value ?? const [];
    for (final m in members) {
      if (m.user.id == cb) return m.user.displayName;
    }
    return null;
  }
}

/// Etiket (sol, soluk) + değer (sağ) satırı.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// Serbest metin bloğu (not, tepki/alerji) — etiket üstte, değer altta tam
/// genişlik. [highlight] true ise dikkat çeken zemin (alerji/tepki için).
class _NoteBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _NoteBlock(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: highlight ? AppColors.symptomBg : fieldBg(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (highlight) ...[
                Icon(Icons.info_outline, size: 14, color: AppColors.symptom),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: highlight ? AppColors.symptom : AppColors.muted)),
            ],
          ),
          const SizedBox(height: 5),
          Text(value,
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35)),
        ],
      ),
    );
  }
}

/// Belirti için evde bakım rehberi kartı (record_form'daki kartla aynı stil).
class _SymptomGuide extends StatelessWidget {
  final SymptomKind symptom;
  const _SymptomGuide({required this.symptom});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: AppColors.symptomBg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(symptom.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trp('{s} · bakım rehberi', {'s': symptom.label}),
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.symptom)),
                const SizedBox(height: 3),
                Text(symptom.info,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
