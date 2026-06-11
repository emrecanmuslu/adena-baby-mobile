import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/ring.dart';
import '../../core/theme.dart';
import '../../data/pregnancy_weeks.dart';
import '../../models/baby.dart';
import '../../models/mom_entry.dart';
import '../babies/baby_actions.dart';
import 'mom_tracking_screen.dart';

/// Bekleme (gebelik) modu ana ekran — design ScrWaiting: meyve boyut sahnesi +
/// doğuma kalan gün halkası + haftalık gelişim notu + "doğdu" CTA.
class ExpectingHome extends ConsumerWidget {
  final Baby baby;
  const ExpectingHome({super.key, required this.baby});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = baby.dueDate;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (due == null) {
      return _NoDue(onEdit: () => context.push('/baby-edit'));
    }

    final daysLeft = due.difference(todayDate).inDays;
    // 40 hafta = 280 gün. Gebelik günü = 280 - kalan.
    final daysPregnant = (280 - daysLeft).clamp(0, 280);
    final weeks = daysPregnant ~/ 7;
    final progress = (daysPregnant / 280).clamp(0.0, 1.0);
    final weeksLeft = (daysLeft / 7).ceil();
    final stage = fruitStageFor(weeks);
    // Hafta görselindeki etiket: tamamlanan + içinde bulunulan hafta (weeks+1).
    final displayWeek = (weeks + 1).clamp(1, 42);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        // Meyve boyut sahnesi
        _FruitStage(weekLabel: '$displayWeek. Hafta', stage: stage),
        const SizedBox(height: 18),

        // Doğuma kalan halka kartı
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(
            children: [
              Ring(
                size: 62,
                pct: progress,
                strokeWidth: 6,
                color: AppColors.coralDd,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(daysLeft > 0 ? '$daysLeft' : '0',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.coralDd,
                            height: 1)),
                    Text(tr('GÜN'),
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted,
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(daysLeft > 0 ? tr('Doğuma kalan') : tr('Bugünlerde!'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      'Tahmini: ${DateFormat('d MMMM y', 'tr_TR').format(due)}'
                      '${daysLeft > 0 ? ' · ~$weeksLeft hafta' : ''}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        _sec(tr('Bu hafta neler oluyor?')),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.peachLight,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            weeklyNote(weeks),
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                height: 1.45),
          ),
        ),

        // Anne takibi (design ScrWaiting) — hızlı ekleme + detay ekranı.
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 22, 3, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('ANNE TAKİBİ'),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.muted,
                        letterSpacing: 0.7)),
              ),
              GestureDetector(
                onTap: () => context.push('/mom'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Tümü'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.coralDark)),
                    const SizedBox(width: 2),
                    const AdenaIcon('chevR', size: 14, color: AppColors.coralDark),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            _MomQuickBtn(
              icon: 'growth',
              color: AppColors.growth,
              bg: AppColors.growthBg,
              label: tr('Kilo'),
              onTap: () => showMomEntrySheet(context, ref, baby.id, MomKind.weight),
            ),
            const SizedBox(width: 10),
            _MomQuickBtn(
              icon: 'doctor',
              color: AppColors.doctor,
              bg: AppColors.doctorBg,
              label: tr('Randevu'),
              onTap: () =>
                  showMomEntrySheet(context, ref, baby.id, MomKind.appointment),
            ),
            const SizedBox(width: 10),
            _MomQuickBtn(
              icon: 'edit',
              color: AppColors.med,
              bg: AppColors.medBg,
              label: tr('Not'),
              onTap: () => showMomEntrySheet(context, ref, baby.id, MomKind.note),
            ),
          ],
        ),

        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => openBornFlow(context),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.coral,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(tr('🎉  Bebeğim Doğdu'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(tr('Tarihi seç, takip moduna otomatik geçilir.'),
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: () => context.push('/baby-edit'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(tr('Bilgileri düzenle')),
          style: TextButton.styleFrom(foregroundColor: AppColors.coralDark),
        ),
      ],
    );
  }
}

/// Meyve/sebze boyut sahnesi (design .ad-fruitstage): hafta rozeti + büyük
/// daire (emoji) + "bir X büyüklüğünde" + ölçü.
class _FruitStage extends StatelessWidget {
  final String weekLabel;
  final FruitStage stage;
  const _FruitStage({required this.weekLabel, required this.stage});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.peach,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(weekLabel,
              style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                  color: AppColors.coralDd)),
        ),
        const SizedBox(height: 14),
        Container(
          width: 148,
          height: 148,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.peachLight, Color(0xFFFFE0D2)],
            ),
          ),
          alignment: Alignment.center,
          child: Text(stage.emoji, style: const TextStyle(fontSize: 70)),
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
            children: [
              TextSpan(text: tr('Bebeğiniz bir ')),
              TextSpan(
                  text: stage.fruit,
                  style: const TextStyle(color: AppColors.coralDd)),
              TextSpan(text: tr(' büyüklüğünde')),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        Text(stage.size,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
      ],
    );
  }
}

/// Tahmini doğum tarihi yoksa: nazik bekleme + düzenle CTA.
class _NoDue extends StatelessWidget {
  final VoidCallback onEdit;
  const _NoDue({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🤰', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(tr('Bebeğinizi bekliyoruz 💛'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              tr('Hafta sayacı ve gelişim takibi için tahmini doğum tarihini ekle.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onEdit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: Text(tr('Tarihi ekle'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anne takibi hızlı ekleme butonu (design .ad-qbtn).
class _MomQuickBtn extends StatelessWidget {
  final String icon;
  final Color color;
  final Color bg;
  final String label;
  final VoidCallback onTap;
  const _MomQuickBtn(
      {required this.icon,
      required this.color,
      required this.bg,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppColors.softShadow,
          ),
          child: Column(
            children: [
              AdIconChip(icon, color: color, bg: bg, size: 48),
              const SizedBox(height: 9),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bölüm başlığı (design .ad-sec).
Widget _sec(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 20, 3, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: AppColors.muted,
          letterSpacing: 0.7,
        ),
      ),
    );
