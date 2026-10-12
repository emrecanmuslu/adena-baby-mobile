import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/age.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../data/notification_prefs.dart';
import '../../data/sync_gate.dart';
import '../../core/premium_gate.dart';
import '../../core/source_citation.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/baby.dart';
import '../../models/vaccine.dart';
import '../babies/baby_controller.dart';
import '../charts/growth_report.dart';
import '../settings/notification_prefs_controller.dart';

/// Aşı Takvimi (Claude Design "01 Yaş grupları"): üstte sıradaki aşı kartı,
/// bekleyen (tarihi geçmiş) aşı uyarısı, özet ve aya göre katlanır gruplar.
/// İsteğe bağlı/ücretli aşılar her grupta ayrı başlık altında, nötr gösterilir.
class VaccinesScreen extends ConsumerStatefulWidget {
  const VaccinesScreen({super.key});

  @override
  ConsumerState<VaccinesScreen> createState() => _VaccinesScreenState();
}

class _VaccinesScreenState extends ConsumerState<VaccinesScreen> {
  // Açık gruplar (ay). İlk veride bekleyen + sıradaki gruplar açılır; sonra
  // kullanıcının aç/kapa seçimi korunur (işaretleme sonrası yeniden yüklemede).
  Set<int>? _open;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final async = ref.watch(vaccinesProvider(baby.id));
    final canWrite = ref.watch(canFullWriteProvider(baby.id));
    final vaccines = async.asData?.value ?? const <Vaccine>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Aşı Takvimi')),
            Text('${baby.name} · ${babyAgeShort(baby)}',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ],
        ),
        actions: [
          if (canWrite && vaccines.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: _ShareAction(
                busy: _sharing,
                onTap: () => _share(baby, vaccines),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.coral)),
        error: (e, _) => Center(child: Text(apiErrorText(e))),
        data: (vaccines) {
          if (vaccines.isEmpty) return _Empty(canEdit: canWrite);
          final s = VaccineSchedule.build(vaccines, DateTime.now());
          _open ??= {
            for (final g in s.groups)
              if (g.status == VaccineGroupStatus.late ||
                  g.status == VaccineGroupStatus.next)
                g.months,
          };
          final remindOn = ref.watch(notifPrefProvider(NotificationPrefs.vaccine));
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, 28 + MediaQuery.of(context).padding.bottom),
            children: [
              if (!canWrite) const _ReadOnlyNote(),
              if (s.nextGroup != null)
                _NextCard(group: s.nextGroup!, remindOn: remindOn)
              else if (s.mandatoryDone == s.mandatoryTotal)
                const _AllDoneCard(),
              if (s.late.isNotEmpty)
                _LateCard(
                  late: s.late,
                  canWrite: canWrite,
                  onMark: (v) => _mark(baby.id, v, s.statusOf(v)),
                ),
              _Summary(schedule: s),
              adSec(tr('Yaşa göre takvim')),
              for (final g in s.groups)
                _GroupCard(
                  group: g,
                  schedule: s,
                  open: _open!.contains(g.months),
                  canWrite: canWrite,
                  onToggle: () => setState(() {
                    if (!_open!.remove(g.months)) _open!.add(g.months);
                  }),
                  onMark: (v) => _mark(baby.id, v, s.statusOf(v)),
                ),
              const SizedBox(height: 18),
              if (canWrite)
                _ShareButton(busy: _sharing, onTap: () => _share(baby, vaccines)),
              // Apple guideline 1.4.1 — tıbbi bilgi (aşı takvimi) kaynak atfı.
              // Takvim locale'e göre değişir (TR: Sağlık Bakanlığı, diğer: CDC).
              Center(
                child: I18n.instance.locale == 'tr'
                    ? const SourceCitation(
                        label: 'Kaynak: T.C. Sağlık Bakanlığı Aşı Takvimi',
                        url: 'https://asi.saglik.gov.tr')
                    : SourceCitation(
                        label: tr('Kaynak: ABD CDC Aşı Takvimi (bilgilendirme amaçlıdır)'),
                        url:
                            'https://www.cdc.gov/vaccines/imz-schedules/child-easyread.html'),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${tr('Bilgilendirme amaçlıdır, tıbbi tavsiye yerine geçmez.')} '
                  '${baby.birthDate == null ? '' : trp('Takvim doğum tarihinden ({d}) hesaplanır.', {'d': fmtDayMonthYear(baby.birthDate!)})}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                      height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Aşı kartı PDF paylaşımı — kreş/okul kaydı gibi resmi gerekliliklerde
  /// kullanılabilecek bir özet (premium; growth report ile aynı `/report` ucu,
  /// backend 'vaccines' anahtarını görünce bu tabloyu render eder).
  void _share(Baby baby, List<Vaccine> vaccines) {
    if (_sharing) return;
    requirePremium(
      context,
      ref,
      feature: tr('Aşı kartı paylaşımı'),
      desc: tr('Aşı takvimini, yapılan/yapılmayan durumuyla, kreş/okul kaydı '
          'gibi ihtiyaçlar için PDF olarak paylaş.'),
      onAllowed: () async {
        setState(() => _sharing = true);
        try {
          final sorted = [...vaccines]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
          final payload = buildVaccineReportPayload(baby, sorted);
          await shareGrowthReport(ref, baby.id, payload);
        } catch (e) {
          if (mounted) showAdError(context, apiErrorText(e));
        } finally {
          if (mounted) setState(() => _sharing = false);
        }
      },
    );
  }

  /// İşaretle / tarihi güncelle / geri al — tarih seçimli sheet üzerinden.
  Future<void> _mark(String babyId, Vaccine v, VaccineStatus status) async {
    // Sağlık kayıtları yalnız owner/parent — bakıcı salt-okunur.
    if (!ref.read(canFullWriteProvider(babyId))) { // N1
      showAdToast(context, tr('Bu işlem için ebeveyn/sahip olmalısın'));
      return;
    }
    final res = await showModalBottomSheet<_MarkResult>(
      context: context,
      showDragHandle: false,
      shape: adSheetShape,
      isScrollControlled: true,
      builder: (_) => _MarkSheet(vaccine: v, status: status),
    );
    if (res == null || !mounted) return;
    final repo = ref.read(healthRepositoryProvider);
    final n = parseVaccineName(v.name);
    final label = n.dose.isEmpty ? n.primary : '${n.primary} · ${n.dose}';
    try {
      if (res.undo) {
        await repo.setVaccineDone(babyId, v.key, done: false);
        ref.invalidate(vaccinesProvider(babyId));
        if (mounted) showAdToast(context, tr('Geri alındı'));
        return;
      }
      await repo.setVaccineDone(babyId, v.key, done: true, date: res.date);
      ref.invalidate(vaccinesProvider(babyId));
      if (!mounted) return;
      if (v.done) {
        showAdToast(context, tr('Tarih güncellendi'));
      } else {
        showAdToast(
          context,
          trp('{name} kaydedildi', {'name': label}),
          onUndo: () async {
            try {
              await repo.setVaccineDone(babyId, v.key, done: false);
              ref.invalidate(vaccinesProvider(babyId));
            } catch (e) {
              if (mounted) showAdError(context, apiErrorText(e));
            }
          },
        );
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }
}

// ── Yardımcılar ──

Color get _coralT =>
    AppColors.brightness == Brightness.dark ? const Color(0xFFFFAF9E) : AppColors.coralDd;
Color get _growthD =>
    AppColors.brightness == Brightness.dark ? const Color(0xFF7BD3AE) : const Color(0xFF349970);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _daysFromToday(DateTime d) {
  final n = DateTime.now();
  return _day(d).difference(DateTime(n.year, n.month, n.day)).inDays;
}

/// Bugüne göre göreli zaman: "Bugün", "27 gün sonra", "3 ay sonra", "2 hafta önce".
String _rel(DateTime d) {
  final n = _daysFromToday(d);
  if (n == 0) return tr('Bugün');
  if (n == 1) return tr('Yarın');
  if (n == -1) return tr('Dün');
  if (n > 0) {
    if (n <= 31) return trp('{n} gün sonra', {'n': n});
    if (n < 730) return trp('{n} ay sonra', {'n': (n / 30.4).round()});
    return trp('{n} yıl sonra', {'n': (n / 365).round()});
  }
  final a = -n;
  if (a < 14) return trp('{n} gün önce', {'n': a});
  if (a < 62) return trp('{n} hafta önce', {'n': (a / 7).round()});
  return trp('{n} ay önce', {'n': (a / 30.4).round()});
}

/// Grup adı: "Doğumda", "6. ay", (24 aydan sonra tam yıllar) "4 yaş".
String _groupLabel(int m) {
  if (m == 0) return tr('Doğumda');
  if (m > 24 && m % 12 == 0) return trp('{n} yaş', {'n': m ~/ 12});
  return trp('{n}. ay', {'n': m});
}

/// Aşı adı — açık ad büyük + doz rozeti, kısaltma/açıklama küçük alt satırda.
class _VacName extends StatelessWidget {
  final Vaccine vaccine;
  final bool muted;
  const _VacName(this.vaccine, {this.muted = false});

  @override
  Widget build(BuildContext context) {
    final n = parseVaccineName(vaccine.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(n.primary,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: muted ? FontWeight.w800 : FontWeight.w900,
                    height: 1.3,
                    color: muted ? AppColors.ink2 : AppColors.ink)),
            if (n.dose.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: fieldBg(context), borderRadius: BorderRadius.circular(999)),
                child: Text(n.dose,
                    style: TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.ink2)),
              ),
          ],
        ),
        if (n.secondary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(n.secondary,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                    height: 1.3)),
          ),
      ],
    );
  }
}

