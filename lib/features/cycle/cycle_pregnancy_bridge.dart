import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/cycle.dart';
import 'cycle_lifecycle.dart';

/// Gebelik köprüsü (F4) — TTC/adet → gebelik geçişi.
/// KARAR: cycle yalnız tetikler/bayrak tutar; gebelik verisinin kaynağı ana
/// gebelik modülüdür. Burada LMP'den (son adet) gebelik haftası + tahmini doğum
/// (Naegele: LMP+280g) TÜRETİLİR ve onaylı olarak `lifecycle_mode=pregnant`
/// yazılır. Ana gebelik modülü (Baby.status=expecting) kullanıcı hazır olunca
/// devralır — cycle pregnant modu bu türetilmiş bilgiyi salt-okunur gösterir.

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
    await setCycleLifecycleMode(ref, CycleLifecycleMode.pregnant);
    if (context.mounted) showAdToast(context, tr('Gebelik moduna geçildi'));
  } catch (e) {
    if (context.mounted) showAdError(context, apiErrorText(e));
  }
}
