import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import 'cycle_kit.dart';

/// F5 — Gebelik kaybı (düşük) şefkatli akışı + doğum sonrası geçiş.
/// Natural Cycles "Recovery Mode" deseni: kayıp loglanınca doğurganlık tahminleri
/// GİZLENİR (predictions_hidden), destekleyici içerik gösterilir, kullanıcı hazır
/// olduğunda takibe döner. Zorlama/metrik baskısı yok.

/// Kaydı yaz + şefkatli moda geç.
Future<void> recordCycleLoss(WidgetRef ref, {DateTime? date}) async {
  final d = date ?? DateTime.now();
  final iso = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  await ref.read(cycleRepositoryProvider).patchSettings({
    'lifecycle_mode': CycleLifecycleMode.loss.name,
    'predictions_hidden': true,
    'last_loss_date': iso,
  });
  ref.invalidate(cycleSettingsProvider);
}

/// Şefkatli moddan çık → adet takibine dön (kullanıcı hazır olunca).
Future<void> returnToTrackingFromLoss(WidgetRef ref) async {
  await ref.read(cycleRepositoryProvider).patchSettings({
    'lifecycle_mode': CycleLifecycleMode.tracking.name,
    'predictions_hidden': false,
  });
  ref.invalidate(cycleSettingsProvider);
}

/// Gebelik durumunu güncelle sayfası: doğum / kayıp / takibe dön.
/// Gebelik modundan çıkışın tek kapısı (Flo pariteti).
Future<void> showCycleLossOrEnd(
  BuildContext context,
  WidgetRef ref,
  CycleSettings settings,
) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: adSheetShape,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          adGrabHandle(),
          const SizedBox(height: 4),
          Text(tr('Durumu güncelle'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          _choice(ctx, Icons.child_care_rounded, AppColors.coralDd,
              tr('Bebeğim doğdu'),
              tr('Doğum sonrası takibe geç'), 'birth'),
          const SizedBox(height: 10),
          _choice(ctx, Icons.favorite_rounded, AppColors.muted,
              tr('Gebeliğim sonlandı'),
              tr('Kayıp — sana destek olalım'), 'loss'),
          const SizedBox(height: 10),
          _choice(ctx, Icons.calendar_month_rounded, AppColors.rose,
              tr('Adet takibine dön'),
              tr('Yeniden döngü takibi'), 'tracking'),
        ]),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  try {
    if (choice == 'loss') {
      await _confirmLoss(context, ref);
    } else if (choice == 'birth') {
      await ref.read(cycleRepositoryProvider).patchSettings({
        'lifecycle_mode': CycleLifecycleMode.postpartum.name,
        'predictions_hidden': true,
      });
      ref.invalidate(cycleSettingsProvider);
      if (context.mounted) {
        showAdToast(context, tr('Doğum sonrası moduna geçildi'));
      }
    } else if (choice == 'tracking') {
      await returnToTrackingFromLoss(ref);
      if (context.mounted) showAdToast(context, tr('Adet takibine dönüldü'));
    }
  } catch (e) {
    if (context.mounted) showAdError(context, apiErrorText(e));
  }
}

/// Kayıp onay ekranı — içerik uyarısı + şefkatli dil (Flo/NC deseni).
Future<void> _confirmLoss(BuildContext context, WidgetRef ref) async {
  final ok = await showModalBottomSheet<bool>(
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
          Icon(Icons.favorite_rounded, size: 38, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(tr('Çok üzgünüz'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text(
              tr('Kaybını kaydedersek doğurganlık tahminlerini bir süre gizler, '
                  'sana zaman tanırız. Hazır olduğunda takibe dönebilirsin. '
                  'Yalnız değilsin.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
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
                      color: AppColors.roseD,
                      borderRadius: BorderRadius.circular(14)),
                  child: Text(tr('Kaydet'),
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
  if (ok != true) return;
  await recordCycleLoss(ref);
  if (context.mounted) showAdToast(context, tr('Kaydedildi. Kendine iyi bak 💗'));
}

/// Şefkatli mod ana ekran içeriği (Today `_loss` builder'ının gövdesi).
List<Widget> cycleLossToday(
  BuildContext context,
  WidgetRef ref,
  CycleSettings settings, {
  DateTime? lastLoss,
}) {
  return [
    const SizedBox(height: 8),
    Center(
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
            color: AppColors.roseBg, shape: BoxShape.circle),
        child: Icon(Icons.favorite_rounded, size: 40, color: AppColors.roseD),
      ),
    ),
    const SizedBox(height: 16),
    Center(
      child: Text(tr('Kendine zaman tanı'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
    ),
    const SizedBox(height: 8),
    Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
            tr('Doğurganlık tahminlerini şimdilik gizledik. Hazır olduğunda '
                'takibe dönebilirsin — acele yok.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.muted)),
      ),
    ),
    const SizedBox(height: 22),
    CycEyebrow(tr('Bilmen iyi olur')),
    cycNote(context,
        icon: Icons.schedule_rounded,
        body: tr('Kayıptan sonra ovülasyon genelde ~2 hafta içinde dönebilir; '
            'ilk adet çoğunlukla 4–6 hafta sonra gelir.')),
    const SizedBox(height: 10),
    cycNote(context,
        icon: Icons.science_outlined,
        body: tr('Gebelik hormonu (hCG) düşene kadar ovülasyon testleri yanlış '
            'pozitif verebilir — ilk ~2 hafta bunlara güvenme.')),
    const SizedBox(height: 10),
    cycNote(context,
        icon: Icons.favorite_border_rounded,
        body: tr('İlk adetin gelmeden de gebe kalabilirsin. Fiziksel/duygusal '
            'iyileşme için sağlık uzmanına danışabilirsin.')),
    const SizedBox(height: 22),
    cycCta(context, tr('Takibe hazırım — döngüme dön'), onTap: () async {
      await returnToTrackingFromLoss(ref);
      if (context.mounted) showAdToast(context, tr('Tekrar hoş geldin 💗'));
    }),
    const SizedBox(height: 8),
  ];
}

Widget _choice(BuildContext ctx, IconData icon, Color color, String title,
        String sub, String value) =>
    GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line, width: 1.4),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style:
                      const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
              Text(sub,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted2),
        ]),
      ),
    );
