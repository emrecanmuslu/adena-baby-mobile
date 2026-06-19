import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_service.dart';
import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../data/mom_repository.dart';
import '../../data/subscription_repository.dart';
import '../../models/mom_entry.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';

/// Anne takibi giriş sheet'i (kilo / randevu / not).
Future<void> showMomEntrySheet(
    BuildContext context, WidgetRef ref, String babyId, MomKind kind) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _MomEntrySheet(babyId: babyId, kind: kind),
    ),
  );
}

// Getter (top-level `final` DEĞİL) — `final` tr()'yi ve tema-duyarlı *-bg
// renklerini ilk erişimde dondurur (dil/tema değişince eskide kalır). Getter
// her okumada taze değerlenir.
Map<MomKind, (String, Color, Color, String)> get _kindMeta => {
      MomKind.weight: ('growth', AppColors.growth, AppColors.growthBg, tr('Anne kilosu')),
      MomKind.appointment: ('doctor', AppColors.doctor, AppColors.doctorBg, tr('Randevu')),
      MomKind.note: ('edit', AppColors.med, AppColors.medBg, tr('Not')),
    };

class _MomEntrySheet extends ConsumerStatefulWidget {
  final String babyId;
  final MomKind kind;
  const _MomEntrySheet({required this.babyId, required this.kind});

  @override
  ConsumerState<_MomEntrySheet> createState() => _MomEntrySheetState();
}

class _MomEntrySheetState extends ConsumerState<_MomEntrySheet> {
  final _weight = TextEditingController();
  final _title = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _weight.dispose();
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final dt = await pickRecordDateTime(context, _date);
    if (dt != null) setState(() => _date = dt);
  }

  Future<void> _save() async {
    final units = ref.read(activeUnitsProvider);
    double? weightKg;
    String? title, note;
    switch (widget.kind) {
      case MomKind.weight:
        final v = num.tryParse(_weight.text.trim().replaceAll(',', '.'));
        if (v == null) return showAdError(context, tr('Kilo gir'));
        weightKg = units.weightToCanonical(v.toDouble());
      case MomKind.appointment:
        if (_title.text.trim().isEmpty) return showAdError(context, tr('Başlık gir'));
        title = _title.text.trim();
        if (_note.text.trim().isNotEmpty) note = _note.text.trim();
      case MomKind.note:
        if (_note.text.trim().isEmpty) return showAdError(context, tr('Not gir'));
        note = _note.text.trim();
    }
    setState(() => _saving = true);
    try {
      await ref.read(momRepositoryProvider).add(widget.babyId,
          kind: widget.kind, date: _date, weightKg: weightKg, title: title, note: note);
      ref.invalidate(momEntriesProvider(widget.babyId));
      // Tamamlanan anne kaydı → interstitial sayılır (bekleme/postpartum kullanıcı
      // da reklam görsün); frekans/grace/premium limitleri AdService'te.
      unawaited(AdService.instance
          .onRecordSaved(isPremium: ref.read(isPremiumProvider)));
      if (!mounted) return;
      showAdToast(context, tr('Kaydedildi'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(activeUnitsProvider);
    final (icon, color, bg, label) = _kindMeta[widget.kind]!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Row(children: [
              AdIconChip(icon, color: color, bg: bg),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 16),
            ..._fields(units, color),
            AdField(
              label: tr('Zaman'),
              child: AdTimeChip(value: _date, onTap: _pick),
            ),
            const SizedBox(height: 8),
            _saving
                ? FilledButton(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                        backgroundColor: color,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    child: const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white)),
                  )
                : AdSaveButton(label: tr('Kaydet'), color: color, onTap: _save),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields(Units units, Color color) {
    switch (widget.kind) {
      case MomKind.weight:
        return [
          AdField(
            label: trp('Kilo ({unit})', {'unit': units.weightLabel}),
            child: AdStepper(
                controller: _weight,
                unit: units.weightLabel,
                step: 0.1,
                decimals: 1,
                accent: color),
          ),
        ];
      case MomKind.appointment:
        return [
          AdField(
            label: tr('Başlık / doktor'),
            child: AdInput(
                controller: _title,
                hint: tr('örn. 28. hafta kontrolü · Dr. Elif'),
                capitalization: TextCapitalization.sentences),
          ),
          AdField(label: tr('Not'), child: AdInput(controller: _note, hint: tr('isteğe bağlı'))),
        ];
      case MomKind.note:
        return [
          AdField(
            label: tr('Not'),
            child: AdInput(
                controller: _note,
                hint: tr('örn. bebek bugün çok hareketliydi'),
                capitalization: TextCapitalization.sentences),
          ),
        ];
    }
  }
}

/// Anne takibi ekranı (design ScrMom): kilo grafiği + yaklaşan randevu + notlar.
class MomTrackingScreen extends ConsumerWidget {
  const MomTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    // Anne takibi kişisel veri — bakıcıdan gizli. (Backend de 403 döner.)
    if (!baby.canFullWrite) {
      return Scaffold(
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(tr('Anne takibi'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
                tr('Anne takibi yalnız ebeveyn ve sahibe açıktır.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }
    final units = ref.watch(activeUnitsProvider);
    final async = ref.watch(momEntriesProvider(baby.id));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Anne takibi')),
      ),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.coral)),
        error: (e, _) => Center(child: Text(apiErrorText(e))),
        data: (entries) {
          final weights = entries.where((e) => e.kind == MomKind.weight).toList()
            ..sort((a, b) => a.date.compareTo(b.date));
          final appts = entries.where((e) => e.kind == MomKind.appointment).toList()
            ..sort((a, b) => a.date.compareTo(b.date));
          final notes = entries.where((e) => e.kind == MomKind.note).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          final now = DateTime.now();
          final upcoming = appts.where((a) => a.date.isAfter(now)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
                child: Text(tr('Hafif takip — tam gebelik kaydı değil.'),
                    style: TextStyle(
                        color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 13)),
              ),

              // Kilo
              _sec(tr('Kilo'), onAdd: () => showMomEntrySheet(context, ref, baby.id, MomKind.weight)),
              _WeightCard(weights: weights, units: units),

              // Yaklaşan randevu
              _sec(tr('Yaklaşan randevu'),
                  onAdd: () =>
                      showMomEntrySheet(context, ref, baby.id, MomKind.appointment)),
              if (upcoming.isEmpty)
                _emptyHint(tr('Henüz randevu yok. + ile ekle.'))
              else
                ...upcoming.take(3).map((a) => _ApptRow(entry: a, babyId: baby.id)),

              // Notlar
              _sec(tr('Notlar'),
                  onAdd: () => showMomEntrySheet(context, ref, baby.id, MomKind.note)),
              if (notes.isEmpty)
                _emptyHint(tr('Henüz not yok. + ile ekle.'))
              else
                ...notes.map((n) => _NoteRow(entry: n, babyId: baby.id)),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(text,
            style: TextStyle(
                color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  /// + ekleme butonlu bölüm başlığı.
  Widget _sec(String title, {required VoidCallback onAdd}) => Padding(
        padding: const EdgeInsets.fromLTRB(3, 18, 0, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(title.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.muted,
                      letterSpacing: 0.7)),
            ),
            GestureDetector(
              onTap: onAdd,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: AdenaIcon('plus', size: 18, color: AppColors.coralDark),
              ),
            ),
          ],
        ),
      );
}

/// Kilo kartı: güncel + artış pill + çizgi grafik.
class _WeightCard extends StatelessWidget {
  final List<MomEntry> weights; // tarihe göre artan
  final Units units;
  const _WeightCard({required this.weights, required this.units});

  @override
  Widget build(BuildContext context) {
    final hasData = weights.any((w) => w.weightKg != null);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: !hasData
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(tr('Kilo ekleyince burada grafik oluşur.'),
                    style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
              ),
            )
          : _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final pts = weights.where((w) => w.weightKg != null).toList();
    final first = pts.first.weightKg!;
    final last = pts.last.weightKg!;
    final curPref = units.weightFromCanonical(last);
    final deltaPref = units.weightFromCanonical(last) - units.weightFromCanonical(first);
    final dec = units.weight == 'lb' ? 1 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text.rich(TextSpan(
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              children: [
                TextSpan(text: curPref.toStringAsFixed(dec)),
                TextSpan(
                    text: ' ${units.weightLabel}',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.muted)),
              ],
            )),
            if (pts.length >= 2)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.growthBg, borderRadius: BorderRadius.circular(999)),
                child: Text(
                    '${deltaPref >= 0 ? '+' : ''}${deltaPref.toStringAsFixed(dec)} ${units.weightLabel}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF349970))),
              ),
          ],
        ),
        if (pts.length >= 2) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            width: double.infinity,
            child: CustomPaint(
              painter: _WeightLinePainter(
                  [for (final p in pts) units.weightFromCanonical(p.weightKg!)]),
            ),
          ),
        ],
      ],
    );
  }
}

