import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/baby.dart';
import '../../models/tooth.dart';
import '../babies/baby_controller.dart';

/// Diş Gelişimi ekranı — gerçekçi ağız haritası (üstten görünüm, iki dental arch).
/// 20 süt dişi tipe göre şekillenir; çıkanlar yeşil işaretlenir. Tasarım:
/// design/AdenaBaby/Diş Gelişimi.html. Katalog sunucuda (teeth_catalog.py).
class TeethScreen extends ConsumerWidget {
  const TeethScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final async = ref.watch(teethProvider(baby.id));
    final ageMonths = _babyAgeMonths(baby);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(tr('Diş Gelişimi')),
            const SizedBox(width: 8),
            AdInfoDot(
              title: tr('Diş haritası nasıl çalışır?'),
              body: tr('Harita, bebeğinin ağzını yukarıdan görüyormuş gibi gösterir: '
                  'üstte üst çene, altta alt çene. Çıkan her dişe dokunup tarihiyle '
                  'işaretleyebilirsin. Kesik kenarlı şeftali renkli dişler, bebeğinin '
                  'yaşına göre sırada beklenenlerdir. Çıkış ayları ortalamadır; her '
                  'bebek kendine özgüdür — bu ekran rehberdir, tıbbi tanı değildir.'),
              size: 16,
            ),
          ],
        ),
      ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            Skeleton(height: 84, radius: 20),
            SizedBox(height: 12),
            Skeleton(height: 300, radius: 20),
          ],
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(apiErrorText(e),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
          ),
        ),
        data: (teeth) {
          if (teeth.isEmpty) {
            return Center(
              child: Text(tr('Diş haritası yükleniyor…'),
                  style: TextStyle(color: AppColors.muted)),
            );
          }
          final erupted = teeth.where((t) => t.erupted).length;
          final nextMonths = _nextMonths(teeth, ageMonths);
          final recent = teeth.where((t) => t.erupted && t.eruptedDate != null).toList()
            ..sort((a, b) => b.eruptedDate!.compareTo(a.eruptedDate!));

          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
            children: [
              _ProgressHeader(erupted: erupted, ageMonths: ageMonths),
              const SizedBox(height: 12),
              _MouthCard(
                teeth: teeth,
                nextMonths: nextMonths,
                onTapTooth: (t) => _showToothSheet(context, ref, baby.id, t),
              ),
              if (recent.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(3, 18, 3, 10),
                  child: Text(tr('SON ÇIKANLAR'),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.muted,
                          letterSpacing: 0.6)),
                ),
                _RecentTeeth(teeth: recent),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Text(
                    tr('Çıkış zamanları bebekten bebeğe değişir — bu harita rehber amaçlıdır.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted2,
                        height: 1.5)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showToothSheet(
      BuildContext context, WidgetRef ref, String babyId, Tooth tooth) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: false,
      shape: adSheetShape,
      isScrollControlled: true,
      builder: (ctx) => _ToothSheet(babyId: babyId, tooth: tooth),
    );
  }
}

// ── Diş geometrisi & şekilleri (HTML tasarımıyla birebir) ──────────────────

const double _vbW = 343, _vbH = 362, _cx = 171.5;
const _ang = {1: 9.0, 2: 27.0, 3: 45.0, 4: 62.0, 5: 78.0};

/// Dişin viewBox içindeki (x, y) merkezi ve derece cinsinden dönüşü.
(double x, double y, double rot) _place(Tooth t) {
  final a = _ang[t.position]! * (t.side == 'right' ? 1 : -1);
  final rad = a * math.pi / 180;
  if (t.isUpper) {
    return (_cx + 122 * math.sin(rad), 170 - 118 * math.cos(rad), a);
  }
  return (_cx + 112 * math.sin(rad), 206 + 104 * math.cos(rad), 180 - a);
}

