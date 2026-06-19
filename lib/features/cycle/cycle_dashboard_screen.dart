import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_banner.dart';
import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/ring.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import '../babies/baby_controller.dart';
import '../content/article_list_screen.dart';
import 'cycle_engine.dart';
import 'cycle_entry_sheet.dart';
import 'cycle_setup_screen.dart';
import 'cycle_widgets.dart';

/// Ekran 2 — Adet Takvimi ana ekranı. Kurulmamışsa sihirbazı, kurulduysa
/// döneme göre 3 varyanttan birini (loşia / bekleme / aktif) gösterir.
class CycleScreen extends ConsumerWidget {
  const CycleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(cycleSettingsProvider);
    final entriesAsync = ref.watch(cycleEntriesProvider);
    final baby = ref.watch(activeBabyProvider);

    return settingsAsync.when(
      loading: () => const _Loading(),
      error: (e, _) => _Error(message: apiErrorText(e)),
      data: (settings) {
        // Kurulmamış → sihirbaz (emzirme durumu kurulumda zorunlu set edilir).
        if (settings.breastfeeding == null) {
          return CycleSetupView(
            initial: settings,
            babyBirthDate: baby?.birthDate,
            onDone: () => ref.invalidate(cycleSettingsProvider),
          );
        }
        return entriesAsync.when(
          loading: () => const _Loading(),
          error: (e, _) => _Error(message: apiErrorText(e)),
          data: (entries) {
            final status = computeStatus(settings, entries);
            return _Dashboard(settings: settings, entries: entries, status: status);
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent),
        body: const Center(child: CircularProgressIndicator(color: AppColors.coral)),
      );
}

class _Error extends StatelessWidget {
  final String message;
  const _Error({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            title: Text(tr('Adet Takvimi'))),
        body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(message))),
      );
}

class _Dashboard extends ConsumerWidget {
  final CycleSettings settings;
  final List<CycleEntry> entries;
  final CycleStatus status;
  const _Dashboard(
      {required this.settings, required this.entries, required this.status});

  bool get _lochiaContext => status.mode != CycleMode.active;

  CycleEntry? get _todayEntry {
    final t = DateTime.now();
    for (final e in entries) {
      if (e.date.year == t.year && e.date.month == t.month && e.date.day == t.day) {
        return e;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Adet Takvimi')),
        actions: [
          IconButton(
            tooltip: tr('Takvim'),
            icon: Icon(Icons.calendar_month, color: AppColors.roseD),
            onPressed: () => context.push('/cycle/calendar'),
          ),
          IconButton(
            tooltip: tr('İstatistikler'),
            icon: Icon(Icons.bar_chart_rounded, color: AppColors.roseD),
            onPressed: () => context.push('/cycle/stats'),
          ),
          IconButton(
            tooltip: tr('Ayarlar'),
            icon: Icon(Icons.settings, color: AppColors.roseD),
            onPressed: () => context.push('/cycle/settings'),
          ),
        ],
      ),
      bottomNavigationBar: const AdBanner(),
      body: RefreshIndicator(
        color: AppColors.rose,
        onRefresh: () async {
          ref.invalidate(cycleEntriesProvider);
          ref.invalidate(cycleSettingsProvider);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
          children: switch (status.mode) {
            CycleMode.lochia => _lochia(context, ref),
            CycleMode.waiting => _waiting(context, ref),
            CycleMode.active => _active(context, ref),
          },
        ),
      ),
    );
  }

  void _record(BuildContext context, WidgetRef ref) => showCycleEntrySheet(
        context,
        ref,
        existing: _todayEntry,
        lochiaMode: _lochiaContext,
      );

