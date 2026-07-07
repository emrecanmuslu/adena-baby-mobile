import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/baby.dart';
import '../../models/cycle.dart';
import '../babies/baby_controller.dart';
import 'cycle_lifecycle.dart';

/// Gebelik köprüsü — TTC/adet → gebelik geçişi.
/// KARAR (güncellendi 2026-07-03): gebeliğin TEK gerçek kaynağı ana gebelik
/// modülüdür (`Baby.status=expecting`). "Hamileyim" seçilince cycle artık salt
/// bayrak yazmaz; LMP'den GERÇEK bir bekleme-modu bebeği oluşturur/bağlar
/// ([[ensureExpectingBabyForPregnancy]]) ve kullanıcıyı ana gebelik ekranına
/// (ExpectingHome) götürür. cycle `lifecycle_mode=pregnant` yalnız bu duruma
/// eşlik eden bir yansımadır; hafta/TDT tek kaynaktan (Baby.dueDate) okunur.

/// LMP'den türetilmiş gebelik bilgisi.
class PregnancyFromLmp {
  final int weeks;
  final int days;
  final DateTime dueDate;
  const PregnancyFromLmp(this.weeks, this.days, this.dueDate);
}

PregnancyFromLmp? pregnancyFromLmp(DateTime? lmp, {DateTime? today}) {
  if (lmp == null) return null;
  final t = today ?? DateTime.now();
  final l = DateTime(lmp.year, lmp.month, lmp.day);
  final n = DateTime(t.year, t.month, t.day);
  final totalDays = n.difference(l).inDays;
  if (totalDays < 0 || totalDays > 300) return null; // makul aralık dışı
  return PregnancyFromLmp(
      totalDays ~/ 7, totalDays % 7, l.add(const Duration(days: 280)));
}

/// Gebeliğin GERÇEK kaynağını sağlar: bekleyen (expecting) bir Baby.
/// - Zaten bekleyen bir bebek varsa onu kullanır.
/// - Yoksa ve LMP biliniyorsa GERÇEK bir `Baby(status=expecting, dueDate=LMP+280,
///   lastMenstrualDate=LMP)` oluşturur (bebeksiz cycle-first kullanıcı dahil).
/// - LMP yoksa ve bebek de yoksa `null` döner (çağıran elle giriş ekranına yollar).
/// Ardından cycle'ı bu gebeliğe bağlar (`baby` + `lifecycle_mode=pregnant`).
Future<Baby?> ensureExpectingBabyForPregnancy(
    WidgetRef ref, CycleSettings settings) async {
  final babies = ref.read(babyControllerProvider).asData?.value ?? const [];
  Baby? baby =
      babies.where((b) => b.status == BabyStatus.expecting).firstOrNull;
  if (baby == null) {
    final info = pregnancyFromLmp(settings.firstPeriodDate);
    if (info == null) return null; // LMP yok → gebelik verisi türetilemez
    baby = await ref.read(babyControllerProvider.notifier).create(
          name: tr('Bebeğim'),
          status: BabyStatus.expecting,
          dueDate: info.dueDate,
          lastMenstrualDate: settings.firstPeriodDate,
        );
  }
  ref.read(activeBabyIdProvider.notifier).set(baby.id);
  // cycle'ı bu gebeliğe bağla (yansıma bayrağı + geri-dönüş için LMP zaten var).
  await ref.read(cycleRepositoryProvider).patchSettings({
    'lifecycle_mode': CycleLifecycleMode.pregnant.name,
    'predictions_hidden': false,
    'baby': baby.id,
  });
  ref.invalidate(cycleSettingsProvider);
  return baby;
}

/// cycle "pregnant" ekranından ana gebelik ekranına götürür (T2 fix).
/// Gerçek bekleme-modu bebeği yoksa oluşturur; LMP yoksa elle giriş ekranına.
Future<void> openPregnancyScreen(
    BuildContext context, WidgetRef ref, CycleSettings settings) async {
  try {
    final baby = await ensureExpectingBabyForPregnancy(ref, settings);
    if (!context.mounted) return;
    context.go(baby != null ? '/home' : '/baby-add');
  } catch (e) {
    if (context.mounted) showAdError(context, apiErrorText(e));
  }
}

/// "Hamileyim" seçilince çağrılır. LMP varsa türetilmiş bilgiyle onay ister,
/// yoksa yine de gebelik moduna geçmeyi teklif eder.
Future<void> startCyclePregnancy(
  BuildContext context,
  WidgetRef ref,
  CycleSettings settings,
) async {
  final info = pregnancyFromLmp(settings.firstPeriodDate);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: adSheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          adGrabHandle(),
          const SizedBox(height: 6),
          Icon(Icons.pregnant_woman_rounded, size: 40, color: AppColors.coralDd),
          const SizedBox(height: 10),
          Text(tr('Gebelik takibine geç'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (info != null) ...[
            Text(
                trp('Son adet verine göre yaklaşık {w} hafta {d} günlük gebe '
                    'görünüyorsun.', {'w': info.weeks, 'd': info.days}),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink2)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.roseBg,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.event_rounded, size: 16, color: AppColors.roseD),
                const SizedBox(width: 8),
                Text(
                    trp('Tahmini doğum: {d}',
                        {'d': fmtDayMonthYear(info.dueDate)}),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.roseD)),
              ]),
            ),
            const SizedBox(height: 6),
            Text(tr('Bu tarih son adetinden hesaplanır; ultrason sonucuna göre '
                'ana gebelik ekranından düzeltebilirsin.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted)),
          ] else
            Text(tr('Gebeliğini hafta hafta takip etmek için gebelik moduna '
                'geçelim. Ayrıntıları ana gebelik ekranından girebilirsin.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink2)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, false),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(14)),
                  child: Text(tr('Vazgeç'),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.muted)),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.coralDd,
                      borderRadius: BorderRadius.circular(14)),
                  child: Text(tr('Gebelik moduna geç'),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
  if (confirmed != true) return;
  try {
    // Gerçek bekleme-modu bebeği oluştur/bağla → ana gebelik ekranı devreye girer.
    final baby = await ensureExpectingBabyForPregnancy(ref, settings);
    if (!context.mounted) return;
    if (baby != null) {
      showAdToast(context, tr('Gebelik takibine geçildi'));
      context.go('/home');
    } else {
      // LMP yok → gebelik ayrıntılarını elle gir (bekleme modunda bebek ekle).
      await setCycleLifecycleMode(ref, CycleLifecycleMode.pregnant);
      if (!context.mounted) return;
      showAdToast(context, tr('Gebelik ayrıntılarını girelim'));
      context.go('/baby-add');
    }
  } catch (e) {
    if (context.mounted) showAdError(context, apiErrorText(e));
  }
}