/// Diş tipine göre taç şekli (yerel koordinat, 0,0 merkezli).
String _shape(int pos) => switch (pos) {
      1 => 'M -9.5 -9.5 Q -9.5 -12.5 -6.5 -12.5 L 6.5 -12.5 Q 9.5 -12.5 9.5 -9.5 '
          'L 9.5 4.5 Q 9.5 12.5 0 12.5 Q -9.5 12.5 -9.5 4.5 Z',
      2 => 'M -8.4 -8.4 Q -8.4 -11.3 -5.9 -11.3 L 5.9 -11.3 Q 8.4 -11.3 8.4 -8.4 '
          'L 8.4 4 Q 8.4 11.3 0 11.3 Q -8.4 11.3 -8.4 4 Z',
      3 => 'M 0 -13.5 Q 2.5 -9 7 -6.8 Q 9.5 -5.6 9.5 -2.8 L 9.5 4.5 Q 9.5 12.5 0 12.5 '
          'Q -9.5 12.5 -9.5 4.5 L -9.5 -2.8 Q -9.5 -5.6 -7 -6.8 Q -2.5 -9 0 -13.5 Z',
      4 => 'M -12 -5.5 Q -12 -12 -6.8 -12 Q -3.6 -12 -3.4 -9 Q -3.2 -6.8 0 -6.8 '
          'Q 3.2 -6.8 3.4 -9 Q 3.6 -12 6.8 -12 Q 12 -12 12 -5.5 L 12 4.5 '
          'Q 12 12.5 0 12.5 Q -12 12.5 -12 4.5 Z',
      _ => 'M -13.5 -5 Q -13.5 -12.5 -7.6 -12.5 Q -4.2 -12.5 -4 -9.4 Q -3.8 -7 0 -7 '
          'Q 3.8 -7 4 -9.4 Q 4.2 -12.5 7.6 -12.5 Q 13.5 -12.5 13.5 -5 L 13.5 5 '
          'Q 13.5 13 0 13 Q -13.5 13 -13.5 5 Z',
    };

const _check = 'M -4 0.5 L -1.2 3.4 L 4.6 -3';

/// Bebeğin yaşına en yakın çıkmamış dişlerin tipik ay(lar)ı — "sırada" vurgusu.
Set<int> _nextMonths(List<Tooth> teeth, int? age) {
  if (age == null) return {};
  int? best;
  for (final t in teeth) {
    if (t.erupted) continue;
    final d = (t.typicalMonth - age).abs();
    if (best == null || d < best) best = d;
  }
  if (best == null) return {};
  final months = <int>{};
  for (final t in teeth) {
    if (!t.erupted && (t.typicalMonth - age).abs() == best) months.add(t.typicalMonth);
  }
  return months;
}

/// Tek dişin SVG `<g>` işaretlemesi (durum: çıktı/sırada/çıkmadı).
String _toothMarkup(Tooth t, Set<int> nextMonths) {
  final (x, y, rot) = _place(t);
  final scale = t.isUpper ? 1.0 : 0.93;
  final String fill, stroke, extra;
  final double sw;
  if (t.erupted) {
    fill = '#52BA8E';
    stroke = '#3FA67A';
    sw = 1;
    extra = '';
  } else if (nextMonths.contains(t.typicalMonth)) {
    fill = '#FFE9DF';
    stroke = '#FF8A7A';
    sw = 1.6;
    extra = ' stroke-dasharray="3.2 2.6"';
  } else {
    fill = '#FFFEFD';
    stroke = '#ECDACF';
    sw = 1.5;
    extra = '';
  }
  var inner = '<path d="${_shape(t.position)}" fill="$fill" stroke="$stroke" '
      'stroke-width="$sw"$extra/>';
  if (t.erupted) {
    // Tik dik kalsın diye dişin dönüşünü geri al.
    inner += '<path d="$_check" fill="none" stroke="#fff" stroke-width="2.4" '
        'stroke-linecap="round" stroke-linejoin="round" '
        'transform="translate(0,1.5) rotate(${(-rot).toStringAsFixed(1)})"/>';
  } else if (t.position >= 4) {
    inner += '<path d="M -4.5 0.5 Q 0 3.6 4.5 0.5" fill="none" stroke="#E8D8CD" '
        'stroke-width="1.4" stroke-linecap="round"/>';
  }
  return '<g transform="translate(${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}) '
      'rotate(${rot.toStringAsFixed(1)}) scale($scale)">$inner</g>';
}

/// Tüm ağız haritasının SVG'si (arka plan + diş eti + dil + 20 diş).
String _mouthSvg(List<Tooth> teeth, Set<int> nextMonths) {
  final b = StringBuffer();
  b.write('<svg viewBox="0 0 $_vbW $_vbH" xmlns="http://www.w3.org/2000/svg">');
  b.write('<defs>'
      '<radialGradient id="mbg" cx="50%" cy="50%" r="60%">'
      '<stop offset="0%" stop-color="#FFE9DF" stop-opacity=".55"/>'
      '<stop offset="100%" stop-color="#FFE9DF" stop-opacity="0"/>'
      '</radialGradient>'
      '<linearGradient id="tng" x1="0" y1="0" x2="0" y2="1">'
      '<stop offset="0%" stop-color="#FFD9C8"/>'
      '<stop offset="100%" stop-color="#FFC9B4"/>'
      '</linearGradient>'
      '</defs>');
  b.write('<ellipse cx="$_cx" cy="181" rx="160" ry="168" fill="url(#mbg)"/>');
  // Diş eti yumuşak yayları
  b.write('<path d="M 56 148 Q 60 52 171.5 52 Q 283 52 287 148" fill="none" '
      'stroke="#FBEAE2" stroke-width="34" stroke-linecap="round"/>');
  b.write('<path d="M 66 226 Q 70 310 171.5 310 Q 273 310 277 226" fill="none" '
      'stroke="#FBEAE2" stroke-width="32" stroke-linecap="round"/>');
  // Dil (alt kemer içinde)
  b.write('<ellipse cx="$_cx" cy="259" rx="52" ry="42" fill="url(#tng)"/>'
      '<path d="M $_cx 232 Q ${_cx - 2} 258 $_cx 288" stroke="#F5AE94" '
      'stroke-width="2" stroke-linecap="round" fill="none" opacity=".55"/>');
  for (final t in teeth) {
    b.write(_toothMarkup(t, nextMonths));
  }
  b.write('</svg>');
  return b.toString();
}