  Widget _sec(String title, {String? info, String? link, VoidCallback? onLink}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(3, 18, 3, 10),
        child: Row(
          children: [
            Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.muted,
                    letterSpacing: 0.7)),
            if (info != null) ...[
              const SizedBox(width: 6),
              AdInfoDot(title: title, body: info),
            ],
            const Spacer(),
            if (link != null)
              GestureDetector(
                onTap: onLink,
                child: Text(link,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.roseD)),
              ),
          ],
        ),
      );

  Widget _saveBtn(String label, Color color, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: AdSaveButton(label: label, color: color, onTap: onTap),
      );

  void _openLearn(BuildContext context) => context.push('/content/articles',
      extra: ArticleListArgs(
          categorySlug: 'postpartum', title: tr('Doğum sonrası bilgilendirme')));

  // ── Varyant 1 — Loşia modu ──
  List<Widget> _lochia(BuildContext context, WidgetRef ref) {
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
          color: AppColors.lochiaBg,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tr('Lohusalık Kanaması').toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: AppColors.lochia)),
                const SizedBox(width: 6),
                AdInfoDot(title: tr('Lohusalık Kanaması'), body: CycleInfo.lochiaVsPeriod),
              ],
            ),
            const SizedBox(height: 4),
            Text(trp('{n}. gün', {'n': status.lochiaDay}),
                style: const TextStyle(
                    fontSize: 42, fontWeight: FontWeight.w900, height: 1.0)),
            const SizedBox(height: 5),
            Text(tr('Bu adet değil — iyileşme süreci'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
            if (status.lochiaStart != null) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 7, runSpacing: 7, children: [
                _pill(trp('Başlangıç: {d}', {'d': fmtDayMonth(status.lochiaStart!)})),
                _pill(tr('~6. haftada bitebilir')),
              ]),
            ],
          ],
        ),
      ),
      _saveBtn(tr('Bugünkü rengi kaydet'), AppColors.lochia,
          () => _record(context, ref)),
      _sec(tr('Loşia renk rehberi'), info: CycleInfo.lochiaColorInfo),
      _lochiaGuide(context),
      _sec(tr('Dikkat belirtileri')),
      _redFlagCard(),
      _learnCard(context),
    ];
  }

  Widget _lochiaGuide(BuildContext context) {
    final steps = [
      (LochiaColor.red, tr('1–3. gün')),
      (LochiaColor.pink, tr('4–7. gün')),
      (LochiaColor.brown, tr('2–3. hafta')),
      (LochiaColor.yellowWhite, tr('Son')),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.softShadow),
      child: Column(
        children: [
          Row(
            children: [
              for (final s in steps)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Container(
                            height: 8,
                            decoration: BoxDecoration(
                                color: lochiaSwatch(s.$1),
                                borderRadius: BorderRadius.circular(4))),
                        const SizedBox(height: 5),
                        Text('${s.$2}\n${lochiaLabel(s.$1)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                height: 1.4,
                                color: AppColors.muted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
              tr('Akış zamanla azalırsa loşia; başlayıp koyulaşıp 4–7 gün sürerse '
                  'muhtemelen ilk adettir.'),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  color: AppColors.muted)),
        ],
      ),
    );
  }

  // ── Varyant 2 — Adet henüz dönmedi (bekleme) ──
  List<Widget> _waiting(BuildContext context, WidgetRef ref) {
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
        decoration: BoxDecoration(
            color: AppColors.roseBg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppColors.softShadow),
        child: Column(
          children: [
            Ring(
              size: 90,
              pct: 0,
              strokeWidth: 7,
              color: AppColors.rose,
              track: AppColors.line,
              child: const Text('🌿', style: TextStyle(fontSize: 28)),
            ),
            const SizedBox(height: 16),
            Text(tr('Döngün henüz oturmadı'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
                tr('Emzirme döneminde adet gecikmesi tamamen normaldir. '
                    'Vücudun toparlanıyor 💛'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.55,
                    color: AppColors.ink2)),
          ],
        ),
      ),
      _saveBtn(tr('İlk kanamamı kaydet'), AppColors.rose, () => _record(context, ref)),
      _sec(tr('Emzirme ve Doğurganlık'),
          link: tr('Daha fazla'), onLink: () => _openLearn(context)),
      _lamCard(context),
      const SizedBox(height: 12),
      _simpleCard(
          context,
          tr('Tahmin ne zaman başlar?'),
          tr('İlk gerçek adetini kaydettiğinde döngü takibi ve tahminler '
              'devreye girecek.')),
      _redFlagCard(),
    ];
  }

  Widget _lamCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.softShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🤱', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(tr('LAM — Laktasyonel Amenore'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                tr('Düzenli emzirme adeti geciktirebilir. Ancak ovülasyon adetten '
                    'önce döner — ilk adeti görmeden gebe kalınabilir.'),
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.55,
                    color: AppColors.ink2)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                  color: AppColors.roseBg, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  AdInfoDot(title: tr('LAM'), body: CycleInfo.lam),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tr('LAM ~%98 etkilidir — %2 başarısızlık riski var'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: AppColors.roseD)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Varyant 3 — Döngü aktif ──
  List<Widget> _active(BuildContext context, WidgetRef ref) {
    final t = _todayEntry;
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: BoxDecoration(
            color: AppColors.roseBg,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppColors.softShadow),
        child: Column(
          children: [
            Row(
              children: [
                Ring(
                  size: 84,
                  pct: (status.dayInCycle / status.avgCycleLength).clamp(0.0, 1.0),
                  strokeWidth: 8,
                  color: AppColors.rose,
                  track: AppColors.rose.withValues(alpha: 0.2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${status.dayInCycle}',
                          style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              color: AppColors.roseD)),
                      Text(tr('gün'),
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(phaseLabel(status.phase),
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900)),
                          ),
                          const SizedBox(width: 5),
                          AdInfoDot(
                              title: phaseLabel(status.phase),
                              body: CycleInfo.regularity),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          trp('{c}. döngü · {d}. gün',
                              {'c': status.cycleNumber, 'd': status.dayInCycle}),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink2)),
                      if (status.lowConfidence) ...[
                        const SizedBox(height: 8),
                        const EstBadge(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _statTile(
                        context,
                        tr('Sonraki adet'),
                        status.daysToNextPeriod == null
                            ? '—'
                            : trp('~{n} gün', {'n': status.daysToNextPeriod}),
                        AppColors.roseD)),
                const SizedBox(width: 8),
                Expanded(
                    child: _statTile(context, tr('Döngü uzunluğu'),
                        trp('~{n} gün', {'n': status.avgCycleLength}), AppColors.ink)),
              ],
            ),
          ],
        ),
      ),
      _saveBtn(tr('Bugünü kaydet'), AppColors.rose, () => _record(context, ref)),
      if (status.fertileStart != null) ...[
        _sec(tr('Doğurganlık Penceresi'),
            link: tr('Takvim'), onLink: () => context.push('/cycle/calendar')),
        _fertileCard(),
      ],
      _sec(tr('Bugünkü Belirtiler')),
      _symptomsSummary(context, ref, t),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
            color: AppColors.roseBg, borderRadius: BorderRadius.circular(18)),
        child: Text(
            '💡 ${tr('İlk döngüler düzensiz olabilir — doğum sonrası bu tamamen normaldir.')}',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                height: 1.5,
                color: AppColors.roseD)),
      ),
      _learnCard(context),
    ];
  }

  Widget _fertileCard() => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
            color: AppColors.sleepBg,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppColors.smallShadow),
        child: Row(
          children: [
            const Text('🌿', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(tr('Doğurganlık penceresi'),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF6F5FD6))),
                      const SizedBox(width: 5),
                      AdInfoDot(
                          title: tr('Doğurganlık penceresi'),
                          body: CycleInfo.fertileWindow),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                      trp('Tahmini {a} – {b}', {
                        'a': fmtDayMonth(status.fertileStart!),
                        'b': fmtDayMonth(status.fertileEnd!)
                      }),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
                ],
              ),
            ),
            const EstBadge(),
          ],
        ),
      );

  Widget _symptomsSummary(BuildContext context, WidgetRef ref, CycleEntry? t) {
    final syms = t?.symptoms ?? const [];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.softShadow),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final s in syms)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.roseBg,
                  borderRadius: BorderRadius.circular(999)),
              child: Text(symptomLabel(s),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.roseD)),
            ),
          GestureDetector(
            onTap: () => _record(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line)),
              child: Text('+ ${tr('ekle')}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.muted)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Ortak parçalar ──
  Widget _statTile(
          BuildContext context, String label, String value, Color valueColor) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Text(label.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.muted,
                    letterSpacing: 0.3)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900, color: valueColor)),
          ],
        ),
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.lochia)),
      );

  Widget _redFlagCard() => Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        decoration: BoxDecoration(
            color: AppColors.feverBg, borderRadius: BorderRadius.circular(18)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🚨', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Kırmızı bayrak'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.coralDd)),
                  const SizedBox(height: 4),
                  Text(
                      tr('Saatte 1+ ped ıslatma · büyük pıhtı · kötü koku · ateş → '
                          'doktoruna danış'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.5,
                          color: AppColors.ink2)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _simpleCard(BuildContext context, String title, String body) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.softShadow),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(body,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.ink2)),
          ],
        ),
      );

  Widget _learnCard(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: AdMenuItem(
          icon: 'heart',
          color: AppColors.roseD,
          bg: AppColors.roseBg,
          title: tr('Doğum sonrası bilgilendirme'),
          meta: tr('Loşia · LAM · ilk döngüler · ne zaman doktora'),
          onTap: () => _openLearn(context),
        ),
      );
}