/// Durum etiketi (design .tag) — yalnız tarihi geçmiş / sıradaki satırlarda.
Widget _tag(String text, Color fg, Color bg, {String? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AdenaIcon(icon, size: 11, color: fg, sw: 3),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: fg)),
          ),
        ],
      ),
    );

Widget? _statusTag(Vaccine v, VaccineStatus st) => switch (st) {
      VaccineStatus.late => _tag(trp('Tarihi geçti · {d}', {'d': fmtDayMon(v.dueDate)}),
          AppColors.goldD, AppColors.goldBg),
      VaccineStatus.next =>
        _tag(trp('Sıradaki · {d}', {'d': _rel(v.dueDate)}), _coralT, AppColors.peachLight),
      VaccineStatus.done when v.doneDate != null => _tag(
          trp('Yapıldı · {d}', {'d': fmtDayMon(v.doneDate!)}),
          _growthD,
          AppColors.growthBg,
          icon: 'check'),
      VaccineStatus.optional =>
        _tag(tr('İsteğe bağlı'), AppColors.muted, AppColors.line),
      _ => null,
    };

// ── Bölümler ──

/// Bakıcı (salt okunur) notu.
class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
          color: AppColors.sleepBg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const AdenaIcon('shield', size: 16, color: AppColors.sleep),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Salt okunur görünüm'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                Text(tr('Bakıcı olarak görüntülüyorsun. Aşıları ebeveynler işaretler.'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink2,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sıradaki aşı kartı — grup tarihi, kalan süre, o gün yapılacak dozlar.
