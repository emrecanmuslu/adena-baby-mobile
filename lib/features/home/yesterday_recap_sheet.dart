import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/medication.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../core/yesterday_recap.dart';
import '../../data/health_repository.dart';
import '../../data/local_session.dart';
import '../../data/record_repository.dart';
import '../../models/baby.dart';
import '../../models/record.dart';
import '../auth/auth_controller.dart';
import '../babies/family_settings.dart';
import '../babies/members_screen.dart' show membersProvider;
import '../health/medication_widgets.dart' show MedGiver, MedWhoDot, medAvatarColor;
import '../records/record_controller.dart';
import '../records/record_ui.dart';

/// "Dün nasıl geçti?" sabah özeti (design/AdenaBaby Mobile/Dün Nasıl Geçti.html):
/// alttan yüzen kart — tek cümlelik başlık, 24 saatlik şerit, en fazla 3 öne
/// çıkan an, (varsa) aile satırı ve bugünkü randevu. Hesap `core/yesterday_recap.dart`
/// içinde saf; burada yalnız veri toplama + metin + çizim var.

const _uuid = Uuid();

/// Özeti gösterirken gereken her şey (hesap + üye adları).
typedef RecapBundle = ({YesterdayRecap recap, List<({MedGiver who, int count})> family});

String _recentKey(String babyId) => 'recap_recent_$babyId';

/// Dünün özetini yerel kayıtlardan kurar. Dün hiç kayıt yoksa null.
Future<RecapBundle?> loadYesterdayRecap(WidgetRef ref, Baby baby) async {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
  final repo = ref.read(recordRepositoryProvider);
  final history =
      await repo.watchSince(baby.id, day.subtract(const Duration(days: 8))).first;
  final foods = await repo.solidFoodNamesBefore(baby.id, day);
  final plans = await ref.read(medicationPlansProvider(baby.id).future);
  final me = ref.read(authControllerProvider).asData?.value;
  final localId = ref.read(localUserIdProvider);

  // Önceki günlerin öne çıkan kimlikleri (cihaz-yerel; senkron edilmez).
  var recent = const <List<String>>[];
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey(baby.id));
    if (raw != null) {
      recent = [
        for (final d in (jsonDecode(raw) as List)) (d as List).cast<String>(),
      ];
    }
  } catch (_) {}

  final recap = buildYesterdayRecap(
    day: day,
    history: history,
    knownFoods: foods,
    plans: plans,
    recentIds: recent,
    selfIds: {if (me != null) me.id, if (localId.isNotEmpty) localId},
  );
  if (recap == null) return null;

  // Aile satırı: yalnız birden çok kişi kayıt eklediyse üye adlarını çöz.
  final family = <({MedGiver who, int count})>[];
  if (recap.contributors.isNotEmpty) {
    var members = const [];
    try {
      members = await ref
          .read(membersProvider(baby.id).future)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    for (final c in recap.contributors) {
      if (c.userId == null) {
        final n = me?.displayName ?? '';
        family.add((
          who: (
            name: tr('Sen'),
            initial: (n.characters.firstOrNull ?? tr('Sen').characters.first).toUpperCaseTr(),
            color: AppColors.coral,
          ),
          count: c.count,
        ));
        continue;
      }
      var name = '';
      for (final m in members) {
        if (m.user.id == c.userId) name = m.user.displayName as String;
      }
      family.add((
        who: (
          name: name,
          initial: (name.characters.firstOrNull ?? '?').toUpperCaseTr(),
          color: medAvatarColor(c.userId!),
        ),
        count: c.count,
      ));
    }
  }
  return (recap: recap, family: family);
}

Future<void> _rememberHighlights(String babyId, YesterdayRecap recap) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey(babyId));
    final old = raw == null ? const [] : jsonDecode(raw) as List;
    final next = [
      [for (final h in recap.highlights) h.id],
      ...old.take(2),
    ];
    await prefs.setString(_recentKey(babyId), jsonEncode(next));
  } catch (_) {}
}

