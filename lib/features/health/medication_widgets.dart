import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/medication.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../data/home_nudge_prefs.dart';
import '../../data/local_session.dart';
import '../../models/record.dart';
import '../auth/auth_controller.dart';
import '../babies/members_screen.dart' show membersProvider;
import '../records/record_controller.dart';
import '../records/record_form.dart';
import 'medication_plan_sheet.dart';

/// İlaç & Vitamin ortak parçaları (design/AdenaBaby Mobile/İlaç & Vitamin
/// Takibi.html): günün doz kartı, bölüm başlığı, keşif kartı, + menüsünden
/// açılan sayfa ve işaretleme/geri alma akışı. Ana sayfa, + menüsü ve yönetim
/// ekranı aynı parçaları ve aynı kuralları kullanır.

const _uuid = Uuid();

/// Dakikada bir tetiklenir — "saati geçti" / "öne çıkar" durumları kayıt
/// değişmeden, yalnız saat ilerleyince de güncellensin.
final _minuteTickProvider = StreamProvider.autoDispose<int>(
    (ref) => Stream.periodic(const Duration(minutes: 1), (i) => i));

/// Bugünün ilaç/vitamin özeti. Plan ya da bugünün kayıtları henüz yüklenmediyse
/// null (yüklenirken "saati geçti" yanıp sönmesin, bölüm yer değiştirmesin).
final medicationDayProvider =
    Provider.autoDispose.family<MedicationDay?, String>((ref, babyId) {
  ref.watch(_minuteTickProvider);
  final plans = ref.watch(medicationPlansProvider(babyId)).asData?.value;
  if (plans == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final records =
      ref.watch(dayRecordsProvider((babyId: babyId, day: today))).asData?.value;
  if (records == null) return null;
  return medicationDay(plans, records, now: now);
});

/// Ana sayfa keşif kartı kapatıldı mı (cihaz-yerel bayrak).
final medDiscoverDismissedProvider = FutureProvider<bool>(
    (ref) => HomeNudgePrefs.instance.dismissed('med_discover'));

// ───────── kim verdi ─────────

const _avatarPalette = [
  Color(0xFFE2553F),
  Color(0xFF7C6BE0),
  Color(0xFF349970),
  Color(0xFF2F92C8),
  Color(0xFFB5821C),
];

typedef MedGiver = ({String name, String initial, Color color});

/// Üye rengi (id'ye göre sabit) — akıştaki avatar paletiyle aynı.
Color medAvatarColor(String id) => _avatarPalette[id.hashCode.abs() % _avatarPalette.length];

/// Dozu BAŞKA bir aile üyesi verdiyse onun adı/baş harfi/rengi; kendi kaydıysa
/// (ya da henüz senkronlanmamış yerel kayıtsa — createdBy null) null. Üye
/// listesi yüklenemediyse ad boş, baş harf "?" döner (yine "başkası" sayılır).
/// [watch] false → build dışı (dokunma işleyicisi) kullanım.
MedGiver? medOtherGiver(WidgetRef ref, String babyId, Record? record,
    {bool watch = true}) {
  final cb = record?.createdBy;
  if (cb == null) return null;
  final me = (watch ? ref.watch(authControllerProvider) : ref.read(authControllerProvider))
      .asData
      ?.value;
  final localId = watch ? ref.watch(localUserIdProvider) : ref.read(localUserIdProvider);
  if (cb == me?.id || cb == localId) return null;
  final members =
      (watch ? ref.watch(membersProvider(babyId)) : ref.read(membersProvider(babyId)))
              .asData
              ?.value ??
          const [];
  final color = _avatarPalette[cb.hashCode.abs() % _avatarPalette.length];
  for (final m in members) {
    if (m.user.id == cb) {
      final name = m.user.displayName;
      return (
        name: name,
        initial: (name.characters.firstOrNull ?? '?').toUpperCaseTr(),
        color: color,
      );
    }
  }
  return (name: '', initial: '?', color: color);
}

// ───────── işaretleme / atlama / düzeltme ─────────

/// Doza dokunma.
/// - Sıradaki doz ([MedicationDoseRole.next]) → tek adımda "verildi" kaydı
///   yazar, 4 sn "Geri al" toast'ı gösterir.
/// - İşaretlenmiş doz (verildi/atlandı) → doz sayfası: verildiği saati düzelt,
///   kaydı geri al (yalnız son işaretlenen), atlananı "verildi"ye çevir.
/// - Sırası gelmemiş kilitli doz → hiçbir şey.
Future<void> medTapDose(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) async {
  if (dose.isResolved) return _showDoseSheet(context, ref, babyId, dose);
  if (dose.role != MedicationDoseRole.next) return;
  await _writeDose(context, ref, babyId, dose, skipped: false);
}

/// Sıradaki doza uzun basma → "Verildi / Bu dozu atla" seçenekleri.
Future<void> medLongPressDose(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) async {
  if (dose.isResolved) return _showDoseSheet(context, ref, babyId, dose);
  if (dose.role != MedicationDoseRole.next) return;
  final skip = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => _SheetFrame(
      title: trp('{name} · {t} dozu', {'name': dose.plan.name, 't': dose.time}),
      children: [
        Text(
            tr('Bilinçli olarak verilmediyse atla. Atlanan doz "saati geçti" '
                'uyarısından çıkar, ailen de görür.'),
            style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: AppColors.muted)),
        const SizedBox(height: 16),
        AdSaveButton(
            label: tr('Verildi olarak işaretle'),
            color: AppColors.coral,
            onTap: () => Navigator.pop(ctx, false)),
        const SizedBox(height: 10),
        AdSaveButton(
            label: tr('Bu dozu atla'),
            color: AppColors.coralDd,
            ghost: true,
            onTap: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (skip == null || !context.mounted) return;
  await _writeDose(context, ref, babyId, dose, skipped: skip);
}

/// Sıradaki dozu doğrudan "atlandı" işaretler (satırdaki "Atla" bağlantısı).
Future<void> medSkipDose(
        BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) =>
    dose.role == MedicationDoseRole.next && !dose.isResolved
        ? _writeDose(context, ref, babyId, dose, skipped: true)
        : Future.value();

/// "Verildi" / "atlandı" kaydı — ikisi de aile-paylaşımlı `RecordType.medication`
/// satırıdır; atlanan `given:false, skipped:true` taşır.
Future<void> _writeDose(BuildContext context, WidgetRef ref, String babyId,
    MedicationDose dose,
    {required bool skipped}) async {
  final actions = ref.read(recordActionsProvider);
  final id = _uuid.v4();
  await actions.upsert(Record(
    id: id,
    baby: babyId,
    type: RecordType.medication,
    ts: DateTime.now(),
    data: {
      'name': dose.plan.name,
      'dose': dose.plan.dose,
      'given': !skipped,
      if (skipped) 'skipped': true,
    },
  ));
  if (!context.mounted) return;
  showAdToast(
    context,
    trp(skipped ? '{name} · {t} atlandı' : '{name} · {t} verildi',
        {'name': dose.plan.name, 't': dose.time}),
    type: skipped ? AdToastType.info : AdToastType.success,
    duration: const Duration(seconds: 4),
    onUndo: () => actions.delete(id),
  );
}

/// Sayfa iskeleti: tutamak + ilaç ikonlu başlık + içerik.
class _SheetFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SheetFrame({required this.title, required this.children});

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
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2, bottom: 12),
              child: Row(
                children: [
                  AdIconChip('med', color: AppColors.med, bg: AppColors.medBg, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

Future<void> _showDoseSheet(
    BuildContext context, WidgetRef ref, String babyId, MedicationDose dose) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _DoseSheet(babyId: babyId, dose: dose),
  );
}

/// İşaretlenmiş dozun sayfası — verildiği saati düzeltme (aşıdaki tarih
/// düzeltme gibi), geri alma, atlananı "verildi"ye çevirme.
class _DoseSheet extends ConsumerStatefulWidget {
  final String babyId;
  final MedicationDose dose;
  const _DoseSheet({required this.babyId, required this.dose});

  @override
  ConsumerState<_DoseSheet> createState() => _DoseSheetState();
}

class _DoseSheetState extends ConsumerState<_DoseSheet> {
  late DateTime _at = widget.dose.record!.ts;

  MedicationDose get _dose => widget.dose;
  Record get _record => _dose.record!;
  bool get _changed => _at != _record.ts;

  /// Aynı planın komşu kayıtları — sıralı eşleme bozulmasın diye yeni saat
  /// bunların ARASINDA kalmalı.
  ({DateTime? after, DateTime? before}) _bounds() {
    final rows = ref.read(medicationDayProvider(widget.babyId))?.rows ?? const [];
    DateTime? after, before;
    for (final r in rows) {
      if (r.plan.id != _dose.plan.id) continue;
      final recs = [
        for (final d in r.doses)
          if (d.record != null) d.record!,
      ];
      final i = recs.indexWhere((x) => x.id == _record.id);
      if (i > 0) after = recs[i - 1].ts;
      if (i >= 0 && i < recs.length - 1) before = recs[i + 1].ts;
    }
    return (after: after, before: before);
  }

  Future<void> _pick() async {
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (picked == null || !mounted) return;
    final t = DateTime(_at.year, _at.month, _at.day, picked.hour, picked.minute);
    if (t.isAfter(DateTime.now())) {
      showAdError(context, tr('Gelecek bir saat seçilemez'));
      return;
    }
    final b = _bounds();
    if ((b.after != null && !t.isAfter(b.after!)) ||
        (b.before != null && !t.isBefore(b.before!))) {
      showAdError(context, tr('Bu saat başka bir dozun kaydıyla çakışıyor'));
      return;
    }
    setState(() => _at = t);
  }

  Future<void> _save() async {
    await ref.read(recordActionsProvider).upsert(_record.copyWith(ts: _at));
    if (!mounted) return;
    Navigator.pop(context);
    showAdToast(context, tr('Saat güncellendi'));
  }

  Future<void> _undo() async {
    await ref.read(recordActionsProvider).delete(_record.id);
    if (!mounted) return;
    Navigator.pop(context);
    showAdToast(context, tr('Geri alındı'), type: AdToastType.info);
  }

  Future<void> _markGiven() async {
    final data = Map<String, dynamic>.from(_record.data)
      ..remove('skipped')
      ..['given'] = true;
    await ref.read(recordActionsProvider).upsert(_record.copyWith(data: data));
    if (!mounted) return;
    Navigator.pop(context);
    showAdToast(
        context, trp('{name} · {t} verildi', {'name': _dose.plan.name, 't': _dose.time}));
  }

  @override
  Widget build(BuildContext context) {
    final other = medOtherGiver(ref, widget.babyId, _record);
    final canUndo = _dose.role == MedicationDoseRole.undo;
    final muted = TextStyle(
        fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w700, color: AppColors.muted);

    return _SheetFrame(
      title: trp('{name} · {t} dozu', {'name': _dose.plan.name, 't': _dose.time}),
      children: [
        if (other != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                MedWhoDot(other, size: 26, ring: false),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                      other.name.isEmpty
                          ? tr('Bu dozu başka bir aile üyesi işaretledi')
                          : trp('Bu dozu {who} işaretledi', {'who': other.name}),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        if (_dose.isSkipped)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(tr('Bu doz atlandı olarak işaretlendi (bilinçli verilmedi).'),
                style: muted),
          )
        else
          AdField(
            label: tr('Verildiği saat'),
            child: Material(
              color: fieldBg(context),
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: _pick,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.line, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      AdenaIcon('clock', size: 18, color: AppColors.med),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(fmtTime(_at),
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                      Text(tr('Değiştir'),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.coralDark)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_dose.isSkipped && canUndo)
          AdSaveButton(
              label: tr('Verildi olarak işaretle'),
              color: AppColors.coral,
              onTap: _markGiven)
        else if (!_dose.isSkipped)
          AdSaveButton(
              label: _changed ? tr('Kaydet') : tr('Tamam'),
              color: AppColors.coral,
              onTap: _changed ? _save : () => Navigator.pop(context)),
        if (canUndo) ...[
          const SizedBox(height: 10),
          AdSaveButton(
              label: tr('Kaydı geri al'),
              color: AppColors.coralDd,
              ghost: true,
              onTap: _undo),
          if (other != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('Geri alırsan ailede herkes için silinir.'),
                  textAlign: TextAlign.center, style: muted),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr('Geri almak için önce sonraki dozun kaydını geri al.'),
                textAlign: TextAlign.center, style: muted),
          ),
      ],
    );
  }
}

// ───────── küçük parçalar ─────────

/// RTL'de aynalanan "ileri" oku.
String medChevron(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl ? 'chevL' : 'chevR';

/// Kesikli çerçeve (daire ya da yuvarlak-köşe) — "henüz sırası gelmedi" /
/// "ekle" / "duraklatıldı" görünümü.
class MedDashedBorder extends CustomPainter {
  final Color color;
  final double radius; // double.infinity → tam yuvarlak
  final double width;
  const MedDashedBorder({required this.color, required this.radius, this.width = 1.5});

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius.isFinite ? radius : size.shortestSide / 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(width / 2), Radius.circular(r)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    const dash = 4.0, gap = 3.5;
    for (final PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(MedDashedBorder old) =>
      old.color != color || old.radius != radius || old.width != width;
}

/// Hap biçimli çip (öneri / "Başka ekle" / "Saat ekle").
class MedChip extends StatelessWidget {
  final String label;
  final String? icon;
  final bool selected;
  final bool dashed;
  final double height;
  final VoidCallback onTap;
  const MedChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.dashed = false,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? AppColors.coralDd
        : (dashed ? AppColors.coralDark : AppColors.ink2);
    final body = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: dashed
          ? null
          : BoxDecoration(
              color: selected ? AppColors.feedBg : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: selected ? AppColors.coral : AppColors.line, width: 1.5),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AdenaIcon(icon!, size: 14, color: fg, sw: 2.4),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: fg)),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: dashed
            ? CustomPaint(
                painter: MedDashedBorder(color: AppColors.line2, radius: double.infinity),
                child: body)
            : body,
      ),
    );
  }
}

/// Küçük üye rozeti (baş harf) — doz düğmesi/çipi köşesinde "kim verdi".
class MedWhoDot extends StatelessWidget {
  final MedGiver who;
  final double size;
  final bool ring;
  const MedWhoDot(this.who, {super.key, this.size = 19, this.ring = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: who.color,
        shape: BoxShape.circle,
        border: ring
            ? Border.all(color: Theme.of(context).colorScheme.surface, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(who.initial,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1,
              fontSize: size * 0.47)),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int done;
  final int total;
  const _CountPill({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppColors.smallShadow,
      ),
      child: Text('$done/$total',
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: AppColors.ink2,
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }
}

/// Bölüm başlığı: "İLAÇ & VİTAMİN" + verilen/toplam + sağda "Planlar ›".
class MedSectionHeader extends StatelessWidget {
  final String title;
  final MedicationDay? day;
  final VoidCallback? onPlans;
  final double top;
  const MedSectionHeader(
      {super.key, required this.title, this.day, this.onPlans, this.top = 18});

  @override
  Widget build(BuildContext context) {
    final d = day;
    return Padding(
      padding: EdgeInsets.fromLTRB(3, top, 3, 10),
      child: Row(
        children: [
          // Başlık + sayaç solda kalan alanı doldurur; "Planlar" hep en sağda.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(title.toUpperCaseTr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.muted,
                          letterSpacing: 0.7)),
                ),
                if (d != null && d.total > 0) ...[
                  const SizedBox(width: 8),
                  _CountPill(done: d.done, total: d.total),
                ],
              ],
            ),
          ),
          if (onPlans != null) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPlans,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Planlar'),
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.coralDark)),
                      const SizedBox(width: 2),
                      AdenaIcon(medChevron(context),
                          size: 13, color: AppColors.coralDark, sw: 2.4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────── doz düğmesi ─────────

/// Saati geçmiş sıradaki dozun etrafındaki nazik nabız halkası. Sistem
/// "hareketi azalt" açıksa sabit kalır.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        // 0→.5: halka açılıp söner, .5→1: dinlenir.
        final t = (_c.value * 2).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.coral.withValues(alpha: 0.45 * (1 - t)),
                spreadRadius: 6 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Dozun görsel tonu — düğme (ana sayfa) ve çip (yönetim) ortak kullanır.
/// Bilgi üçlü verilir: renk + simge + metin (gece yarı uykulu okunabilsin).
({Color bg, Color? border, bool dashed, Color text, bool faded}) _doseTone(
    MedicationDose d) {
  final next = d.role == MedicationDoseRole.next;
  switch (d.status) {
    case MedicationDoseStatus.given:
      return (
        bg: AppColors.growth,
        border: null,
        dashed: false,
        text: AppColors.growth,
        faded: false
      );
    case MedicationDoseStatus.skipped:
      return (
        bg: AppColors.line,
        border: null,
        dashed: false,
        text: AppColors.muted,
        faded: false
      );
    case MedicationDoseStatus.overdue:
      return (
        bg: AppColors.feverBg,
        border: AppColors.coral,
        dashed: false,
        text: AppColors.coralDd,
        faded: !next
      );
    case MedicationDoseStatus.upcoming:
      return next
          ? (
              bg: AppColors.medBg,
              border: AppColors.med,
              dashed: false,
              text: AppColors.med,
              faded: false
            )
          : (
              bg: Colors.transparent,
              border: AppColors.line2,
              dashed: true,
              text: AppColors.muted,
              faded: true
            );
  }
}

String _doseSemantics(MedicationDose d) => switch (d.status) {
      MedicationDoseStatus.given => trp('Verildi · {t}', {'t': d.time}),
      MedicationDoseStatus.skipped => trp('Atlandı · {t}', {'t': d.time}),
      MedicationDoseStatus.overdue => trp('Saati geçti · {t}', {'t': d.time}),
      MedicationDoseStatus.upcoming => trp('Planlanan · {t}', {'t': d.time}),
    };

/// Ana sayfa doz düğmesi: 46×58 dokunma hedefi, 40px daire + altında saat.
class MedDoseButton extends ConsumerWidget {
  final String babyId;
  final MedicationDose dose;
  const MedDoseButton({super.key, required this.babyId, required this.dose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dose;
    final tone = _doseTone(d);
    final who = d.isResolved ? medOtherGiver(ref, babyId, d.record) : null;
    final tappable = d.isResolved || d.role == MedicationDoseRole.next;

    Widget circle = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tone.bg,
        shape: BoxShape.circle,
        border: tone.border != null && !tone.dashed
            ? Border.all(color: tone.border!, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: d.isGiven
          ? const AdenaIcon('check', size: 20, color: Colors.white, sw: 2.8)
          : (d.isSkipped
              ? AdenaIcon('close', size: 16, color: AppColors.muted, sw: 2.4)
              : null),
    );
    if (tone.dashed) {
      circle = CustomPaint(
        foregroundPainter:
            MedDashedBorder(color: tone.border!, radius: double.infinity, width: 2),
        child: circle,
      );
    }
    if (tone.faded) circle = Opacity(opacity: 0.6, child: circle);
    if (d.isOverdue && d.role == MedicationDoseRole.next) circle = _Pulse(child: circle);

    return Semantics(
      button: tappable,
      label: '${d.plan.name} · ${_doseSemantics(d)}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tappable ? () => medTapDose(context, ref, babyId, d) : null,
        onLongPress: tappable ? () => medLongPressDose(context, ref, babyId, d) : null,
        // 46×58 en küçük hedef; büyük sistem yazı boyutunda saat etiketi
        // büyürse düğme uzar (taşmaz), genişlik sabit kalır.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58, minWidth: 46, maxWidth: 46),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  circle,
                  if (who != null)
                    PositionedDirectional(bottom: -4, end: -5, child: MedWhoDot(who)),
                ],
              ),
              const SizedBox(height: 4),
              Text(d.time,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                      fontSize: 10.5,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: tone.text,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yönetim ekranı saat çipi — aynı kurallar, hap biçimi.
class MedTimeChip extends ConsumerWidget {
  final String babyId;
  final MedicationDose dose;
  const MedTimeChip({super.key, required this.babyId, required this.dose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dose;
    final tone = _doseTone(d);
    final who = d.isResolved ? medOtherGiver(ref, babyId, d.record) : null;
    final tappable = d.isResolved || d.role == MedicationDoseRole.next;
    final given = d.isGiven;

    Widget chip = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: given ? AppColors.growthBg : tone.bg,
        borderRadius: BorderRadius.circular(999),
        border: !given && tone.border != null && !tone.dashed
            ? Border.all(color: tone.border!, width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (given) ...[
            AdenaIcon('check', size: 14, color: tone.text, sw: 2.8),
            const SizedBox(width: 6),
          ] else if (d.isSkipped) ...[
            AdenaIcon('close', size: 12, color: tone.text, sw: 2.4),
            const SizedBox(width: 6),
          ],
          Text(d.time,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: tone.text,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (who != null) ...[
            const SizedBox(width: 6),
            MedWhoDot(who, size: 16, ring: false),
          ],
        ],
      ),
    );
    if (tone.dashed) {
      chip = CustomPaint(
        foregroundPainter: MedDashedBorder(color: tone.border!, radius: double.infinity),
        child: chip,
      );
    }
    return Semantics(
      button: tappable,
      label: _doseSemantics(d),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tappable ? () => medTapDose(context, ref, babyId, d) : null,
        onLongPress: tappable ? () => medLongPressDose(context, ref, babyId, d) : null,
        child: chip,
      ),
    );
  }
}

// ───────── gün kartı ─────────

/// Günün doz kartı: üstte gün çubuğu (her doz bir segment), saati geçen varsa
/// uyarı şeridi, her plan bir satır, her saat bir düğme. Hepsi verildiyse tek
/// satıra iner; 3'ten fazla planda tamamlananlar "+N plan" satırında toplanır.
/// [flat] → sayfa (sheet) içinde gölgesiz/alan zeminli.
class MedDayCard extends ConsumerStatefulWidget {
  final String babyId;
  final MedicationDay day;
  final bool flat;
  const MedDayCard({super.key, required this.babyId, required this.day, this.flat = false});

  @override
  ConsumerState<MedDayCard> createState() => _MedDayCardState();
}

class _MedDayCardState extends ConsumerState<MedDayCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final decoration = BoxDecoration(
      color: widget.flat ? fieldBg(context) : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      boxShadow: widget.flat ? null : AppColors.softShadow,
    );

    if (day.allDone && !_expanded) {
      return Container(
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: _doneRow(day),
      );
    }

    final hideDone = day.rows.length > 3 && !_expanded;
    final doneRows = day.rows.where((r) => r.complete).toList();
    final shown = hideDone ? day.rows.where((r) => !r.complete).toList() : day.rows;

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(day),
          if (day.overdue > 0) _strip(day.overdue),
          for (var i = 0; i < shown.length; i++)
            _PlanRow(babyId: widget.babyId, row: shown[i], divider: i > 0),
          if (hideDone && doneRows.isNotEmpty)
            _FootRow(
              leading: _CheckStack(count: doneRows.length.clamp(1, 3)),
              label: trp('+{n} plan · bugün tamam', {'n': doneRows.length}),
              up: false,
              onTap: () => setState(() => _expanded = true),
            ),
          if (_expanded && (day.rows.length > 3 || day.allDone))
            _FootRow(
              label: tr('Daha az göster'),
              up: true,
              onTap: () => setState(() => _expanded = false),
            ),
        ],
      ),
    );
  }

  Widget _bar(MedicationDay day) {
    final segs = day.timeline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 3),
      child: Row(
        children: [
          for (var i = 0; i < segs.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: switch (segs[i].status) {
                    MedicationDoseStatus.given => AppColors.growth,
                    MedicationDoseStatus.skipped => AppColors.muted2,
                    MedicationDoseStatus.overdue => AppColors.coral,
                    MedicationDoseStatus.upcoming => AppColors.line,
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _strip(int n) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: AppColors.feverBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AppColors.coral, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                n == 1
                    ? tr('1 dozun saati geçti — verdiysen dokun')
                    : trp('{n} dozun saati geçti — verdiysen dokun', {'n': n}),
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: AppColors.coralDd)),
          ),
        ],
      ),
    );
  }

  Widget _doneRow(MedicationDay day) {
    // Dozu veren diğer aile üyeleri (tekrarsız) — "kim verdi" bir bakışta.
    final givers = <String, MedGiver>{};
    for (final d in day.timeline) {
      final g = medOtherGiver(ref, widget.babyId, d.record);
      if (g != null) givers[d.record!.createdBy!] = g;
    }
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.growthBg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const AdenaIcon('check', size: 22, color: AppColors.growth, sw: 2.8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Bugünün dozları tamam'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                      trp('{done}/{total} verildi · yarın ilk doz {t}',
                          {'done': day.done, 'total': day.total, 't': day.firstTime}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
            for (final g in givers.values.take(3))
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 3),
                child: MedWhoDot(g, size: 22, ring: false),
              ),
            const SizedBox(width: 8),
            AdenaIcon('chevD', size: 16, color: AppColors.muted2),
          ],
        ),
      ),
    );
  }
}