class _NextCard extends StatelessWidget {
  final VaccineGroup group;
  final bool remindOn;
  const _NextCard({required this.group, required this.remindOn});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final rows = <Widget>[
      for (final v in group.mandatory.where((v) => !v.done)) _row(v, optional: false),
      for (final v in group.optional) _row(v, optional: true),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.76, -1),
          radius: 1.3,
          colors: [AppColors.peachLight, AppColors.peach],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(999),
                boxShadow: AppColors.smallShadow),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AdenaIcon('syringe', size: 12, color: _coralT, sw: 2.4),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                      trp('Sıradaki aşı · {g}', {'g': _groupLabel(group.months)})
                          .toUpperCaseTr(),
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                          color: _coralT)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('${fmtDayMonth(group.dueDate)}, ${fmtWeekdayFull(group.dueDate)}',
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.4)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.coral,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.coralDd.withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Text(_rel(group.dueDate),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              if (remindOn)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AdenaIcon('bell', size: 14, color: AppColors.ink2),
                    const SizedBox(width: 5),
                    Text(tr("O sabah 09:00'da hatırlatılır"),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink2)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration:
                BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.line),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Vaccine v, {required bool optional}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: optional ? Colors.transparent : AppColors.coral,
                border: optional ? Border.all(color: AppColors.muted2, width: 2) : null,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(child: _VacName(v, muted: optional)),
            if (optional) ...[
              const SizedBox(width: 8),
              v.done
                  ? _tag(tr('Yapıldı'), _growthD, AppColors.growthBg, icon: 'check')
                  : _tag(tr('İsteğe bağlı'), AppColors.muted, AppColors.line),
            ],
          ],
        ),
      );
}