class _WeightLinePainter extends CustomPainter {
  final List<double> values;
  _WeightLinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var minY = values.reduce(math.min), maxY = values.reduce(math.max);
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }
    final pad = (maxY - minY) * 0.15;
    minY -= pad;
    maxY += pad;
    Offset at(int i) => Offset(
          size.width * i / (values.length - 1),
          size.height * (1 - (values[i] - minY) / (maxY - minY)),
        );
    final fill = Path()..moveTo(at(0).dx, size.height);
    for (var i = 0; i < values.length; i++) {
      fill.lineTo(at(i).dx, at(i).dy);
    }
    fill
      ..lineTo(at(values.length - 1).dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = AppColors.coral.withValues(alpha: 0.12));
    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.coral
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    final last = at(values.length - 1);
    canvas.drawCircle(last, 4.5, Paint()..color = AppColors.coralDark);
    canvas.drawCircle(last, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WeightLinePainter o) => o.values != values;
}

class _ApptRow extends ConsumerWidget {
  final MomEntry entry;
  final String babyId;
  const _ApptRow({required this.entry, required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: AppColors.doctor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
                  child: Row(
                    children: [
                      AdIconChip('doctor',
                          color: AppColors.doctor, bg: AppColors.doctorBg, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.title ?? tr('Randevu'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                                fmtDayMonthTime(entry.date),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.muted)),
                            if (entry.note != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(entry.note!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.muted)),
                              ),
                          ],
                        ),
                      ),
                      _delBtn(context, ref),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _delBtn(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: tr('Sil'),
        icon: Icon(Icons.close, size: 18, color: AppColors.muted),
        onPressed: () async {
          await ref.read(momRepositoryProvider).delete(babyId, entry.id);
          ref.invalidate(momEntriesProvider(babyId));
          if (context.mounted) showAdToast(context, tr('Silindi'));
        },
      );
}

class _NoteRow extends ConsumerWidget {
  final MomEntry entry;
  final String babyId;
  const _NoteRow({required this.entry, required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.diaperBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('"${entry.note ?? ''}"',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink2,
                        height: 1.4)),
                const SizedBox(height: 6),
                Text(fmtDayMonthTime(entry.date),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              await ref.read(momRepositoryProvider).delete(babyId, entry.id);
              ref.invalidate(momEntriesProvider(babyId));
              if (context.mounted) showAdToast(context, tr('Silindi'));
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 18, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}