// ── Üst ilerleme kartı ──────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  final int erupted;
  final int? ageMonths;
  const _ProgressHeader({required this.erupted, required this.ageMonths});

  static const _growthD = Color(0xFF349970);

  @override
  Widget build(BuildContext context) {
    const total = 20;
    final remaining = total - erupted;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.8, -1),
          end: Alignment(1, 1),
          colors: [Color(0xFFDBF2E8), Color(0xFFEAF8F1), Color(0xFFF2FBF6)],
          stops: [0, 0.58, 1],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '$erupted',
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w900, color: _growthD)),
                TextSpan(
                    text: trp(' / {t} diş çıktı', {'t': total}),
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.ink)),
              ])),
              const Spacer(),
              if (ageMonths != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: AppColors.smallShadow),
                  child: Text(trp('Şu an: {n}. ay', {'n': ageMonths}),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w900, color: _growthD)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: erupted / total,
              minHeight: 7,
              backgroundColor: const Color(0xFF52BA8E).withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation(AppColors.growth),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              remaining > 0
                  ? trp('{n} süt dişi daha bekleniyor', {'n': remaining})
                  : tr('Tüm süt dişleri tamamlandı 🎉'),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _growthD.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}

// ── Ağız haritası kartı ─────────────────────────────────────────────────────

class _MouthCard extends StatelessWidget {
  final List<Tooth> teeth;
  final Set<int> nextMonths;
  final ValueChanged<Tooth> onTapTooth;
  const _MouthCard(
      {required this.teeth, required this.nextMonths, required this.onTapTooth});