/// Özeti alttan yüzen kart olarak gösterir. Scrim'e dokunma, aşağı kaydırma,
/// geri tuşu ya da "Güne başla" ile kapanır.
Future<void> showYesterdayRecap(
    BuildContext context, WidgetRef ref, Baby baby, RecapBundle bundle) {
  unawaited(_rememberHighlights(baby.id, bundle.recap));
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: dark ? const Color(0x99050208) : const Color(0x6B2C1812),
    builder: (_) => _RecapSheet(baby: baby, initial: bundle),
  );
}

/// Kart içi zemin (şerit kutusu, rozetler, notlar) — design var(--bg). Koyu
/// temada kart rengiyle aynı olan fieldBg yerine sayfa zemini: kontrast kalsın.
Color _ground(BuildContext c) => Theme.of(c).scaffoldBackgroundColor;

// ───────── metin yardımcıları ─────────

/// Süre: "4 sa 50 dk" / "4 sa" / "50 dk".
String recapDur(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h > 0 && m > 0) return trp('{h} sa {m} dk', {'h': h, 'm': m});
  if (h > 0) return trp('{h} sa', {'h': h});
  return trp('{m} dk', {'m': m});
}

String _clock(int minuteOfDay) =>
    fmtTime(DateTime(2000, 1, 1, minuteOfDay ~/ 60, minuteOfDay % 60));

String _delta(int d) => '${d >= 0 ? '+' : '−'}${recapDur(d.abs())}';

String recapHeadlineText(RecapHeadline h, String baby) => switch (h.kind) {
      RecapHeadlineKind.firstFood =>
        trp('Dün bir ilk vardı: {food}', {'food': h.text}),
      RecapHeadlineKind.longestSleep => trp('{baby} dün {dur} aralıksız uyudu',
          {'baby': baby, 'dur': recapDur(h.minutes ?? 0)}),
      RecapHeadlineKind.daySleepLonger => tr('Gündüz uykuları dün daha uzundu'),
      RecapHeadlineKind.closeWatch =>
        trp('Dün {baby} için yakın takip günüydü', {'baby': baby}),
      RecapHeadlineKind.family => tr('Dünü birlikte kaydettiniz'),
      RecapHeadlineKind.sleepTotal => trp('{baby} dün toplam {dur} uyudu',
          {'baby': baby, 'dur': recapDur(h.minutes ?? 0)}),
      RecapHeadlineKind.feedCount =>
        trp('{baby} dün {n} kez beslendi', {'baby': baby, 'n': h.count}),
      RecapHeadlineKind.diaperCount => trp('Dün {n} bez değişti', {'n': h.count}),
      RecapHeadlineKind.generic => tr('Dünün özeti hazır'),
    };

// ───────── sayfa ─────────

class _RecapSheet extends ConsumerStatefulWidget {
  final Baby baby;
  final RecapBundle initial;
  const _RecapSheet({required this.baby, required this.initial});

  @override
  ConsumerState<_RecapSheet> createState() => _RecapSheetState();
}

