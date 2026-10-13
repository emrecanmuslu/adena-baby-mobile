import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widget_pin_service.dart';
import '../../models/baby.dart';
import '../babies/baby_controller.dart';

/// Ayarlar → Uygulama: "Ana ekrana widget ekle" satırı. Yalnız Android'de ve
/// launcher sabitlemeyi destekliyorken görünür; aksi halde hiç yer kaplamaz.
class WidgetPinMenuItem extends ConsumerWidget {
  const WidgetPinMenuItem({super.key});

  /// Kullanıcı sistem penceresinde onaylayana dek "eklendi" olayını bekleme süresi.
  static const pinnedWait = Duration(minutes: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(widgetPinSupportedProvider).asData?.value ?? false;
    if (!supported) return const SizedBox.shrink();
    // Dokunma anında bebek listesi hazır olsun (K1 seçimi bu listeden).
    ref.watch(babyControllerProvider);
    return AdMenuItem(
      icon: 'home',
      color: AppColors.coral,
      bg: AppColors.feedBg,
      title: tr('Ana ekrana widget ekle'),
      meta: tr('Sonraki beslenme saatini ana ekranda gör'),
      onTap: () => _pin(context, ref),
    );
  }

  Future<void> _pin(BuildContext context, WidgetRef ref) async {
    final service = ref.read(widgetPinServiceProvider);
    // K1: birden çok doğmuş bebekte eklemeden ÖNCE "Hangi bebek için?"; tekte
    // soru yok. Widget yalnız doğmuş bebeği gösterebilir (gebelik listede yok).
    final born = [
      for (final b in ref.read(babyControllerProvider).asData?.value ?? const <Baby>[])
        if (!b.isExpecting) b
    ];
    String? babyId;
    if (born.length > 1) {
      babyId = await _chooseBaby(context, born);
      if (babyId == null) return; // vazgeçti
    } else if (born.length == 1) {
      babyId = born.first.id;
    }
    final requested = await service.requestPin(babyId: babyId);
    if (!requested) {
      if (context.mounted) {
        showAdToast(context, tr('Widget eklenemedi'), type: AdToastType.error);
      }
      return;
    }
    // Geri çağrı ancak kullanıcı sistem penceresini onaylayınca gelir → istek
    // döndükten sonra dinlemek olay kaçırmaz.
    try {
      await service.pinned.first.timeout(pinnedWait);
      if (context.mounted) showAdToast(context, tr('Widget ana ekrana eklendi'));
    } catch (_) {
      // Kullanıcı vazgeçti ya da launcher geri çağrı göndermedi → sessiz.
    }
  }

  /// Widget'ın göstereceği bebeği seçtirir; kapatılırsa null.
  Future<String?> _chooseBaby(BuildContext context, List<Baby> babies) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      shape: adSheetShape,
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: adGrabHandle()),
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 12),
                  child: Text(tr('Hangi bebek için?'),
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                ),
                for (final b in babies)
                  AdMenuItem(
                    icon: 'baby',
                    color: AppColors.coral,
                    bg: AppColors.feedBg,
                    title: b.name,
                    onTap: () => Navigator.pop(sheetCtx, b.id),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