/// Bir planın satırı: ikon + ad·doz + durum metni + doz düğmeleri.
class _PlanRow extends ConsumerWidget {
  final String babyId;
  final MedicationPlanDay row;
  final bool divider;
  const _PlanRow({required this.babyId, required this.row, required this.divider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = row.plan;
    final late = row.firstOverdue;
    final (String text, Color color) = () {
      if (late != null) {
        return (trp('Saati geçti · {t}', {'t': late.time}), AppColors.coralDd);
      }
      if (row.complete) {
        final g = row.lastResolved!;
        if (g.isSkipped) {
          return (trp('Atlandı · {t}', {'t': g.time}), AppColors.muted);
        }
        final at = fmtTime(g.record!.ts);
        final who = medOtherGiver(ref, babyId, g.record);
        return (
          who != null && who.name.isNotEmpty
              ? trp('Verildi · {t} · {who}', {'t': at, 'who': who.name})
              : trp('Verildi · {t}', {'t': at}),
          AppColors.growth,
        );
      }
      final k = row.givenCount, n = row.doses.length;
      return (
        n > 1 && k > 0
            ? trp('Sıradaki · {t} · {k}/{n}', {'t': row.next!.time, 'k': k, 'n': n})
            : trp('Sıradaki · {t}', {'t': row.next!.time}),
        AppColors.muted,
      );
    }();

    // 3+ dozda düğmeler alt satıra geçer: dar telefonda ad/durum (ve "Atla")
    // sıkışmasın, düğmeler küçülmesin.
    final wide = row.doses.length > 2;
    final info = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: p.name,
              children: [
                if (p.dose.isNotEmpty)
                  TextSpan(
                      text: ' · ${p.dose}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.muted)),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, height: 1.25),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
              ),
              // Saati geçen doz bilinçli verilmediyse tek dokunuşla "atlandı".
              if (late != null && late.role == MedicationDoseRole.next)
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => medSkipDose(context, ref, babyId, late),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 6, 4),
                      child: Text(tr('Atla'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink2,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.muted2)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    final doses = [
      for (final d in row.doses) MedDoseButton(babyId: babyId, dose: d),
    ];

    return Container(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: AppColors.line)) : null,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 7),
      child: Column(
        children: [
          Row(
            children: [
              AdIconChip('med', color: AppColors.med, bg: AppColors.medBg),
              const SizedBox(width: 12),
              info,
              if (!wide) ...[
                const SizedBox(width: 8),
                Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: doses),
              ],
            ],
          ),
          if (wide)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 50),
                child: Wrap(spacing: 4, children: doses),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckStack extends StatelessWidget {
  final int count;
  const _CheckStack({required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16.0 + (count - 1) * 11,
      height: 16,
      child: Stack(
        children: [
          for (var i = 0; i < count; i++)
            PositionedDirectional(
              start: i * 11.0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.growth,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: const AdenaIcon('check', size: 8, color: Colors.white, sw: 3.4),
              ),
            ),
        ],
      ),
    );
  }
}

class _FootRow extends StatelessWidget {
  final Widget? leading;
  final String label;
  final bool up;
  final VoidCallback onTap;
  const _FootRow({required this.label, required this.up, required this.onTap, this.leading});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 8)],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.muted)),
            ),
            RotatedBox(
              quarterTurns: up ? 2 : 0,
              child: AdenaIcon('chevD', size: 15, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────── keşif kartı (plan yok) ─────────

/// Hiç plan yokken ana sayfada modülü keşfettiren, kapatılabilir kart. Öneri
/// çipleri adı dolu bir "Yeni plan" sayfası açar.
class MedDiscoverCard extends ConsumerWidget {
  final String babyId;
  const MedDiscoverCard({super.key, required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.smallShadow,
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [AppColors.medBg, surface],
          stops: const [0, 0.85],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 28),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: AppColors.smallShadow,
                        ),
                        alignment: Alignment.center,
                        child: const AdenaIcon('med', size: 21, color: AppColors.med, sw: 1.9),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(tr('Her gün verdiğin vitaminleri takip et'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 14.5, height: 1.25)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 9, bottom: 11),
                  child: Text(
                      tr('Saatini kur, hatırlatalım. Tek dokunuşla işaretle; ailen '
                          'de görsün, çift doz verilmesin.'),
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
                ),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final s in medicationSuggestions().take(3))
                      MedChip(
                        label: s.name,
                        icon: 'plus',
                        onTap: () => showMedicationPlanSheet(context, babyId,
                            presetName: s.name, presetTime: s.time),
                      ),
                    MedChip(
                      label: tr('Başka ekle'),
                      dashed: true,
                      onTap: () => showMedicationPlanSheet(context, babyId),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Semantics(
              button: true,
              label: tr('Kapat'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await HomeNudgePrefs.instance.dismiss('med_discover');
                  ref.invalidate(medDiscoverDismissedProvider);
                },
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                      child: AdenaIcon('close', size: 16, color: AppColors.muted, sw: 2.2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── ana sayfa bölümü ─────────

/// Ana sayfa "İlaç & Vitamin" bölümü. Aktif plan varsa günün doz kartı; hiç
/// plan yoksa (ve kapatılmadıysa) keşif kartı; aksi halde gizli. Bölümün
/// sayfadaki YERİ çağıran tarafından [medicationDayProvider]`.promote`'a göre
/// seçilir (bkz. home_screen.dart _HomeTab).
class MedHomeSection extends ConsumerWidget {
  final String babyId;
  const MedHomeSection({super.key, required this.babyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(medicationDayProvider(babyId));
    if (day == null) return const SizedBox.shrink();
    void openPlans() => context.push('/medications');

    if (day.hasActive) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MedSectionHeader(title: tr('İlaç & Vitamin'), day: day, onPlans: openPlans),
          MedDayCard(babyId: babyId, day: day),
        ],
      );
    }
    // Yalnız duraklatılmış planı olan kullanıcı modülü zaten biliyor → keşif yok.
    if (day.planCount > 0) return const SizedBox.shrink();
    final dismissed = ref.watch(medDiscoverDismissedProvider).asData?.value ?? true;
    if (dismissed) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MedSectionHeader(title: tr('İlaç & Vitamin'), onPlans: openPlans),
        MedDiscoverCard(babyId: babyId),
      ],
    );
  }
}

// ───────── + menüsü → İlaç & Vitamin sayfası ─────────

/// + → İlaç & Vitamin: bugünün dozları (işaretlenebilir) + plan dışı tek
/// seferlik kayıt + planları yönet. [context]/[ref] sayfa kapandıktan sonra da
/// geçerli olan ÇAĞIRAN ekranınkiler olmalı (form/rota onlarla açılır).
Future<void> showMedicationSheet(BuildContext context, WidgetRef ref, String babyId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Consumer(
          builder: (_, sheetRef, _) {
            final day = sheetRef.watch(medicationDayProvider(babyId));
            final plans = day?.planCount ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: adGrabHandle()),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 2, bottom: 4),
                  child: Row(
                    children: [
                      AdIconChip('med', color: AppColors.med, bg: AppColors.medBg, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('İlaç & Vitamin'),
                            style:
                                const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                if (day != null && day.hasActive) ...[
                  MedSectionHeader(title: tr('Bugünün planı'), day: day, top: 10),
                  MedDayCard(babyId: babyId, day: day, flat: true),
                  const SizedBox(height: 6),
                ] else
                  const SizedBox(height: 8),
                _SheetOption(
                  icon: 'fever',
                  color: AppColors.coralDd,
                  bg: AppColors.feverBg,
                  title: tr('Plan dışı ilaç kaydet'),
                  meta: tr('Ateş düşürücü gibi tek seferlik'),
                  divider: day != null && day.hasActive,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showRecordForm(context, ref, babyId, RecordType.medication);
                  },
                ),
                _SheetOption(
                  icon: 'clock',
                  color: AppColors.med,
                  bg: AppColors.medBg,
                  title: tr('Planları yönet'),
                  meta: plans > 0
                      ? trp('{n} plan · ilaç ekle, saat ve doz değiştir', {'n': plans})
                      : tr('Her gün verdiklerini ekle, saatinde hatırlatalım'),
                  divider: true,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    context.push('/medications');
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _SheetOption extends StatelessWidget {
  final String icon;
  final Color color;
  final Color bg;
  final String title;
  final String meta;
  final bool divider;
  final VoidCallback onTap;
  const _SheetOption({
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.meta,
    required this.divider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: divider ? Border(top: BorderSide(color: AppColors.line)) : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 13),
        child: Row(
          children: [
            AdIconChip(icon, color: color, bg: bg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(meta,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
            AdenaIcon(medChevron(context), size: 18, color: AppColors.muted2),
          ],
        ),
      ),
    );
  }
}