class _RecapSheetState extends ConsumerState<_RecapSheet>
    with SingleTickerProviderStateMixin {
  late RecapBundle _b = widget.initial;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));
  bool _adding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hareket azaltma açıksa çizim/yükselme animasyonu yok.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else if (_c.status == AnimationStatus.dismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// "Verdiysen ekle": kaydı olmayan dozları DÜNÜN plan saatine yazar, sonra
  /// özeti yeniden kurar. Reklam/puanlama tetiklemesin diye RecordActions
  /// yerine doğrudan depoya yazılır.
  Future<void> _addMissing(List<MedicationDose> doses) async {
    if (_adding) return;
    setState(() => _adding = true);
    final repo = ref.read(recordRepositoryProvider);
    final day = _b.recap.day;
    for (final d in doses) {
      final m = medicationMinutes(d.time);
      await repo.upsertLocal(Record(
        id: _uuid.v4(),
        baby: widget.baby.id,
        type: RecordType.medication,
        ts: DateTime(day.year, day.month, day.day, m ~/ 60, m % 60),
        data: {'name': d.plan.name, 'dose': d.plan.dose, 'given': true},
      ));
    }
    unawaited(ref.read(syncServiceProvider).syncAll());
    final next = await loadYesterdayRecap(ref, widget.baby);
    if (!mounted) return;
    setState(() {
      _adding = false;
      if (next != null) _b = next;
    });
  }

  Animation<double> _iv(double a, double b) =>
      CurvedAnimation(parent: _c, curve: Interval(a, b, curve: Curves.easeOutCubic));

  @override
  Widget build(BuildContext context) {
    final recap = _b.recap;
    final units = ref.watch(activeUnitsProvider);
    final surface = Theme.of(context).colorScheme.surface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final n = recap.highlights.length;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 5,
            margin: const EdgeInsets.only(top: 2, bottom: 12),
            decoration: BoxDecoration(
                color: AppColors.line2, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.smallShadow,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.peachLight, AppColors.peach],
                ),
              ),
              alignment: Alignment.center,
              child: _Rise(
                anim: _iv(0.1, 0.6),
                dy: 7,
                child: AdenaIcon('sunrise',
                    size: 25, color: dark ? AppColors.coral : AppColors.coralDd, sw: 1.9),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      trp('Dün · {d}', {
                        'd': DateFormat('d MMMM EEEE', dfLocale()).format(recap.day)
                      }).toUpperCaseTr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.muted,
                          letterSpacing: 0.6)),
                  const SizedBox(height: 3),
                  Text(recapHeadlineText(recap.headline, widget.baby.name),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w900, height: 1.24)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (!recap.ribbon.isEmpty) ...[
          _Ribbon(ribbon: recap.ribbon, draw: _iv(0.2, 0.75), label: _iv(0.75, 1)),
          const SizedBox(height: 6),
        ],
        for (var i = 0; i < n; i++)
          _Rise(
            anim: _iv(0.45 + i * 0.07, 0.85 + i * 0.05),
            child: _HighlightRow(
              h: recap.highlights[i],
              units: units,
              divider: i > 0 && !recap.highlights[i].first && !recap.highlights[i - 1].first,
              busy: _adding,
              onAdd: _addMissing,
            ),
          ),
        if (recap.littleData)
          _Rise(
            anim: _iv(0.55, 0.95),
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: _ground(context), borderRadius: BorderRadius.circular(14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: AdenaIcon('ai', size: 16, color: AppColors.coralDark, sw: 2),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                        trp(
                            'Birkaç gün kayıt girdikçe burada {baby} için ritmi ve '
                            'değişimi göstereceğiz.',
                            {'baby': widget.baby.name}),
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink2)),
                  ),
                ],
              ),
            ),
          ),
        if (_b.family.isNotEmpty)
          _Rise(
            anim: _iv(0.5 + n * 0.07, 1),
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: _ground(context), borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  for (final f in _b.family.take(3))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: MedWhoDot(f.who, size: 26, ring: false),
                    ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                        trp('{list} kayıt', {
                          'list': [
                            for (final f in _b.family)
                              '${f.who.name.isEmpty ? '?' : f.who.name} ${f.count}',
                          ].join(' · ')
                        }),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ),
        if (recap.nextAppointment != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(2, 10, 2, 0),
            child: Row(
              children: [
                const AdenaIcon('calendar', size: 16, color: AppColors.doctor, sw: 2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      trp('Bugün {t} · {title}', {
                        't': fmtTime(recap.nextAppointment!.ts),
                        'title': recap.nextAppointment!.data['title'] as String? ??
                            tr('Randevu'),
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.ink2)),
                ),
              ],
            ),
          ),
      ],
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
          child: Material(
            color: surface,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Üstte hafif sabah ışıması.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 130,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topCenter,
                          radius: 1.2,
                          colors: [AppColors.peachLight, AppColors.peachLight.withValues(alpha: 0)],
                          stops: const [0, 0.72],
                        ),
                      ),
                    ),
                  ),
                ),
                // Tek eylem hep görünür: içerik sığmazsa yalnız üst kısım kayar.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                        child: content,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                      child: AdSaveButton(
                          label: tr('Güne başla'),
                          color: AppColors.coral,
                          onTap: () => Navigator.pop(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aşağıdan hafifçe yükselerek belirme.
class _Rise extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  final double dy;
  const _Rise({required this.anim, required this.child, this.dy = 8});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      child: child,
      builder: (_, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, dy * (1 - anim.value)), child: child),
      ),
    );
  }
}

