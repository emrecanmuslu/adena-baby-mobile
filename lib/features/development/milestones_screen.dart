import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/baby.dart';
import '../../models/milestone.dart';
import '../babies/baby_controller.dart';

/// Gelişim / Kilometre Taşları ekranı — yaşa gruplu basamaklar, başarıldı
/// işaretleme + ilerleme özeti. Katalog sunucuda (milestone_catalog.py).
class MilestonesScreen extends ConsumerWidget {
  const MilestonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final async = ref.watch(milestonesProvider(baby.id));
    final ageMonths = _babyAgeMonths(baby);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text(tr('Gelişim')),
            const SizedBox(width: 8),
            AdInfoDot(
              title: tr('Gelişim / Kilometre taşları'),
              body: tr('Bebeğinin yaşa göre beklenen gelişim basamakları. '
                  'Başardıkça işaretle — her bebek kendi temposunda gelişir, bu '
                  'bir rehberdir, tıbbi tanı değildir. Endişen varsa doktoruna danış.'),
              size: 16,
            ),
          ],
        ),
      ),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < 6; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Skeleton(height: 64, radius: 16),
              ),
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
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(tr('Gelişim basamakları yükleniyor…'),
                  style: TextStyle(color: AppColors.muted)),
            );
          }
          final achieved = items.where((m) => m.achieved).length;
          // Beklenen aya göre grupla (sunucu zaten sıralı).
          final groups = <int, List<Milestone>>{};
          for (final m in items) {
            (groups[m.expectedMonth] ??= []).add(m);
          }
          final months = groups.keys.toList()..sort();

          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
            children: [
              _ProgressHeader(
                  items: items, achieved: achieved, ageMonths: ageMonths),
              for (final month in months) ...[
                _GroupHeader(month: month, ageMonths: ageMonths),
                for (final m in groups[month]!)
                  _MilestoneTile(
                    milestone: m,
                    onToggle: () => _toggle(context, ref, baby.id, m),
                    onOpen: () => _showSheet(context, ref, baby.id, m),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, String babyId, Milestone m) async {
    // Sağlık/gelişim yalnız owner/parent — bakıcı salt-okunur.
    if (!(ref.read(activeBabyProvider)?.canFullWrite ?? true)) {
      showAdToast(context, tr('Bu işlem için ebeveyn/sahip olmalısın'));
      return;
    }
    try {
      await ref
          .read(healthRepositoryProvider)
          .setMilestoneAchieved(m.id, achieved: !m.achieved);
      ref.invalidate(milestonesProvider(babyId));
      if (context.mounted && !m.achieved) {
        showAdToast(context, tr('Tebrikler! 🎉 Yeni bir kilometre taşı'));
      }
    } catch (e) {
      if (context.mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _showSheet(
      BuildContext context, WidgetRef ref, String babyId, Milestone m) {
    return showModalBottomSheet(
      context: context,
      showDragHandle: false,
      shape: adSheetShape,
      isScrollControlled: true,
      builder: (ctx) => _MilestoneSheet(babyId: babyId, milestone: m),
    );
  }
}

/// Üst ilerleme kartı — başarılan/toplam + çubuk + bebeğin yaşı + kategori dökümü.
class _ProgressHeader extends StatelessWidget {
  final List<Milestone> items;
  final int achieved;
  final int? ageMonths;
  const _ProgressHeader(
      {required this.items, required this.achieved, required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final pct = total > 0 ? achieved / total : 0.0;
    // Kategori bazında başarılan/toplam (renk noktalarını da açıklar).
    const cats = ['motor', 'social', 'language', 'cognitive'];
    final perCat = <String, (int done, int tot)>{};
    for (final c in cats) {
      final inCat = items.where((m) => m.category == c);
      perCat[c] = (inCat.where((m) => m.achieved).length, inCat.length);
    }
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE0D2), Color(0xFFFFD0BE)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(trp('{a} / {t} başarıldı', {'a': achieved, 't': total}),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (ageMonths != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(trp('Şu an: {age}', {'age': milestoneAgeLabel(ageMonths!)}),
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: AppColors.coralDd)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.55),
              valueColor: const AlwaysStoppedAnimation(AppColors.coralDd),
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in cats)
                _CatChip(
                  cat: milestoneCategory(c),
                  done: perCat[c]!.$1,
                  total: perCat[c]!.$2,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// İlerleme kartındaki kategori rozeti — renk noktası + ad + başarılan/toplam.
class _CatChip extends StatelessWidget {
  final MilestoneCategory cat;
  final int done;
  final int total;
  const _CatChip({required this.cat, required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('${cat.label()}  $done/$total',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.coralDd)),
        ],
      ),
    );
  }
}

/// Yaş grubu başlığı (ör. "6. AY") — bebeğin yaşına göre "şimdi"/"ileride".
class _GroupHeader extends StatelessWidget {
  final int month;
  final int? ageMonths;
  const _GroupHeader({required this.month, required this.ageMonths});

  @override
  Widget build(BuildContext context) {
    final age = ageMonths;
    // Bebeğin yaşı bu gruba denk geliyorsa "şimdi", ilerideyse soluk rozet.
    final bool upcoming = age != null && month > age + 1;
    final bool current = age != null && (month - age).abs() <= 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 16, 3, 8),
      child: Row(
        children: [
          Text(milestoneAgeLabel(month).toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: upcoming ? AppColors.muted2 : AppColors.muted,
                  letterSpacing: 0.7)),
          if (current) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.feedBg, borderRadius: BorderRadius.circular(999)),
              child: Text(tr('Şimdi'),
                  style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.coralDd)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tek kilometre taşı satırı — kategori noktası + başlık/açıklama + başarıldı
/// dairesi. Gövdeye dokun → detay (tarih + ipucu); daireye dokun → hızlı işaret.
class _MilestoneTile extends StatelessWidget {
  final Milestone milestone;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  const _MilestoneTile(
      {required this.milestone, required this.onToggle, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final m = milestone;
    final cat = milestoneCategory(m.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Kategori renk noktası
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: cat.bg, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(color: cat.color, shape: BoxShape.circle),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.title,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: m.achieved ? AppColors.muted : null,
                              decoration: m.achieved
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(
                        m.achieved && m.achievedDate != null
                            ? trp('{cat} · {date} başardı', {
                                'cat': cat.label(),
                                'date': fmtDayMonYear(m.achievedDate!),
                              })
                            : (m.description.isNotEmpty ? m.description : cat.label()),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Başarıldı dairesi — gövdeden bağımsız hızlı işaret/geri al.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: m.achieved ? AppColors.growth : Colors.transparent,
                      border: m.achieved
                          ? null
                          : Border.all(color: AppColors.line2, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: m.achieved
                        ? const AdenaIcon('check', size: 15, color: Colors.white, sw: 2.6)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kilometre taşı detay sheet'i — açıklama + "nasıl destekleyebilirsin" ipucu +
/// başarı tarihi seçici (geçmişe tarihleme) + işaretle/güncelle/geri al.
class _MilestoneSheet extends ConsumerStatefulWidget {
  final String babyId;
  final Milestone milestone;
  const _MilestoneSheet({required this.babyId, required this.milestone});

  @override
  ConsumerState<_MilestoneSheet> createState() => _MilestoneSheetState();
}

class _MilestoneSheetState extends ConsumerState<_MilestoneSheet> {
  late DateTime _date;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = widget.milestone.achievedDate ?? DateTime.now();
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

  Future<void> _set(bool achieved) async {
    // Gelişim yalnız owner/parent — bakıcı salt-okunur.
    if (!(ref.read(activeBabyProvider)?.canFullWrite ?? true)) {
      showAdToast(context, tr('Bu işlem için ebeveyn/sahip olmalısın'));
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(healthRepositoryProvider).setMilestoneAchieved(
          widget.milestone.id,
          achieved: achieved,
          date: achieved ? _date : null);
      ref.invalidate(milestonesProvider(widget.babyId));
      if (!mounted) return;
      Navigator.pop(context);
      showAdToast(
          context,
          achieved
              ? tr('Tebrikler! 🎉 Yeni bir kilometre taşı')
              : tr('Geri alındı'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdError(context, apiErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.milestone;
    final cat = milestoneCategory(m.category);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: adGrabHandle()),
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                        color: cat.bg, borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration:
                          BoxDecoration(color: cat.color, shape: BoxShape.circle),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _pill('${cat.label()} · ${milestoneAgeLabel(m.expectedMonth)}',
                                cat.color, cat.bg),
                            _stateBadge(m),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (m.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(m.description,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.45)),
              ],
              if (m.tip.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppColors.feedBg,
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Nasıl destekleyebilirsin?'),
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.coralDd)),
                            const SizedBox(height: 3),
                            Text(m.tip,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              AdField(
                label: tr('Başardığı tarih'),
                info: tr('Bu basamağı ilk yaptığı günü seç. Emin değilsen yaklaşık '
                    'bir tarih girebilirsin; sonradan değiştirebilirsin.'),
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
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        AdenaIcon('chevD', size: 18, color: AppColors.muted2),
                      ],
                    ),
                  ),
                ),
              ),
              if (m.achieved) ...[
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
                    label: _busy ? tr('Kaydediliyor…') : tr('Başardı olarak işaretle'),
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
      ),
    );
  }

  Widget _pill(String text, Color color, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w900, color: color)),
      );

  Widget _stateBadge(Milestone m) {
    final on = m.achieved;
    final text = on && m.achievedDate != null
        ? trp('✓ {d}', {'d': fmtDayMonYear(m.achievedDate!)})
        : tr('Henüz işaretlenmedi');
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
