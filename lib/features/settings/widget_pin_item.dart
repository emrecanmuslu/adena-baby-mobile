import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widget_pin_service.dart';

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
    return AdMenuItem(
      icon: 'home',
      color: AppColors.coral,
      bg: AppColors.feedBg,
      title: tr('Ana ekrana widget ekle'),
      meta: tr('Sonraki beslenme saatini ana ekranda gör'),
      onTap: () => _pin(context, ref.read(widgetPinServiceProvider)),
    );
  }

  Future<void> _pin(BuildContext context, WidgetPinService service) async {
    final requested = await service.requestPin();
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
}