/// Tüm zorunlu aşılar tamamsa sıradaki kartının yerine kısa kutlama.
class _AllDoneCard extends StatelessWidget {
  const _AllDoneCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.growthBg, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          const AdenaIcon('check', size: 22, color: AppColors.growth, sw: 2.6),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr('Tüm zorunlu aşılar tamamlandı 🎉'),
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900, color: _growthD)),
          ),
        ],
      ),
    );
  }
}

/// Bekleyen (tarihi geçmiş, işaretlenmemiş zorunlu) aşı uyarısı — panik
/// yaratmayan bal rengi. Tek aşıysa doğrudan işaretleme butonu da verir.
class _LateCard extends StatelessWidget {
  final List<Vaccine> late;
  final bool canWrite;
  final void Function(Vaccine) onMark;
  const _LateCard({required this.late, required this.canWrite, required this.onMark});

  @override
  Widget build(BuildContext context) {
    final single = late.length == 1;
    final v = late.first;
    final n = parseVaccineName(v.name);
    final name = [
      n.primary,
      if (n.secondary.isNotEmpty) '(${n.secondary})',
      if (n.dose.isNotEmpty) n.dose,
    ].join(' ');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.goldBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: AdenaIcon('clock', size: 17, color: AppColors.goldD),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    single
                        ? tr('Bekleyen bir aşı var')
                        : trp('{n} aşı işaretlenmemiş görünüyor', {'n': late.length}),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                    single
                        ? trp(
                            '{name}, {d} tarihinde planlanmıştı. Yaptırdıysan '
                            'işaretleyebilirsin; yaptırmadıysan doktorunla yeni bir '
                            'gün belirleyebilirsin.',
                            {'name': name, 'd': fmtDayMonth(v.dueDate)})
                        : tr('Yaptırdıysan aşağıdan tarihiyle işaretleyebilirsin; '
                            'yaptırmadıysan doktorunla yeni bir gün belirleyebilirsin.'),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink2,
                        height: 1.5)),
                if (single && canWrite) ...[
                  const SizedBox(height: 10),
                  _MarkButton(
                    label: tr('Yapıldı olarak işaretle'),
                    late: true,
                    onTap: () => onMark(v),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yapılan/toplam özeti + zorunlu sayısı + ilerleme çubuğu.
class _Summary extends StatelessWidget {
  final VaccineSchedule schedule;
  const _Summary({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final s = schedule;
    final ratio = s.total > 0 ? s.done / s.total : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${s.done} / ${s.total}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr('aşı yapıldı'),
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink2)),
              ),
              Text(
                  trp('Zorunlu {a}/{b}',
                      {'a': s.mandatoryDone, 'b': s.mandatoryTotal}),
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 7,
              child: Stack(
                children: [
                  Container(color: AppColors.line),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFF6FCCA4), AppColors.growth]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yaş grubu kartı — başlık (ay rozeti + tarih + durum) ve katlanır gövde.
class _GroupCard extends StatelessWidget {
  final VaccineGroup group;
  final VaccineSchedule schedule;
  final bool open;
  final bool canWrite;
  final VoidCallback onToggle;
  final void Function(Vaccine) onMark;
  const _GroupCard({
    required this.group,
    required this.schedule,
    required this.open,
    required this.canWrite,
    required this.onToggle,
    required this.onMark,
  });

  @override
  Widget build(BuildContext context) {
    final g = group;
    final m = g.months;
    final yearly = m > 24 && m % 12 == 0;
    final (Color badgeBg, Color badgeFg) = switch (g.status) {
      VaccineGroupStatus.done => (AppColors.growthBg, _growthD),
      VaccineGroupStatus.late => (AppColors.goldBg, AppColors.goldD),
      VaccineGroupStatus.next => (AppColors.coral, Colors.white),
      VaccineGroupStatus.future => (fieldBg(context), AppColors.ink2),
    };
    final upcoming = g.status == VaccineGroupStatus.next ||
        g.status == VaccineGroupStatus.future;
    final sub = [
      fmtDayMonthYear(g.dueDate),
      if (upcoming) _rel(g.dueDate),
      if (g.optional.isNotEmpty) trp('+{n} isteğe bağlı', {'n': g.optional.length}),
    ].join(' · ');
    final countAll = g.mandatory.isNotEmpty ? g.mandatory.length : g.optional.length;
    final Widget statusText = switch (g.status) {
      VaccineGroupStatus.done => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdenaIcon('check', size: 13, color: _growthD, sw: 3),
            const SizedBox(width: 4),
            Text(tr('Tamamlandı'), style: _gs(_growthD)),
          ],
        ),
      VaccineGroupStatus.late =>
        Text(trp('{n} bekliyor', {'n': g.lateCount}), style: _gs(AppColors.goldD)),
      VaccineGroupStatus.next => Text(tr('Sıradaki'), style: _gs(_coralT)),
      VaccineGroupStatus.future =>
        Text(trp('{n} aşı', {'n': countAll}), style: _gs(AppColors.muted)),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: g.status == VaccineGroupStatus.next ? AppColors.peach : AppColors.line),
        boxShadow: AppColors.smallShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 62),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: badgeBg, borderRadius: BorderRadius.circular(14)),
                        alignment: Alignment.center,
                        child: m == 0
                            ? AdenaIcon('baby', size: 18, color: badgeFg, sw: 2.2)
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${yearly ? m ~/ 12 : m}',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                          color: badgeFg)),
                                  const SizedBox(height: 2),
                                  Text((yearly ? tr('yaş') : tr('ay')).toUpperCaseTr(),
                                      style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w900,
                                          height: 1,
                                          letterSpacing: 0.3,
                                          color: badgeFg)),
                                ],
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_groupLabel(m),
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 1),
                            Text(sub,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.muted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      statusText,
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: AdenaIcon('chevD', size: 18, color: AppColors.muted2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: !open
                  ? const SizedBox(width: double.infinity)
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                      decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.line))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < g.mandatory.length; i++)
                            _row(g.mandatory[i], divider: i > 0),
                          if (g.optional.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 12, bottom: 2),
                              child: Row(
                                children: [
                                  Text(
                                      (I18n.instance.locale == 'tr'
                                              ? tr('İsteğe bağlı · ücretli')
                                              : tr('İsteğe bağlı'))
                                          .toUpperCaseTr(),
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.7,
                                          color: AppColors.muted)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Container(height: 1, color: AppColors.line)),
                                ],
                              ),
                            ),
                            for (var i = 0; i < g.optional.length; i++)
                              _row(g.optional[i], divider: i > 0, optional: true),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _gs(Color c) => TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: c);

  Widget _row(Vaccine v, {required bool divider, bool optional = false}) {
    final st = schedule.statusOf(v);
    final showTag = st == VaccineStatus.late || st == VaccineStatus.next;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: divider
          ? BoxDecoration(border: Border(top: BorderSide(color: AppColors.line)))
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VacName(v, muted: optional),
                if (showTag) ...[
                  const SizedBox(height: 5),
                  _statusTag(v, st)!,
                ],
              ],
            ),
          ),
          const SizedBox(width: 11),
          if (canWrite)
            _MarkButton(
              label: v.done && v.doneDate != null ? fmtDayMon(v.doneDate!) : tr('Yapıldı'),
              done: v.done,
              late: st == VaccineStatus.late,
              onTap: () => onMark(v),
            )
          else if (v.done)
            Container(
              width: 28,
              height: 28,
              decoration:
                  const BoxDecoration(color: AppColors.growth, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const AdenaIcon('check', size: 14, color: Colors.white, sw: 3),
            ),
        ],
      ),
    );
  }
}

