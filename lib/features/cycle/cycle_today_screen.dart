import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/age.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/in_flight_guard.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../data/cycle_long_answers.dart';
import '../../models/baby.dart';
import '../../models/cycle.dart';
import '../babies/baby_controller.dart';
import '../content/article_list_screen.dart';
import 'cycle_dial.dart';
import 'cycle_engine.dart';
import 'cycle_anchor.dart';
import 'cycle_entry_sheet.dart';
import 'cycle_guidance.dart';
import 'cycle_loss.dart';
import 'cycle_period_adjust_sheet.dart';
import 'cycle_pregnancy_bridge.dart';
import 'cycle_kit.dart';
import 'cycle_shell.dart';
import 'cycle_widgets.dart';

/// Bugün — "Bloom" durum makinesi (v3): eyebrow + imza Dial + CTA + "Bu döngü"
/// Mini kartları + şefkatli kayıt istemi. Mod: aktif / lohusalık / bekleme.
/// "Adet başlat" hızlı eylemi için uçuş koruması — `_Today` stateless (her
/// provider emit'inde yeniden kurulur) olduğundan dosya düzeyinde tek örnek.
final _quickStartGuard = InFlightGuard();

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
                  final status = computeStatus(settings, entries,
                      confirmedLongStarts:
                          ref.watch(cycleLongAnswersProvider).confirmedLong);
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
        lochiaMode: status.mode == CycleMode.lochia, // O24
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
    // Çift dokunma koruması (O8): iş sürerken ikinci dokunuş atlanır.
    await _quickStartGuard.run(() async {
      final t = DateTime.now();
      final e = _todayEntry;
      final entry = CycleEntry(
        id: e?.id ?? '',
        date: DateTime(t.year, t.month, t.day),
        flow: FlowLevel.medium,
        // D34: "ilk adetimi kaydet" loşia rengini TAŞIMAZ — taşısa kayıt
        // isPeriod=false kalır, çapa kurulmaz ama başarı toast'ı gelirdi.
        lochiaColor: null,
        symptoms: e?.symptoms ?? const [],
        mood: e?.mood,
        note: e?.note,
      );
      try {
        // A3: "İlk adetimi kaydet" açık beyandır (loşia penceresi hariç).
        await ref.read(cycleRepositoryProvider).saveEntry(entry,
            confirmedFirstPeriod: !inPostpartumLochiaWindow(t, settings));
        if (context.mounted) showAdToast(context, tr('Adet başlangıcı kaydedildi'));
      } catch (err) {
        if (context.mounted) showAdError(context, apiErrorText(err));
      }
    });
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
        child: Text(text.toUpperCaseTr(),
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
      // C1 (karar S8): "gecikti" yerine "Beklenen tarihten {n} gün geçti".
      state = 'late';
      big = '${-d2n}';
      dialLabel = tr('Gün geçti');
      dialSub = np == null
          ? null
          : trp('Beklenen tarih (tahmini): {d}', {'d': fmtDayMonth(np)});
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
      // C3: tahmin etiketleri "tahmini".
      dialLabel = tr('Tahmini yumurtlama');
      dialSub = tr('Doğurgan pencere');
      accent = AppColors.gold;
      action = tr('Adeti başlat');
      ghost = true;
    } else if (inFertile) {
      state = 'fertile';
      big = '${status.dayInCycle}';
      dialLabel = tr('Doğurgan pencere (tahmini)');
      dialSub = d2n == null ? null : trp('Sonraki ~{n} gün', {'n': d2n});
      accent = AppColors.sageD;
      action = tr('Bugünü kaydet');
    } else if (d2n != null && d2n <= 7) {
      state = 'count';
      big = '$d2n';
      dialLabel = tr('Gün kaldı');
      dialSub = np == null
          ? null
          : status.irregular
              ? trp('Sonraki adet tahmini: {d}', {'d': _nextRange()})
              : trp('Sonraki adet (tahmini) · {d}', {'d': fmtDayMonth(np)});
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
      ..._missedPeriodPrompt(context, ref),
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
                  // C5: "gebelik şansı" dili yalnız TTC'de; diğer modlarda nötr.
                  Text(_ttc ? tr('Yüksek doğurganlık') : tr('Doğurgan pencere (tahmini)'),
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.sageD)),
                  const SizedBox(height: 2),
                  Text(
                      _ttc
                          ? tr('Bugün gebelik şansı en yüksek dönemde')
                          : tr('Bugün tahmini yumurtlama günün.'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
                ]),
              ),
              cycPill(tr('~tahmini'), tone: CycTone.sage),
            ])),
        // A1: TTC dışında kart korunma notunu taşır (TTC'de not olasılık altında).
        if (!_ttc) ...[
          const SizedBox(height: 12),
          cycNoContraNote(context),
        ],
        // A2: adet döndükten sonra emzirme korunma sayılmaz.
        if (lamState(settings) == LamState.notProtective) ...[
          const SizedBox(height: 12),
          cycNote(context,
              icon: Icons.favorite_rounded,
              body: CycleTexts.lamNotProtective,
              infoTitle: tr('LAM'),
              info: CycleInfo.lam),
        ],
      ]);
    } else {
      final (String l1, String v1, String l2, String v2) = switch (state) {
        'late' => (
            tr('Beklenen tarihten'),
            trp('{n} gün geçti', {'n': -(d2n ?? 0)}),
            tr('Test'),
            -(d2n ?? 0) >= 7 ? tr('Önerilir') : tr('Gerekirse')
          ),
        'count' when status.irregular => (
            tr('Döngü günü'),
            '${status.dayInCycle} / $total',
            tr('Sonraki adet tahmini'),
            _nextRange()
          ),
        'count' => (
            tr('Döngü günü'),
            '${status.dayInCycle} / $total',
            // D5: kesinlik değil olasılık dili.
            tr('PMS belirtileri olabilir'),
            tr('2–3 gün')
          ),
        _ when status.irregular => (
            tr('Akış'),
            _todayEntry?.flow != null ? flowLabel(_todayEntry!.flow!) : '—',
            tr('Sonraki adet tahmini'),
            _nextRange()
          ),
        _ => (
            tr('Akış'),
            _todayEntry?.flow != null ? flowLabel(_todayEntry!.flow!) : '—',
            tr('Sonraki adet (tahmini)'),
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
            ? tr('Emzirme döneminde gecikme sık görülür. Endişe varsa test '
                'yapabilir ya da doktoruna danışabilirsin.')
            : _ttc
                ? tr('Gecikme gebelik işareti olabilir — birkaç gün içinde test '
                    'yapmayı düşünebilirsin.')
                : tr('Gecikmeler stres, yolculuk veya hastalıkla da olabilir. '
                    'Endişe varsa test yapabilir ya da doktoruna danışabilirsin.');
        final late = -(d2n ?? 0);
        out.addAll([
          const SizedBox(height: 12),
          cycNote(context,
              icon: Icons.favorite_rounded,
              body: late >= 7
                  // C1: ≥7 gün → açık test önerisi.
                  ? '${trp('Beklenen tarihten {n} gün geçti.', {'n': late})} '
                      '${tr('Gebelik testi yapmanı öneririz; negatifse birkaç gün '
                          'sonra tekrarlayabilirsin.')}'
                  : '${trp('Beklenen tarihten {n} gün geçti.', {'n': late})} '
                      '$lateBody'),
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
          // C5: "gebelik şansı" dili yalnız TTC'de; diğer modlarda nötr + A1 notu.
          if (_ttc && _bfActive)
            cycNote(context,
                icon: Icons.spa_rounded,
                body: tr('Doğurganlık penceresindesin — gebelik şansı artıyor. '
                    'Emziriyorsan ovülasyon ilk adetten önce dönebilir; korunma '
                    'gerekiyorsa doktoruna danış.'),
                infoTitle: tr('LAM'),
                info: CycleInfo.lam)
          else if (_ttc)
            cycNote(context,
                icon: Icons.spa_rounded,
                body: tr('Doğurganlık penceresindesin — gebelik şansı artıyor.'),
                infoTitle: tr('Doğurganlık'),
                info: CycleInfo.fertileWindow)
          else ...[
            cycNote(context,
                icon: Icons.spa_rounded,
                body: tr('Doğurgan pencere (tahmini) içindesin.'),
                infoTitle: tr('Doğurganlık'),
                info: CycleInfo.fertileWindow),
            const SizedBox(height: 12),
            cycNoContraNote(context),
          ],
        ]);
      }
    }

    // C2 (karar S10): uzun / yoğun adet → hekim önerisi (her durumda).
    if (longPeriodWarning(entries, status)) {
      out.addAll([
        const SizedBox(height: 12),
        cycNote(context,
            icon: Icons.medical_services_outlined, body: CycleTexts.longPeriod),
      ]);
    }
    if (longAmenorrheaWarning(settings, status)) {
      out.addAll([const SizedBox(height: 12), _longAmenorrheaCard(context)]);
    }

    // ── TTC (gebe kalma) bölümü: bugünün olasılığı + ovülasyon geri sayımı +
    // potansiyel doğum tarihi (bugün gebe kalınırsa, konsepsiyon+266g). ──
    if (_ttc) out.addAll(_ttcSection(context, today));

    out.addAll([const SizedBox(height: 4), _feelPrompt(context, ref)]);
    return out;
  }

  /// C4 (karar S11): TTC ipuçları + süreye göre hekim önerisi.
  List<Widget> _ttcTips(BuildContext context) {
    final months = ttcMonths(settings) ?? 0;
    final doctor = months >= 12
        ? tr('Bir yıldır (35 yaş üstünde 6 aydır) deniyorsan hekimine '
            'danışmanı öneririz.')
        : months >= 6
            ? tr('35 yaş ve üzerindeysen ve 6 aydır deniyorsan hekimine '
                'danışmanı öneririz.')
            : null;
    Widget gap() => const SizedBox(height: 12);
    return [
      if (doctor != null) ...[
        gap(),
        cycNote(context, icon: Icons.medical_services_outlined, body: doctor),
      ],
      gap(),
      cycNote(context,
          icon: Icons.favorite_border_rounded,
          body: tr('Doğurgan pencerede 1–2 günde bir ilişki önerilir.')),
      gap(),
      cycNote(context,
          icon: Icons.science_outlined,
          body: tr('Ovülasyon testleri (LH) ve servikal mukus takibi tahmini '
              'güçlendirebilir.')),
      gap(),
      cycNote(context,
          icon: Icons.medication_outlined,
          body: tr('Gebelik planlıyorsan genellikle günde 400 mikrogram folik asit '
              'önerilir; risk grubundaysan doktorun farklı doz önerebilir.')),
    ];
  }

  /// B2: düzensiz döngüde sonraki adet aralığı ("19–27 Ekim").
  String _nextRange() {
    final a = status.nextPeriodEarliest, b = status.nextPeriodLatest;
    if (a == null || b == null) {
      final np = status.nextPeriod;
      return np == null ? '—' : fmtDayMonth(np);
    }
    if (a.month == b.month && a.year == b.year) {
      return '${a.day}–${fmtDayMonth(b)}';
    }
    return '${fmtDayMonth(a)}–${fmtDayMonth(b)}';
  }

  /// B1 (karar S7): hesaptan çıkarılan uzun döngü için bir kez sorulur:
  /// "Bu dönemde bir adet kaydını unutmuş olabilir misin?" → [Kayıt ekle] /
  /// [Hayır, döngüm uzundu]. Cevap kalıcı (cycleLongAnswersProvider).
  List<Widget> _missedPeriodPrompt(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(cycleLongAnswersProvider);
    final open = status.suspectedMissedStarts
        .where((s) => !answers.answered(s))
        .toList();
    if (open.isEmpty) return const [];
    final start = open.first;
    final span = status.spans.where((s) => _dOnly(s.start) == _dOnly(start)).firstOrNull;
    final notifier = ref.read(cycleLongAnswersProvider.notifier);
    return [
      cycCard(context,
          tint: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Bu dönemde bir adet kaydını unutmuş olabilir misin?'),
                style: cycTitleStyle(size: 15)),
            const SizedBox(height: 6),
            Text(
                trp('{d} tarihinde başlayan {n} günlük döngü alışılmadık uzun '
                    'görünüyor; tahminlerde şimdilik hesaba katılmadı.',
                    {'d': fmtDayMonth(start), 'n': span?.length ?? '—'}),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                    color: AppColors.ink2)),
            const SizedBox(height: 12),
            Row(children: [
              cycAct(tr('Kayıt ekle'), icon: Icons.add_rounded, onTap: () {
                notifier.answer(start, longCycle: false);
                _openPeriodAdjust(context, ref, start: false);
              }),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton(
                  onPressed: () => notifier.answer(start, longCycle: true),
                  child: Text(tr('Hayır, döngüm uzundu'),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.muted)),
                ),
              ),
            ]),
          ])),
      const SizedBox(height: 12),
    ];
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
            label: tr('Tahmini yumurtlama'),
            value: toOvu == null
                ? '—'
                : toOvu == 0
                    ? tr('Bugün')
                    : toOvu > 0
                        ? trp('{n} gün sonra', {'n': toOvu})
                        : trp('{n} gün önce', {'n': -toOvu})),
      ]),
      // A1: olasılık satırının altında kalıcı not.
      const SizedBox(height: 12),
      cycNoContraNote(context),
      ..._ttcTips(context),
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
    // B6: hafta + TDT ana gebelik modülüyle AYNI kaynaktan (Baby.dueDate;
    // ultrasonla düzeltilmiş olabilir). Bekleyen bebek yoksa SAT'tan türetilir.
    final babies = ref.watch(babyControllerProvider).asData?.value ?? const <Baby>[];
    final expecting = babies
            .where((b) =>
                b.status == BabyStatus.expecting &&
                b.id == settings.babyId &&
                b.dueDate != null)
            .firstOrNull ??
        babies
            .where((b) => b.status == BabyStatus.expecting && b.dueDate != null)
            .firstOrNull;
    final fromBaby = expecting != null;
    final PregnancyFromLmp? info;
    if (fromBaby) {
      final days = pregnancyDays(expecting.dueDate!);
      info = PregnancyFromLmp(days ~/ 7, days % 7, expecting.dueDate!);
    } else {
      info = pregnancyFromLmp(settings.firstPeriodDate);
    }
    return [
      _heroEyebrow(tr('Gebelik')),
      _dialCenter(CycleDial(
        mode: DialMode.heal,
        day: info?.weeks ?? 0,
        healSpan: 40, // D1: gebelik halkası hafta ölçeğinde
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
          body: fromBaby
              ? tr('Gebeliğini hafta hafta, bebeğinin gelişimiyle takip etmek için '
                  'ana gebelik ekranını kullan. Hafta ve tahmini doğum tarihi ana '
                  'gebelik ekranındaki bilgiyle aynıdır.')
              : tr('Gebeliğini hafta hafta, bebeğinin gelişimiyle takip etmek için '
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
  List<Widget> _loss(BuildContext context, WidgetRef ref) => [
        // C1: kayıptan 8 hafta sonra hâlâ adet yoksa hekim kartı.
        if (longAmenorrheaWarning(settings, status)) ...[
          const SizedBox(height: 8),
          _longAmenorrheaCard(context),
        ],
        ...cycleLossToday(
          context,
          ref,
          settings,
          lastLoss: settings.lastLossDate,
        ),
      ];

  /// C1 (karar S8): uzun süre adet görmeme → hekim önerisi.
  Widget _longAmenorrheaCard(BuildContext context) => cycNote(context,
      icon: Icons.medical_services_outlined, body: CycleTexts.longAmenorrhea);

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
        sub: tr('Genellikle 4–6 hafta'),
        accent: AppColors.lochia,
      )),
      const SizedBox(height: 16),
      cycCta(context, tr('Kanama kaydet'),
          color: AppColors.lochia, onTap: () => _record(context, ref)),
      const SizedBox(height: 12),
      // B5: süre + A3: ilk 6 haftada kanama ilk adet sayılmaz.
      cycNote(context,
          clay: true,
          icon: Icons.schedule_rounded,
          body: tr('Loşia genellikle 4–6 hafta sürer, 8 haftaya uzayabilir. '
              'Doğumdan sonraki ilk 6 haftada girdiğin kanama loşia sayılır, '
              'ilk adet olarak kabul edilmez.'),
          infoTitle: tr('Loşia ve adet farkı'),
          info: CycleInfo.lochiaVsPeriod),
      const SizedBox(height: 12),
      // A4: lohusalıkta acil/aynı gün belirtileri her zaman erişilebilir.
      cycNote(context,
          icon: Icons.medical_services_outlined,
          body: tr('Hangi belirtilerde beklemeden yardım alman gerektiğini öğren.'),
          infoTitle: tr('Dikkat belirtileri'),
          info: CycleInfo.redFlags),
      if (status.lochiaDay > postpartumLochiaDays) ...[
        const SizedBox(height: 12),
        cycNote(context,
            icon: Icons.medical_services_outlined,
            body: tr('Doğumdan 6 haftadan uzun süre sonra kanaman devam ediyorsa '
                'hekimine söyle.')),
      ],
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
        // B4 (karar S2): dengeli ayrım + yeniden parlak kırmızı kanamada hekim.
        Text(tr('Kanama kesildikten sonra başlayan ve 4–7 gün süren düzenli bir '
            'kanama ilk adetin olabilir. Yeniden parlak kırmızı ve yoğunlaşan '
            'kanamada hekimine başvur.'),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.5,
                color: AppColors.ink2)),
      ])),
      ..._postpartumNotes(context),
    ];
  }

  /// A2/A5/D3 — doğum sonrası (loşia + bekleme) emzirme notları. Emzirmeyene
  /// LAM yerine erken ovülasyon metni; emzirene "ilk adetten önce gebelik"
  /// uyarısı + LAM kartı (üç koşul ya da "artık korumaz"). Emzirme bilinmiyorsa
  /// (null) LAM gösterilmez.
  List<Widget> _postpartumNotes(BuildContext context, {bool waiting = false}) {
    final bf = settings.breastfeeding;
    final lam = lamState(settings);
    final out = <Widget>[];
    void add(Widget w) => out.addAll([const SizedBox(height: 12), w]);
    if (bf == Breastfeeding.none) {
      add(cycNote(context,
          clay: !waiting,
          icon: Icons.favorite_rounded,
          body: CycleTexts.nonBreastfeeding));
      return out;
    }
    if (waiting && bf != null) {
      add(cycNote(context,
          icon: Icons.favorite_rounded,
          body: tr('Emzirme döneminde adetin geç dönmesi sık görülür.')));
    }
    add(cycNote(context,
        clay: !waiting,
        icon: Icons.shield_outlined,
        body: CycleTexts.ovulationBeforeFirstPeriod));
    if (lam != LamState.hidden) {
      out.add(CycEyebrow(tr('Emzirme & doğurganlık'),
          link: tr('Daha fazla'), onLink: () => _openLearn(context)));
      out.add(cycCard(context,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: AppColors.roseBg,
                      borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.favorite_rounded,
                      size: 18, color: AppColors.rose)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('LAM · Laktasyonel amenore'),
                    style: cycTitleStyle(size: 14.5)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
                lam == LamState.conditions
                    ? CycleTexts.lamConditions
                    : CycleTexts.lamNotProtective,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.ink2)),
          ])));
    }
    return out;
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
      if (longAmenorrheaWarning(settings, status)) ...[
        const SizedBox(height: 12),
        _longAmenorrheaCard(context),
      ],
      const SizedBox(height: 18),
      // BULGU-2: bekleme moduna bebeksiz kullanıcı da düşebilir (LMP girilmedi);
      // emzirme/LAM içeriği yalnız doğum yapmış kullanıcıya gösterilir.
      if (_hadBirth)
        ..._postpartumNotes(context, waiting: true)
      else
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
