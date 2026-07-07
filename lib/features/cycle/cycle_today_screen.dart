import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import '../content/article_list_screen.dart';
import 'cycle_dial.dart';
import 'cycle_engine.dart';
import 'cycle_entry_sheet.dart';
import 'cycle_loss.dart';
import 'cycle_period_adjust_sheet.dart';
import 'cycle_pregnancy_bridge.dart';
import 'cycle_kit.dart';
import 'cycle_shell.dart';
import 'cycle_widgets.dart';

/// Bugün — "Bloom" durum makinesi (v3): eyebrow + imza Dial + CTA + "Bu döngü"
/// Mini kartları + şefkatli kayıt istemi. Mod: aktif / lohusalık / bekleme.
class CycleTodayScreen extends ConsumerWidget {
  const CycleTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(cycleSettingsProvider);
    final entriesAsync = ref.watch(cycleEntriesProvider);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          CycleHeader(onSettings: () => context.push('/cycle/settings')),
          Expanded(
            child: settingsAsync.when(
              loading: () =>
                  Center(child: CircularProgressIndicator(color: AppColors.rose)),
              error: (e, _) => Center(child: Text(apiErrorText(e))),
              data: (settings) => entriesAsync.when(
                loading: () => Center(
                    child: CircularProgressIndicator(color: AppColors.rose)),
                error: (e, _) => Center(child: Text(apiErrorText(e))),
                data: (entries) {
                  final status = computeStatus(settings, entries);
                  return _Today(settings: settings, entries: entries, status: status);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Today extends ConsumerWidget {
  final CycleSettings settings;
  final List<CycleEntry> entries;
  final CycleStatus status;
  const _Today(
      {required this.settings, required this.entries, required this.status});

  CycleEntry? get _todayEntry {
    final t = DateTime.now();
    for (final e in entries) {
      if (e.date.year == t.year && e.date.month == t.month && e.date.day == t.day) {
        return e;
      }
    }
    return null;
  }

  void _record(BuildContext context, WidgetRef ref) => showCycleEntrySheet(
        context, ref,
        existing: _todayEntry,
        lochiaMode: status.mode != CycleMode.active,
      );

  /// My Calendar hero-buton aksiyonu: adet ayarlama takvimini açar.
  /// [start] true → başlatma modu (bugün ön-seçili); false → düzenleme (mevcut adet).
  void _openPeriodAdjust(BuildContext context, WidgetRef ref, {required bool start}) =>
      showCyclePeriodAdjustSheet(
        context, ref,
        settings: settings,
        entries: entries,
        startDate: start ? DateTime.now() : null,
        autoFillDays: status.avgPeriodDays,
      );

  /// My Calendar "Period Starts" pariteti — tek dokunuşla bugünü adet başlangıcı
  /// olarak işaretle (flow=orta). Bekleme/gecikme/erken durumlarda anında loglar
  /// ve döngü takibini başlatır/yeniler. Mevcut gün kaydı varsa diğer alanları korur.
  Future<void> _quickStartPeriod(BuildContext context, WidgetRef ref) async {
    final t = DateTime.now();
    final e = _todayEntry;
    final entry = CycleEntry(
      id: e?.id ?? '',
      date: DateTime(t.year, t.month, t.day),
      flow: FlowLevel.medium,
      lochiaColor: e?.lochiaColor,
      symptoms: e?.symptoms ?? const [],
      mood: e?.mood,
      note: e?.note,
    );
    try {
      await ref.read(cycleRepositoryProvider).saveEntry(entry);
      ref.invalidate(cycleEntriesProvider);
      ref.invalidate(cycleSettingsProvider); // ilk adet → bekleme/loşia'dan aktife geçiş
      if (context.mounted) showAdToast(context, tr('Adet başlangıcı kaydedildi'));
    } catch (err) {
      if (context.mounted) showAdError(context, apiErrorText(err));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Yaşam-döngüsü modu (Flo-tarzı) motor modundan ÖNCE gelir: kayıp/gebelik
    // özel deneyimlerdir; TTC ise aktif döngü üstüne "gebe kalma" vurgusu ekler.
    final lc = settings.lifecycleMode;
    final children = switch (lc) {
      CycleLifecycleMode.loss => _loss(context, ref),
      CycleLifecycleMode.pregnant => _pregnant(context, ref),
      _ => switch (status.mode) {
          CycleMode.lochia => _lochia(context, ref),
          CycleMode.waiting => _waiting(context, ref),
          CycleMode.active => _active(context, ref),
        },
    };
    return ListView(
      padding: EdgeInsets.fromLTRB(18, 6, 18, 24 + MediaQuery.of(context).padding.bottom),
      children: children,
    );
  }

  bool get _ttc => settings.lifecycleMode == CycleLifecycleMode.ttc;

  // BULGU-2: postpartum/emzirme metinleri yalnız doğum yapmış kullanıcıya.
  // Bebeksiz kurulum birthDate=null + breastfeeding=none yazar (cycle_setup).
  bool get _hadBirth => settings.birthDate != null;
  bool get _bfActive =>
      _hadBirth && settings.breastfeeding != Breastfeeding.none;

  /// TTC (gebe kalma) modunda üstte gösterilen vurgu şeridi.
  Widget _ttcBanner(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.sageBg, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(Icons.spa_rounded, size: 18, color: AppColors.sageD),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr('Gebe kalma modu — doğurgan pencereni takip et'),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.sageD)),
          ),
        ]),
      );

  // ── küçük başlık (Hero eyebrow, ortalı) ──
  Widget _heroEyebrow(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
                color: AppColors.muted)),
      );

  Widget _dialCenter(Widget dial) => Center(child: dial);

  /// Dial bilgi rozeti — halkadaki renklerin ne anlama geldiğini açıklar
  /// (acemi kullanıcı için [[bilgi-rozeti-ilkesi]]). Tıklanınca açıklama açılır.
  Widget _dialLegend(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: GestureDetector(
            onTap: () => showAdInfo(context, tr('Halka rehberi'), CycleInfo.dialGuide),
            behavior: HitTestBehavior.opaque,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.info_outline_rounded, size: 15, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(tr('Bu halka ne anlatıyor?'),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted)),
            ]),
          ),
        ),
      );

  String get _todayStr => fmtDayMonth(DateTime.now());

  // ════════ AKTİF DÖNGÜ ════════
  List<Widget> _active(BuildContext context, WidgetRef ref) {
    final total = status.avgCycleLength;
    final np = status.nextPeriod;
    final cycleStart = np == null ? null : cycleAddDays(_dOnly(np), -total);
    int? cd(DateTime? d) => (d == null || cycleStart == null)
        ? null
        : _dOnly(d).difference(cycleStart).inDays + 1;
    final ovu = cd(status.ovulationDay) ?? (total - (settings.lutealPhaseLength ?? 14));
    final fa = cd(status.fertileStart) ?? (ovu - 5);
    final fb = cd(status.fertileEnd) ?? (ovu + 1);

    final d2n = status.daysToNextPeriod;
    final inPeriod = status.dayInCycle <= status.avgPeriodDays;
    final isOvu = status.phase == CyclePhase.ovulation;
    // Doğurganlık penceresinde (yumurtlama hariç) dial fazı değil "Doğurganlık"
    // göstermeli — takvim "Doğurganlık" derken Bugün "Folliküler" demesin (#6).
    final today = _dOnly(DateTime.now());
    final inFertile = !isOvu &&
        status.fertileStart != null &&
        status.fertileEnd != null &&
        !today.isBefore(_dOnly(status.fertileStart!)) &&
        !today.isAfter(_dOnly(status.fertileEnd!));

    // Durum: gecikme > adet > yumurtlama > geri sayım > faz.
    final String state;
    String? big;
    Widget? dialIcon;
    String dialLabel;
    String? dialSub;
    Color accent;
    String action;
    bool ghost = false;
    if (d2n != null && d2n < 0) {
      state = 'late';
      big = '${-d2n}';
      dialLabel = tr('Gün gecikti');
      dialSub = np == null ? null : trp('{d} bekleniyordu', {'d': fmtDayMonth(np)});
      accent = AppColors.roseD;
      action = tr('Adeti kaydet');
    } else if (inPeriod) {
      state = 'period';
      big = '${status.dayInCycle}';
      dialLabel = tr('Adet · gün');
      dialSub = d2n == null ? null : trp('Sonraki ~{n} gün', {'n': d2n});
      accent = AppColors.rose;
      action = tr('Adeti düzenle');
    } else if (isOvu) {
      state = 'ovu';
      dialIcon = const Text('🌸', style: TextStyle(fontSize: 36));
      dialLabel = tr('Yumurtlama');
      dialSub = tr('Doğurgan pencere');
      accent = AppColors.gold;
      action = tr('Adeti başlat');
      ghost = true;
    } else if (inFertile) {
      state = 'fertile';
      big = '${status.dayInCycle}';
      dialLabel = tr('Doğurganlık');
      dialSub = d2n == null ? null : trp('Sonraki ~{n} gün', {'n': d2n});
      accent = AppColors.sageD;
      action = tr('Bugünü kaydet');
    } else if (d2n != null && d2n <= 7) {
      state = 'count';
      big = '$d2n';
      dialLabel = tr('Gün kaldı');
      dialSub = np == null ? null : trp('Sonraki adet · {d}', {'d': fmtDayMonth(np)});
      accent = AppColors.rose;
      action = tr('Erken geldi? Kaydet');
      ghost = true;
    } else {
      state = 'mid';
      big = '${status.dayInCycle}';
      dialLabel = switch (status.phase) {
        CyclePhase.menstrual => tr('Adet'),
        CyclePhase.follicular => tr('Folliküler'),
        CyclePhase.ovulation => tr('Yumurtlama'),
        CyclePhase.luteal => tr('Luteal'),
      };
      dialSub = d2n == null ? null : trp('Sonraki ~{n} gün', {'n': d2n});
      accent = AppColors.rose;
      action = tr('Bugünü kaydet');
    }

    final out = <Widget>[
      if (_ttc) _ttcBanner(context),
      _heroEyebrow(trp('Döngü {c} · {d}', {'c': status.cycleNumber, 'd': _todayStr})),
      _dialCenter(CycleDial(
        mode: DialMode.cycle,
        day: status.dayInCycle,
        cycleLen: total,
        periodLen: status.avgPeriodDays,
        ovu: ovu,
        fertile: [fa, fb],
        num: big,
        centerIcon: dialIcon,
        numSize: 56,
        label: dialLabel,
        sub: dialSub,
        accent: accent,
      )),
      if (status.lowConfidence)
        const Center(child: Padding(padding: EdgeInsets.only(top: 12), child: EstBadge())),
      _dialLegend(context),
      const SizedBox(height: 16),
      cycCta(context, action,
          ghost: ghost,
          onTap: () {
            // Adet sınır aksiyonları → My Calendar pariteli adet ayarlama takvimi:
            //  • adet günü → düzenle (mevcut adet; kuyruğu silerek bitir)
            //  • gecikme/yumurtlama/geri sayım → başlat (bugün ön-seçili)
            //  • doğurganlık/orta ("Bugünü kaydet") → günlük akış/belirti kaydı
            if (state == 'period') {
              _openPeriodAdjust(context, ref, start: false);
            } else if (state == 'late' || state == 'ovu' || state == 'count') {
              _openPeriodAdjust(context, ref, start: true);
            } else {
              _record(context, ref);
            }
          }),
    ];

    // ── duruma göre "Bu döngü" bölümü ──
    if (state == 'ovu') {
      out.addAll([
        CycEyebrow(tr('Doğurganlık'), suffix: tr('· açık')),
        cycCard(context,
            child: Row(children: [
              Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      color: AppColors.sageBg, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.spa_rounded, size: 24, color: AppColors.sageD)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Yüksek doğurganlık'),
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.sageD)),
                  const SizedBox(height: 2),
                  Text(tr('Bugün gebelik şansı en yüksek dönemde'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
                ]),
              ),
              cycPill(tr('~tahmini'), tone: CycTone.sage),
            ])),
        if (_bfActive) ...[
          const SizedBox(height: 12),
          cycNote(context,
              icon: Icons.favorite_rounded,
              body: tr('Emziriyorsan ovülasyon ilk adetten önce dönebilir — korunma '
                  'gerekiyorsa doktoruna danış.'),
              infoTitle: tr('LAM'),
              info: CycleInfo.lam),
        ],
      ]);
    } else {
      final (String l1, String v1, String l2, String v2) = switch (state) {
        'late' => (
            tr('Gecikme'),
            trp('{n} gün', {'n': -(d2n ?? 0)}),
            tr('Test'),
            tr('Gerekirse')
          ),
        'count' => (
            tr('Döngü günü'),
            '${status.dayInCycle} / $total',
            tr('PMS olası'),
            tr('2–3 gün')
          ),
        _ => (
            tr('Akış'),
            _todayEntry?.flow != null ? flowLabel(_todayEntry!.flow!) : '—',
            tr('Sonraki adet'),
            np == null ? '—' : fmtDayMonth(np)
          ),
      };
      out.addAll([
        CycEyebrow(tr('Bu döngü')),
        Row(children: [
          cycMini(context, label: l1, value: v1),
          const SizedBox(width: 11),
          cycMini(context, label: l2, value: v2),
        ]),
      ]);
      if (state == 'late') {
        // Bağlama duyarlı gecikme notu (BULGU-2): emziren lohusa / TTC /
        // klasik takip aynı cümleyi paylaşamaz.
        final lateBody = _bfActive
            ? tr('Emzirme döneminde gecikme çok yaygındır. Endişe varsa test '
                'yapabilir ya da doktoruna danışabilirsin.')
            : _ttc
                ? tr('Gecikme gebelik işareti olabilir — birkaç gün içinde test '
                    'yapmayı düşünebilirsin.')
                : tr('Gecikmeler stres, yolculuk veya hastalıkla da olabilir. '
                    'Endişe varsa test yapabilir ya da doktoruna danışabilirsin.');
        out.addAll([
          const SizedBox(height: 12),
          cycNote(context, icon: Icons.favorite_rounded, body: lateBody),
        ]);
      } else if (state == 'count') {
        out.addAll([
          const SizedBox(height: 12),
          cycNote(context,
              icon: Icons.notifications_none_rounded,
              body: _hadBirth
                  ? tr('Tahminler yaklaşıktır — doğum sonrası ilk döngüler değişebilir.')
                  : tr('Tahminler yaklaşıktır — döngüler doğal olarak birkaç gün '
                      'oynayabilir.'),
              infoTitle: tr('Tahmin'),
              info: CycleInfo.estimate),
        ]);
      } else if (state == 'fertile') {
        out.addAll([
          const SizedBox(height: 12),
          if (_bfActive)
            cycNote(context,
                icon: Icons.spa_rounded,
                body: tr('Doğurganlık penceresindesin — gebelik şansı artıyor. '
                    'Emziriyorsan ovülasyon ilk adetten önce dönebilir; korunma '
                    'gerekiyorsa doktoruna danış.'),
                infoTitle: tr('LAM'),
                info: CycleInfo.lam)
          else
            cycNote(context,
                icon: Icons.spa_rounded,
                body: tr('Doğurganlık penceresindesin — gebelik şansı artıyor.'),
                infoTitle: tr('Doğurganlık'),
                info: CycleInfo.fertileWindow),
        ]);
      }
    }

    // ── TTC (gebe kalma) bölümü: bugünün olasılığı + ovülasyon geri sayımı +
    // potansiyel doğum tarihi (bugün gebe kalınırsa, konsepsiyon+266g). ──
    if (_ttc) out.addAll(_ttcSection(context, today));

    out.addAll([const SizedBox(height: 4), _feelPrompt(context, ref)]);
    return out;
  }

  List<Widget> _ttcSection(BuildContext context, DateTime today) {
    final chance = conceptionChance(today, status);
    final (chanceLabel, chanceColor) = switch (chance) {
      ConceptionChance.veryHigh => (tr('Çok yüksek'), AppColors.gold),
      ConceptionChance.high => (tr('Yüksek'), AppColors.sageD),
      ConceptionChance.medium => (tr('Orta'), AppColors.sage),
      ConceptionChance.low => (tr('Düşük'), AppColors.muted),
    };
    final inWindow = chance != ConceptionChance.low;
    // Yaklaşan ovülasyona kalan gün (pencere geçtiyse sonraki döngünün penceresi).
    final nextOvu = status.fertileWindowIsNextCycle
        ? (status.upcomingFertileEnd == null
            ? null
            : cycleAddDays(status.upcomingFertileEnd!, -1))
        : status.ovulationDay;
    final toOvu = nextOvu == null ? null : _dOnly(nextOvu).difference(today).inDays;
    // Naegele (konsepsiyondan): bugün gebe kalınırsa TDT ≈ bugün + 266 gün.
    final potentialDue = cycleAddDays(today, 266);

    return [
      const SizedBox(height: 14),
      CycEyebrow(tr('Gebe kalma'), suffix: inWindow ? tr('· pencere açık') : null),
      Row(children: [
        cycMini(context, label: tr('Bugün olasılık'), value: chanceLabel,
            valueColor: chanceColor),
        const SizedBox(width: 11),
        cycMini(
            context,
            label: tr('Yumurtlama'),
            value: toOvu == null
                ? '—'
                : toOvu == 0
                    ? tr('Bugün')
                    : toOvu > 0
                        ? trp('{n} gün sonra', {'n': toOvu})
                        : trp('{n} gün önce', {'n': -toOvu})),
      ]),
      if (inWindow) ...[
        const SizedBox(height: 12),
        cycNote(context,
            icon: Icons.child_friendly_rounded,
            body: trp(
                'Bugün gebe kalırsan tahmini doğum tarihi: {d}. Bu bir '
                    'tahmindir — döngüler oturdukça netleşir.',
                {'d': fmtDayMonthYear(potentialDue)}),
            infoTitle: tr('Doğurganlık penceresi'),
            info: CycleInfo.fertileWindow),
      ],
    ];
  }

  // ════════ GEBELİK (yaşam-döngüsü köprüsü) ════════
  // Kaynak = ana gebelik modülü; burada LMP'den türetilmiş salt-okunur özet.
  List<Widget> _pregnant(BuildContext context, WidgetRef ref) {
    final info = pregnancyFromLmp(settings.firstPeriodDate);
    return [
      _heroEyebrow(tr('Gebelik')),
      _dialCenter(CycleDial(
        mode: DialMode.heal,
        day: info?.weeks ?? 0,
        num: info == null ? '—' : '${info.weeks}',
        numSize: 54,
        label: tr('Hafta'),
        sub: info == null ? tr('Gebelik takibi') : trp('{d} günlük', {'d': info.days}),
        accent: AppColors.coralDd,
      )),
      const SizedBox(height: 16),
      if (info != null)
        cycCard(context,
            child: Row(children: [
              Icon(Icons.event_rounded, size: 20, color: AppColors.coralDd),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Tahmini doğum'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                  Text(fmtDayMonthYear(info.dueDate),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ]),
              ),
            ])),
      const SizedBox(height: 12),
      cycNote(context,
          icon: Icons.info_outline_rounded,
          body: tr('Gebeliğini hafta hafta, bebeğinin gelişimiyle takip etmek için '
              'ana gebelik ekranını kullan. Buradaki tarih son adetinden hesaplanır.')),
      const SizedBox(height: 14),
      cycCta(context, tr('Gebelik ekranına git'),
          onTap: () => openPregnancyScreen(context, ref, settings)),
      const SizedBox(height: 10),
      Center(
        child: TextButton(
          onPressed: () => showCycleLossOrEnd(context, ref, settings),
          child: Text(tr('Durumu güncelle'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted)),
        ),
      ),
    ];
  }

  // ════════ İYİLEŞME (gebelik kaybı — şefkatli mod) ════════
  List<Widget> _loss(BuildContext context, WidgetRef ref) => cycleLossToday(
        context,
        ref,
        settings,
        lastLoss: settings.lastLossDate,
      );

  // ════════ LOHUSALIK ════════
  List<Widget> _lochia(BuildContext context, WidgetRef ref) {
    final stages = [
      (lochiaSwatch(LochiaColor.red), tr('Kırmızı')),
      (lochiaSwatch(LochiaColor.pink), tr('Pembe')),
      (lochiaSwatch(LochiaColor.brown), tr('Kahve')),
      (lochiaSwatch(LochiaColor.yellowWhite), tr('Sarı')),
    ];
    return [
      _heroEyebrow(trp('Doğum +{n} gün · {d}', {'n': status.lochiaDay, 'd': _todayStr})),
      _dialCenter(CycleDial(
        mode: DialMode.heal,
        day: status.lochiaDay,
        num: '${status.lochiaDay}',
        numSize: 54,
        label: tr('Lohusalık · gün'),
        sub: tr('İyileşme · 0–6 hafta'),
        accent: AppColors.lochia,
      )),
      const SizedBox(height: 16),
      cycCta(context, tr('Kanama kaydet'),
          color: AppColors.lochia, onTap: () => _record(context, ref)),
      CycEyebrow(tr('Loşia rengi'), suffix: tr('· tahmin yok')),
      cycCard(context, soft: true, child: Column(children: [
        Row(children: [
          for (var i = 0; i < stages.length; i++) ...[
            if (i > 0) const SizedBox(width: 9),
            Expanded(
              child: Column(children: [
                Container(
                    height: 38,
                    decoration: BoxDecoration(
                        color: stages[i].$1, borderRadius: BorderRadius.circular(12))),
                const SizedBox(height: 6),
                Text(stages[i].$2,
                    style: TextStyle(
                        fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
              ]),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        Text(tr('Akış zamanla azalıp açılıyorsa loşia; durup koyulaşıp 4–7 gün '
            'sürerse muhtemelen ilk adettir.'),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.5,
                color: AppColors.ink2)),
      ])),
      const SizedBox(height: 12),
      cycNote(context,
          clay: true,
          icon: Icons.favorite_rounded,
          body: tr('Emziriyorsan adet gecikebilir (LAM). İlk gerçek adetini girdiğinde '
              'döngü takibi otomatik başlar.'),
          infoTitle: tr('LAM'),
          info: CycleInfo.lam),
    ];
  }

  // ════════ İLK ADET BEKLENİYOR ════════
  List<Widget> _waiting(BuildContext context, WidgetRef ref) {
    return [
      _heroEyebrow(trp('Bekleme · {d}', {'d': _todayStr})),
      _dialCenter(CycleDial(
        mode: DialMode.waiting,
        accent: AppColors.rose,
        centerIcon: const Text('🌿', style: TextStyle(fontSize: 32)),
        label: tr('Bekleniyor'),
        sub: tr('Henüz adet dönmedi'),
      )),
      const SizedBox(height: 16),
      cycCta(context, tr('İlk adetimi kaydet'),
          onTap: () => _quickStartPeriod(context, ref)),
      const SizedBox(height: 18),
      // BULGU-2: bekleme moduna bebeksiz kullanıcı da düşebilir (LMP girilmedi);
      // emzirme/LAM içeriği yalnız doğum yapmış kullanıcıya gösterilir.
      if (_hadBirth) ...[
        cycNote(context,
            icon: Icons.favorite_rounded,
            body: tr('Emzirme döneminde adetin geç dönmesi tamamen normaldir. '
                'Vücudun toparlanıyor.')),
        CycEyebrow(tr('Emzirme & doğurganlık'),
            link: tr('Daha fazla'), onLink: () => _openLearn(context)),
        cycCard(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppColors.roseBg, borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.favorite_rounded, size: 18, color: AppColors.rose)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('LAM · Laktasyonel amenore'),
                  style: cycTitleStyle(size: 14.5)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(tr('Düzenli emzirme adeti geciktirir; ancak ovülasyon adetten önce döner '
              '— ilk adeti görmeden gebe kalınabilir (~%2 risk).'),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  color: AppColors.ink2)),
        ])),
      ] else
        cycNote(context,
            icon: Icons.favorite_rounded,
            body: tr('Son adetinin ilk gününü kaydettiğinde döngü takibi ve '
                'tahminler burada başlar.')),
    ];
  }

  // ── şefkatli kayıt istemi (4 emoji + Kayıt ekle) ──
  Widget _feelPrompt(BuildContext context, WidgetRef ref) {
    const emojis = ['🌸', '🙂', '😴', '😣'];
    return cycCard(context, tint: true, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Bugün nasıl geçti?'), style: cycTitleStyle(size: 18)),
        const SizedBox(height: 4),
        Text(tr('Akış, belirti ve ruh halini ekle — tahminlerin zamanla gelişir.'),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, height: 1.45, color: AppColors.ink2)),
        const SizedBox(height: 14),
        Row(children: [
          for (final e in emojis) ...[
            GestureDetector(
              onTap: () => _record(context, ref),
              child: Container(
                width: 42,
                height: 42,
                margin: const EdgeInsets.only(right: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.line, width: 1.6)),
                child: Text(e, style: const TextStyle(fontSize: 19)),
              ),
            ),
          ],
          const Spacer(),
          cycAct(tr('Kayıt ekle'),
              icon: Icons.add_rounded, onTap: () => _record(context, ref)),
        ]),
      ],
    ));
  }

  void _openLearn(BuildContext context) => context.push('/content/articles',
      extra: ArticleListArgs(
          categorySlug: 'postpartum', title: tr('Doğum sonrası bilgilendirme')));

  DateTime _dOnly(DateTime x) => DateTime(x.year, x.month, x.day);
}