/// "✓ Yapıldı" hap butonu (44 px) — yapıldıysa yeşil zeminde tarih gösterir.
class _MarkButton extends StatelessWidget {
  final String label;
  final bool done;
  final bool late;
  final VoidCallback onTap;
  const _MarkButton(
      {required this.label, this.done = false, this.late = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: done ? AppColors.growthBg : Theme.of(context).colorScheme.surface,
      shape: StadiumBorder(
        side: done
            ? BorderSide.none
            : BorderSide(
                color: late ? AppColors.gold.withValues(alpha: 0.55) : AppColors.line2,
                width: 1.5),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AdenaIcon('check', size: 15, color: done ? _growthD : AppColors.growth, sw: 3),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: done ? _growthD : AppColors.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Paylaşım ──

/// AppBar'daki paylaşım ikonu — premium tacıyla.
class _ShareAction extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ShareAction({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              shape: const CircleBorder(),
              elevation: 0,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onTap,
                child: Center(
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.coral))
                      : AdenaIcon('doc', size: 18, color: _coralT),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: -3,
            end: -3,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFC36B), Color(0xFFF29A3A)]),
                border: Border.all(color: AppColors.cream, width: 2),
              ),
              alignment: Alignment.center,
              child: const AdenaIcon('star', size: 8, color: Colors.white, sw: 2.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alt "Aşı kartını paylaş (PDF)" butonu + Premium rozeti.
class _ShareButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _ShareButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.line2, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: AppColors.coral))
                else
                  AdenaIcon('doc', size: 18, color: _coralT),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                      busy ? tr('Hazırlanıyor…') : tr('Aşı kartını paylaş (PDF)'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 9),
                const AdProBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── İşaretleme sheet'i ──