  void _handleTap(Offset local, double scale) {
    final vx = local.dx / scale, vy = local.dy / scale;
    Tooth? best;
    double bestD = double.infinity;
    for (final t in teeth) {
      final (x, y, _) = _place(t);
      final d = (x - vx) * (x - vx) + (y - vy) * (y - vy);
      if (d < bestD) {
        bestD = d;
        best = t;
      }
    }
    if (best != null && bestD < 23 * 23) onTapTooth(best);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            final h = w * _vbH / _vbW;
            final scale = w / _vbW;
            return SizedBox(
              width: w,
              height: h,
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _handleTap(d.localPosition, scale),
                    child: SvgPicture.string(
                      _mouthSvg(teeth, nextMonths),
                      width: w,
                      height: h,
                      fit: BoxFit.fill,
                    ),
                  ),
                  // Çene başlıkları (SVG yerine Flutter metni — net tipografi).
                  Positioned(
                    top: 4,
                    left: 0,
                    right: 0,
                    child: Center(child: _cap(tr('ÜST ÇENE'))),
                  ),
                  Positioned(
                    bottom: 2,
                    left: 0,
                    right: 0,
                    child: Center(child: _cap(tr('ALT ÇENE'))),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          // Açıklama (legend)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(const Color(0xFF52BA8E), tr('Çıktı')),
              const SizedBox(width: 16),
              _legend(const Color(0xFFFFE9DF), tr('Sırada'),
                  border: AppColors.coral, dashed: true),
              const SizedBox(width: 16),
              _legend(const Color(0xFFFFFEFD), tr('Çıkmadı'), border: AppColors.line2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cap(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Color(0xFFC3B2A9),
          letterSpacing: 1.4));

  Widget _legend(Color color, String label, {Color? border, bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            border: border != null
                ? Border.all(color: border, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
      ],
    );
  }
}

// ── Son çıkanlar listesi ────────────────────────────────────────────────────

class _RecentTeeth extends StatelessWidget {
  final List<Tooth> teeth;
  const _RecentTeeth({required this.teeth});

  @override
  Widget build(BuildContext context) {
    final shown = teeth.take(4).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i == shown.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: AppColors.growthBg,
                        borderRadius: BorderRadius.circular(11)),
                    alignment: Alignment.center,
                    child: const AdenaIcon('check',
                        size: 16, color: Color(0xFF349970), sw: 2.4),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${shown[i].positionLabel} · ${shown[i].name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 13.5)),
                        const SizedBox(height: 2),
                        Text(
                            fmtDayMonthYear(shown[i].eruptedDate!),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.growthBg,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(shown[i].typicalLabel,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF349970))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Diş detay sheet'i ───────────────────────────────────────────────────────

class _ToothSheet extends ConsumerStatefulWidget {
  final String babyId;
  final Tooth tooth;
  const _ToothSheet({required this.babyId, required this.tooth});

  @override
  ConsumerState<_ToothSheet> createState() => _ToothSheetState();
}

class _ToothSheetState extends ConsumerState<_ToothSheet> {
  late DateTime _date;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = widget.tooth.eruptedDate ?? DateTime.now();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 6),
      lastDate: now,
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _set(bool erupted) async {
    // Diş takibi yalnız owner/parent — bakıcı salt-okunur.
    if (!(ref.read(activeBabyProvider)?.canFullWrite ?? true)) {
      showAdToast(context, tr('Bu işlem için ebeveyn/sahip olmalısın'));
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(healthRepositoryProvider).setToothErupted(widget.tooth.id,
          erupted: erupted, date: erupted ? _date : null);
      ref.invalidate(teethProvider(widget.babyId));
      if (!mounted) return;
      Navigator.pop(context);
      showAdToast(context, erupted ? tr('Diş işaretlendi 🦷') : tr('Geri alındı'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdError(context, apiErrorText(e));
    }
  }

  /// Önizleme dişi (sheet başlığındaki kutu) — çıkmışsa yeşil+tik, değilse şeftali.
  String _previewSvg() {
    final t = widget.tooth;
    final on = t.erupted;
    final fill = on ? '#52BA8E' : '#FFE9DF';
    final stroke = on ? '#3FA67A' : '#FF8A7A';
    final dash = on ? '' : ' stroke-dasharray="3.2 2.6"';
    var s = '<svg viewBox="-17 -17 34 34" xmlns="http://www.w3.org/2000/svg">'
        '<path d="${_shape(t.position)}" fill="$fill" stroke="$stroke" '
        'stroke-width="1.5"$dash/>';
    if (on) {
      s += '<path d="$_check" fill="none" stroke="#fff" stroke-width="2.4" '
          'stroke-linecap="round" stroke-linejoin="round" transform="translate(0,1.5)"/>';
    }
    return '$s</svg>';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tooth;
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
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(18)),
                  alignment: Alignment.center,
                  child: SvgPicture.string(_previewSvg(), width: 42, height: 42),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${t.positionLabel} · ${t.name}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(trp('Tipik çıkış: {t}', {'t': t.typicalLabel}),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.muted)),
                      const SizedBox(height: 7),
                      _stateBadge(t),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AdField(
              label: tr('Çıkış tarihi'),
              info: tr('Dişin çıktığı günü seç. Emin değilsen yaklaşık bir tarih '
                  'girebilirsin; sonradan değiştirebilirsin.'),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      AdenaIcon('calendar', size: 18, color: AppColors.coralDark),
                      const SizedBox(width: 10),
                      Text(fmtDayMonthYear(_date),
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      AdenaIcon('chevD', size: 18, color: AppColors.muted2),
                    ],
                  ),
                ),
              ),
            ),
            if (t.erupted) ...[
              AdSaveButton(
                  label: _busy ? tr('Kaydediliyor…') : tr('Tarihi güncelle'),
                  color: AppColors.growth,
                  onTap: () => _set(true)),
              const SizedBox(height: 8),
              AdSaveButton(
                  label: tr('Geri al'),
                  color: AppColors.growth,
                  ghost: true,
                  onTap: () => _set(false)),
            ] else ...[
              AdSaveButton(
                  label: _busy ? tr('Kaydediliyor…') : tr('Çıktı olarak işaretle'),
                  color: AppColors.growth,
                  onTap: () => _set(true)),
              const SizedBox(height: 8),
              AdSaveButton(
                  label: tr('Vazgeç'),
                  color: AppColors.coralDark,
                  ghost: true,
                  onTap: () => Navigator.pop(context)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stateBadge(Tooth t) {
    final on = t.erupted;
    final text = on && t.eruptedDate != null
        ? trp('✓ Çıktı · {d}', {'d': fmtDayMonYear(t.eruptedDate!)})
        : tr('Henüz çıkmadı');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: on ? AppColors.growthBg : AppColors.peachLight,
          borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: on ? const Color(0xFF349970) : AppColors.coralDd)),
    );
  }
}

/// Bebeğin ay cinsinden yaşı (doğmamışsa/born değilse null).
int? _babyAgeMonths(Baby b) {
  final bd = b.birthDate;
  if (bd == null) return null;
  final now = DateTime.now();
  var months = (now.year - bd.year) * 12 + (now.month - bd.month);
  if (now.day < bd.day) months -= 1;
  return months < 0 ? 0 : months;
}