// ───────── 24 saatlik şerit ─────────

class _Ribbon extends StatelessWidget {
  final RecapRibbon ribbon;
  final Animation<double> draw; // soldan sağa "gün baştan oynatılır"
  final Animation<double> label; // en uzun uyku etiketi en son gelir
  const _Ribbon({required this.ribbon, required this.draw, required this.label});

  @override
  Widget build(BuildContext context) {
    final r = ribbon;
    final hasF = r.feeds.isNotEmpty, hasS = r.sleeps.isNotEmpty, hasD = r.diapers.isNotEmpty;
    final call = hasS && r.longest != null;
    // Katman yerleşimi (yalnız kaydı olan katmanlar yer kaplar).
    var y = call ? 20.0 : 4.0;
    final fy = y;
    if (hasF) y += 15;
    final sh = !hasF && !hasD ? 22.0 : 16.0; // tek kategoriyse uyku kalınlaşır
    final sy = y;
    if (hasS) y += sh + 6;
    final dy = y;
    if (hasD) y += 9;
    final height = y + 2;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final surface = Theme.of(context).colorScheme.surface;

    Widget? callout;
    if (call) {
      final b = r.sleeps[r.longest!];
      final p = ((b.start + b.end) / 2 / 1440).clamp(0.0, 1.0);
      callout = Align(
        alignment: AlignmentDirectional(p * 2 - 1, -1),
        child: FadeTransition(
          opacity: label,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(999),
              boxShadow: AppColors.smallShadow,
            ),
            child: Text(trp('En uzun · {dur}', {'dur': recapDur(r.longestMin)}),
                maxLines: 1,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.sleep)),
          ),
        ),
      );
    }

    final legend = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.ink2);
    Widget leg(Widget mark, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [mark, const SizedBox(width: 5), Text(text, style: legend)],
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration:
          BoxDecoration(color: _ground(context), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: draw,
                    builder: (_, _) => CustomPaint(
                      painter: _RibbonPainter(
                        ribbon: r,
                        progress: draw.value,
                        rtl: rtl,
                        nightTop: call ? 16 : 0,
                        feedY: hasF ? fy : null,
                        sleepY: hasS ? sy : null,
                        sleepH: sh,
                        diaperY: hasD ? dy : null,
                        nightColor: AppColors.sleepBg.withValues(alpha: 0.55),
                        railColor: AppColors.line2,
                        surface: surface,
                        ground: _ground(context),
                      ),
                    ),
                  ),
                ),
                ?callout,
              ],
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in const ['00', '06', '12', '18', '24'])
                Text(h,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                        fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 9, 2, 0),
            child: Wrap(
              spacing: 13,
              runSpacing: 4,
              children: [
                if (hasF)
                  leg(
                      Container(
                          width: 3.5,
                          height: 10,
                          decoration: BoxDecoration(
                              color: AppColors.coral,
                              borderRadius: BorderRadius.circular(2))),
                      trp('{n} beslenme', {'n': r.feeds.length})),
                if (hasS && r.sleepTotalMin > 0)
                  leg(
                      Container(
                          width: 13,
                          height: 8,
                          decoration: BoxDecoration(
                              color: AppColors.sleep,
                              borderRadius: BorderRadius.circular(3))),
                      trp('{dur} uyku', {'dur': recapDur(r.sleepTotalMin)})),
                if (hasD)
                  leg(
                      Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                              color: AppColors.diaper, shape: BoxShape.circle)),
                      trp('{n} bez', {'n': r.diapers.length})),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final RecapRibbon ribbon;
  final double progress;
  final bool rtl;
  final double nightTop;
  final double? feedY;
  final double? sleepY;
  final double sleepH;
  final double? diaperY;
  final Color nightColor;
  final Color railColor;
  final Color surface;
  final Color ground;
  const _RibbonPainter({
    required this.ribbon,
    required this.progress,
    required this.rtl,
    required this.nightTop,
    required this.feedY,
    required this.sleepY,
    required this.sleepH,
    required this.diaperY,
    required this.nightColor,
    required this.railColor,
    required this.surface,
    required this.ground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    // Dakika aralığı → dikdörtgen (RTL'de gün sağdan sola akar).
    Rect span(num a, num b, double top, double h) {
      final x1 = a / 1440 * w, x2 = b / 1440 * w;
      return rtl ? Rect.fromLTRB(w - x2, top, w - x1, top + h) : Rect.fromLTRB(x1, top, x2, top + h);
    }

    double x(num m) => rtl ? w - m / 1440 * w : m / 1440 * w;
    const r6 = Radius.circular(6);

    // Gece zemini (00–07 ve 19–24) + uyku rayı — anında, çizimden bağımsız.
    final night = Paint()..color = nightColor;
    for (final (a, b) in const [(0, recapNightEndMin), (recapNightStartMin, 1440)]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(span(a, b, nightTop, size.height - nightTop), r6), night);
    }
    if (sleepY != null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, sleepY! + sleepH / 2 - 1, w, 2), const Radius.circular(1)),
          Paint()..color = railColor);
    }

    // Kayıtlar soldan sağa (RTL: sağdan sola) açılır.
    canvas.save();
    final reveal = w * progress;
    canvas.clipRect(rtl
        ? Rect.fromLTRB(w - reveal, -4, w, size.height + 4)
        : Rect.fromLTRB(0, -4, reveal, size.height + 4));

    if (sleepY != null) {
      for (var i = 0; i < ribbon.sleeps.length; i++) {
        final b = ribbon.sleeps[i];
        final rect = span(b.start, b.end, sleepY!, sleepH);
        final rr = RRect.fromRectAndRadius(rect, r6);
        canvas.drawRRect(
            rr,
            Paint()
              ..color = b.night ? AppColors.sleep : AppColors.sleep.withValues(alpha: 0.6));
        if (i == ribbon.longest) {
          // En uzun uyku: zemin boşluğu + ince halka.
          canvas.drawRRect(
              rr.inflate(1),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = ground);
          canvas.drawRRect(
              rr.inflate(2.75),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = AppColors.sleep);
        }
      }
    }
    if (feedY != null) {
      final p = Paint()..color = AppColors.coral;
      for (final m in ribbon.feeds) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(x(m), feedY! + 5.5), width: 3.5, height: 11),
                const Radius.circular(2)),
            p);
      }
    }
    if (diaperY != null) {
      final fill = Paint()..color = AppColors.diaper;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.diaper;
      for (final d in ribbon.diapers) {
        final c = Offset(x(d.min), diaperY! + 3.5);
        switch (d.kind) {
          case RecapDiaperKind.pee: // içi boş halka
            canvas.drawCircle(c, 3.5, Paint()..color = ground);
            canvas.drawCircle(c, 2.5, ring);
          case RecapDiaperKind.poo: // dolu
            canvas.drawCircle(c, 3.5, fill);
          case RecapDiaperKind.both: // dolu + dış halka
            canvas.drawCircle(c, 2.5, fill);
            canvas.drawCircle(c, 4.5, ring..strokeWidth = 1.2);
            ring.strokeWidth = 2;
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.progress != progress || old.ribbon != ribbon || old.rtl != rtl || old.ground != ground;
}

// ───────── öne çıkan satırı ─────────

class _HighlightRow extends StatelessWidget {
  final RecapHighlight h;
  final Units units;
  final bool divider;
  final bool busy;
  final Future<void> Function(List<MedicationDose>) onAdd;
  const _HighlightRow({
    required this.h,
    required this.units,
    required this.divider,
    required this.busy,
    required this.onAdd,
  });

  Widget _chip(BuildContext context) {
    Widget rec(RecordType t) => RecordUi.chip(t, size: 38, radius: 13);
    return switch (h.kind) {
      RecapHighlightKind.firstFood => AdIconChip('solid',
          color: AppColors.feed, bg: Theme.of(context).colorScheme.surface),
      RecapHighlightKind.medication => rec(RecordType.medication),
      RecapHighlightKind.longestSleep ||
      RecapHighlightKind.daySleep ||
      RecapHighlightKind.bedtime =>
        rec(RecordType.sleep),
      RecapHighlightKind.fever => rec(RecordType.temperature),
      RecapHighlightKind.growth => rec(RecordType.growth),
      RecapHighlightKind.bath => rec(RecordType.bath),
      RecapHighlightKind.breast ||
      RecapHighlightKind.bottle ||
      RecapHighlightKind.feedMixed =>
        rec(RecordType.feed),
      RecapHighlightKind.diaper => rec(RecordType.diaper),
    };
  }

  String _temp(num v) => '${v.toStringAsFixed(1)} °${h.unit ?? 'C'}';

  ({String title, String sub}) _text() {
    switch (h.kind) {
      case RecapHighlightKind.firstFood:
        final amt = h.amount;
        final amtStr = amt is num ? trp('{n} kaşık', {'n': amt}) : amt?.toString();
        return (
          title: trp('İlk ek gıda · {food}', {'food': h.text}),
          sub: [
            if (h.at != null) fmtTime(h.at!),
            if (amtStr != null && amtStr.isNotEmpty) amtStr,
            if (h.text2 != null && h.text2!.isNotEmpty) trp('tepki: {r}', {'r': h.text2}),
          ].join(' · '),
        );
      case RecapHighlightKind.medication:
        final name = h.text ?? tr('İlaç & Vitamin');
        final String sub;
        if (h.missing.isNotEmpty) {
          sub = h.missing.length == 1
              ? trp('{t} dozu kayıtlı değil.', {'t': h.missing.first.time})
              : trp('{n} doz kayıtlı değil.', {'n': h.missing.length});
        } else if ((h.minutes ?? 0) > 0) {
          sub = trp('{n} doz atlandı', {'n': h.minutes});
        } else {
          sub = tr('Hepsi kaydedildi');
        }
        return (
          title: trp('{name} · {done}/{total} doz',
              {'name': name, 'done': h.count, 'total': h.count2}),
          sub: sub,
        );
      case RecapHighlightKind.longestSleep:
        return (
          title: trp('En uzun uyku · {dur}', {'dur': recapDur(h.minutes ?? 0)}),
          sub: [
            if (h.at != null && h.at2 != null) '${fmtTime(h.at!)}–${fmtTime(h.at2!)}',
            if (h.flag) tr('son 7 günün en uzunu'),
          ].join(' · '),
        );
      case RecapHighlightKind.daySleep:
        return (
          title: trp('Gündüz uykusu · {dur}', {'dur': recapDur(h.minutes ?? 0)}),
          sub: [
            trp('{n} şekerleme', {'n': h.count}),
            if (h.minutes2 != null)
              trp('son 7 gün ortalaması {dur}', {'dur': recapDur(h.minutes2!)}),
          ].join(' · '),
        );
      case RecapHighlightKind.bedtime:
        return (
          title: trp('Gece uykusu başlangıcı · {t}', {'t': _clock(h.clock ?? 0)}),
          sub: trp('Son 7 günde genelde {t} civarı', {'t': _clock(h.clock2 ?? 0)}),
        );
      case RecapHighlightKind.fever:
        return (
          title: trp('Ateş · en yüksek {v}', {'v': _temp(h.value ?? 0)}),
          sub: (h.count ?? 1) > 1
              ? trp('{n} ölçüm · sonuncusu {t}: {v}', {
                  'n': h.count,
                  't': h.at2 != null ? fmtTime(h.at2!) : '',
                  'v': _temp(h.value2 ?? 0),
                })
              : trp('Ölçüm · {t}', {'t': h.at2 != null ? fmtTime(h.at2!) : ''}),
        );
      case RecapHighlightKind.growth:
        final parts = [
          if (h.value != null) units.fmtWeight(h.value!),
          if (h.value2 != null) units.fmtLength(h.value2!),
        ];
        return (
          title: parts.isEmpty
              ? tr('Büyüme')
              : trp('Büyüme · {parts}', {'parts': parts.join(' · ')}),
          sub: trp('Ölçüm · {t}', {'t': h.at != null ? fmtTime(h.at!) : ''}),
        );
      case RecapHighlightKind.bath:
        return (
          title: tr('Banyo'),
          sub: h.at != null ? fmtTime(h.at!) : '',
        );
      case RecapHighlightKind.breast:
        return (
          title: trp('Emzirme · sol {l} dk, sağ {r} dk', {'l': h.count, 'r': h.count2}),
          sub: h.minutes2 != null
              ? trp('Ortalama {dur} arayla', {'dur': recapDur(h.minutes2!)})
              : trp('{n} beslenme', {'n': h.minutes}),
        );
      case RecapHighlightKind.bottle:
        final n = h.count ?? 1;
        return (
          title: trp('Biberon · {n} öğün, {vol}',
              {'n': n, 'vol': units.fmtVolume(h.value ?? 0)}),
          sub: [
            trp('Öğün başı ~{vol}', {'vol': units.fmtVolume((h.value ?? 0) / n)}),
            if (h.minutes2 != null)
              trp('en uzun ara {dur}', {'dur': recapDur(h.minutes2!)}),
          ].join(' · '),
        );
      case RecapHighlightKind.feedMixed:
        return (
          title: trp('{n} beslenme', {'n': h.count}),
          sub: h.minutes2 != null
              ? trp('Ortalama {dur} arayla', {'dur': recapDur(h.minutes2!)})
              : '',
        );
      case RecapHighlightKind.diaper:
        return (
          title: trp('{poo} kaka · {pee} çiş', {'poo': h.count, 'pee': h.count2}),
          sub: [
            if (h.at2 != null) trp('Son kaka {t}', {'t': fmtTime(h.at2!)}),
            if (h.text != null) h.text!,
          ].join(' · '),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _text();
    final subStyle = TextStyle(
        fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.muted);
    final canAdd = h.kind == RecapHighlightKind.medication && h.missing.isNotEmpty;

    Widget? trailing;
    if (h.first) {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: AppColors.coralDark, borderRadius: BorderRadius.circular(999)),
        child: Text(tr('İlk').toUpperCaseTr(),
            style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.4)),
      );
    } else if (h.deltaMin != null) {
      // Fark kırmızı/yeşil değil — nötr rozet (yargı yok).
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: _ground(context), borderRadius: BorderRadius.circular(999)),
        child: Text(_delta(h.deltaMin!),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: AppColors.ink2,
                fontFeatures: const [FontFeature.tabularFigures()])),
      );
    } else if (h.ok) {
      trailing = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: AppColors.growthBg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const AdenaIcon('check', size: 14, color: AppColors.growth, sw: 3),
      );
    }

    final row = Row(
      children: [
        _chip(context),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w900, height: 1.25)),
              if (t.sub.isNotEmpty || canAdd) ...[
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: t.sub,
                    children: [
                      if (canAdd)
                        TextSpan(
                          text: ' ${tr('Verdiysen ekle')}',
                          style: TextStyle(
                              color: busy ? AppColors.muted2 : AppColors.coralDark,
                              fontWeight: FontWeight.w900),
                          recognizer: TapGestureRecognizer()
                            ..onTap = busy ? null : () => onAdd(h.missing),
                        ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: subStyle,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );

    if (h.first) {
      return Container(
        margin: const EdgeInsets.only(top: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [AppColors.feedBg, AppColors.peachLight],
          ),
        ),
        child: row,
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: AppColors.line)) : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: row,
    );
  }
}