class _MarkResult {
  final DateTime? date;
  final bool undo;
  const _MarkResult.date(DateTime this.date) : undo = false;
  const _MarkResult.undo()
      : date = null,
        undo = true;
}

/// "Ne zaman yapıldı?" — hızlı seçim (Bugün/Dün/Planlanan gün) + takvim.
/// Gelecek tarih seçilemez. Yapılmış aşıda tarih güncelleme + geri al.
class _MarkSheet extends StatefulWidget {
  final Vaccine vaccine;
  final VaccineStatus status;
  const _MarkSheet({required this.vaccine, required this.status});

  @override
  State<_MarkSheet> createState() => _MarkSheetState();
}

class _MarkSheetState extends State<_MarkSheet> {
  late DateTime _date;
  late final DateTime _today;

  @override
  void initState() {
    super.initState();
    _today = _day(DateTime.now());
    _date = _day(widget.vaccine.doneDate ?? _today);
    if (_date.isAfter(_today)) _date = _today;
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vaccine;
    final late = widget.status == VaccineStatus.late;
    final yesterday = _today.subtract(const Duration(days: 1));
    final due = _day(v.dueDate);
    final quick = <(String, DateTime)>[
      (tr('Bugün'), _today),
      (tr('Dün'), yesterday),
      if (due.isBefore(yesterday))
        (trp('Planlanan gün · {d}', {'d': fmtDayMon(due)}), due),
    ];
    final tag = _statusTag(v, widget.status);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: adGrabHandle()),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: late ? AppColors.goldBg : AppColors.peachLight,
                        borderRadius: BorderRadius.circular(15)),
                    alignment: Alignment.center,
                    child: AdenaIcon('syringe',
                        size: 22, color: late ? AppColors.goldD : _coralT),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _VacName(v),
                        if (tag != null) ...[const SizedBox(height: 7), tag],
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 18, 2, 9),
                child: Text(tr('Ne zaman yapıldı?').toUpperCaseTr(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                        color: AppColors.muted)),
              ),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final (label, d) in quick)
                    _QuickChip(
                      label: label,
                      on: _date == d,
                      onTap: () => setState(() => _date = d),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                    color: fieldBg(context), borderRadius: BorderRadius.circular(18)),
                child: CalendarDatePicker(
                  // Hızlı seçimde takvim o aya gitsin diye yeniden kurulur.
                  key: ValueKey(_date),
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: _today,
                  onDateChanged: (d) => setState(() => _date = _day(d)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 9, 2, 14),
                child: Row(
                  children: [
                    AdenaIcon('clock', size: 13, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tr('Gelecek bir tarih seçilemez.'),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ),
                  ],
                ),
              ),
              AdSaveButton(
                label: v.done
                    ? trp('Tarihi güncelle · {d}', {'d': fmtDayMonthYear(_date)})
                    : trp('Kaydet · {d}', {'d': fmtDayMonthYear(_date)}),
                color: AppColors.coral,
                onTap: () => Navigator.pop(context, _MarkResult.date(_date)),
              ),
              const SizedBox(height: 8),
              if (v.done)
                AdSaveButton(
                  label: tr('Yapılmadı olarak geri al'),
                  color: AppColors.coralDark,
                  ghost: true,
                  onTap: () => Navigator.pop(context, const _MarkResult.undo()),
                )
              else
                AdSaveButton(
                  label: tr('Vazgeç'),
                  color: AppColors.muted,
                  ghost: true,
                  onTap: () => Navigator.pop(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? AppColors.coral : Theme.of(context).colorScheme.surface,
      shape: StadiumBorder(
          side: BorderSide(color: on ? AppColors.coral : AppColors.line2, width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 38),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: on ? Colors.white : AppColors.ink2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Boş durum ──

class _Empty extends StatelessWidget {
  final bool canEdit;
  const _Empty({required this.canEdit});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            boxShadow: AppColors.softShadow,
          ),
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.6),
                    radius: 1.2,
                    colors: [AppColors.peachLight, AppColors.peach],
                  ),
                ),
                alignment: Alignment.center,
                child: AdenaIcon('calendar', size: 34, color: _coralT, sw: 2),
              ),
              const SizedBox(height: 16),
              Text(tr('Takvim doğum tarihinden otomatik oluşturulur'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900, height: 1.25)),
              const SizedBox(height: 6),
              Text(
                tr('Doğum tarihini eklediğinde aşıların planlanan tarihleri '
                    "hesaplanır ve aşı günlerinde sabah 09:00'da hatırlatılır."),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink2,
                    height: 1.55),
              ),
              if (canEdit) ...[
                const SizedBox(height: 18),
                AdSaveButton(
                  label: tr('Doğum tarihini ekle'),
                  color: AppColors.coral,
                  onTap: () => context.push('/baby-edit'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
