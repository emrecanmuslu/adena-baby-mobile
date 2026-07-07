import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../data/local_session.dart';
import '../../models/baby.dart';
import '../../models/cycle.dart';
import '../babies/baby_controller.dart';
import 'cycle_kit.dart';
import 'cycle_pregnancy_bridge.dart';

/// F5 — Gebelik kaybı (düşük) şefkatli akışı + doğum sonrası geçiş.
/// Natural Cycles "Recovery Mode" deseni: kayıp loglanınca doğurganlık tahminleri
/// GİZLENİR (predictions_hidden), destekleyici içerik gösterilir, kullanıcı hazır
/// olduğunda takibe döner. Zorlama/metrik baskısı yok.

/// Kaydı yaz + şefkatli moda geç.
/// Döngü çapası (first_period_date) SIFIRLANIR: gebelikteki LMP artık geçersiz —
/// bırakılsaydı "takibe dön" sonrası motor eski LMP'den sayıp "56 gün gecikti"
/// gibi çöp tahmin üretirdi. İlk gerçek adet = yeni Gün 1 (bekleme modundan).
Future<void> recordCycleLoss(WidgetRef ref, {DateTime? date}) async {
  final d = date ?? DateTime.now();
  final iso = '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  await ref.read(cycleRepositoryProvider).patchSettings({
    'lifecycle_mode': CycleLifecycleMode.loss.name,
    'predictions_hidden': true,
    'last_loss_date': iso,
    'first_period_date': null,
    // Gebelik bebeği kayıp akışında silinir → ayarlardaki bağ da kopmalı
    // (bayat id, sonraki köprü çağrılarında yanlış bebeğe işaret ederdi).
    'baby': null,
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
      await _confirmLoss(context, ref, settings);
    } else if (choice == 'birth') {
      // GERÇEK doğum akışı: bekleyen bebeği doğum ekranına (born_flow) götür →
      // Baby.status=born + gerçek doğum tarihi/prematüre; born_flow ayrıca cycle'ı
      // doğum sonrasına (loşia) senkronlar. Yalnız cycle bayrağı yazmak YETMEZ.
      final baby = await ensureExpectingBabyForPregnancy(ref, settings);
      if (!context.mounted) return;
      context.go(baby != null ? '/born-flow' : '/baby-add');
    } else if (choice == 'tracking') {
      await returnToTrackingFromLoss(ref);
      if (context.mounted) showAdToast(context, tr('Adet takibine dönüldü'));
    }
  } catch (e) {
    if (context.mounted) showAdError(context, apiErrorText(e));
  }
}

/// Gebelik kaybında bekleyen (expecting) bebek profilini sessizce kaldırır (T4).
/// Baby'de "kayıp" durumu yok → kalıntı "expecting" bebek bırakmamak için silinir.
/// Silme sonrası hiç bebek kalmazsa, router onboarding'e atmasın diye cycle-first
/// bayrağı açılır (kullanıcı iyileşme moduyla Adet Takvimi'nde kalır).
Future<void> _removeExpectingBabyForLoss(
    WidgetRef ref, CycleSettings settings) async {
  final babies = ref.read(babyControllerProvider).asData?.value ?? const [];
  final expecting = <Baby>[
    // Önce cycle'a bağlı bebek, sonra herhangi bir bekleyen bebek.
    ...babies.where((b) => b.id == settings.babyId && b.status == BabyStatus.expecting),
    ...babies.where((b) => b.status == BabyStatus.expecting && b.id != settings.babyId),
  ];
  if (expecting.isEmpty) return;
  await ref.read(babyControllerProvider.notifier).deleteBaby(expecting.first.id);
  final remaining = ref.read(babyControllerProvider).asData?.value ?? const [];
  if (remaining.where((b) => b.id != expecting.first.id).isEmpty) {
    await ref.read(cycleFirstProvider.notifier).set(true);
  }
}

/// Kayıp onay ekranı — içerik uyarısı + şefkatli dil (Flo/NC deseni).
Future<void> _confirmLoss(
    BuildContext context, WidgetRef ref, CycleSettings settings) async {
  var lossDate = DateTime.now();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: adSheetShape,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
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
          const SizedBox(height: 14),
          // İsteğe bağlı tarih: varsayılan bugün; geçmişte olduysa düzeltilebilir.
          GestureDetector(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: ctx,
                initialDate: lossDate,
                firstDate: now.subtract(const Duration(days: 300)),
                lastDate: now,
                helpText: tr('Ne zaman oldu?'),
              );
              if (picked != null) setSheet(() => lossDate = picked);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line, width: 1.4),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_rounded,
                    size: 17, color: AppColors.muted),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                      '${tr('Ne zaman oldu?')} · ${fmtDayMonthYear(lossDate)}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink2)),
                ),
                Icon(Icons.edit_outlined, size: 16, color: AppColors.muted2),
              ]),
            ),
          ),
          const SizedBox(height: 14),
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
    ),
  );
  if (ok != true) return;
  // Bekleyen bebek profilini sessizce kaldır (kalıntı gebelik kalmasın), sonra
  // cycle'ı şefkatli iyileşme moduna al.
  await _removeExpectingBabyForLoss(ref, settings);
  await recordCycleLoss(ref, date: lossDate);
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
