import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/subscription_repository.dart';
import '../../data/sync_gate.dart';
import '../babies/baby_controller.dart';

/// Oturum-içi kapatma durumu (kapatınca o oturumda gizlenir, yeniden açılışta
/// tekrar görünür — "sürekli uyarı" ilkesi: kalıcı olarak kapatılamaz).
class _NagDismiss extends Notifier<bool> {
  @override
  bool build() => false;
  void dismiss() => state = true;
}

final _nagDismissedProvider =
    NotifierProvider<_NagDismiss, bool>(_NagDismiss.new);

/// Free kullanıcıya "verin yalnız bu telefonda, Premium ile yedekle" uyarısı.
/// Local-first veri kaybı güvenlik ağı: cloud yedeği olmayan kullanıcıyı premium'a
/// nazikçe iter. Cloud senkron açıkken (premium + oturum) hiç görünmez.
///
/// Aktif bebek PAYLAŞILAN (sahibi premium → veri zaten sahibin bulutunda) ise bu
/// bebek için "yalnız bu telefonda" yanlış olur → gösterilmez. Uyarı yalnız
/// kullanıcının KENDİ (yerel, yedeksiz) bebeğindeyken çıkar.
class BackupNagBanner extends ConsumerWidget {
  const BackupNagBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(cloudSyncEnabledProvider)) return const SizedBox.shrink();
    // Kendi premium'um yok; ama aktif bebek paylaşılansa (sahibi premium) o bebek
    // bulutta yedekli → bu bebekte uyarı gösterme. (Kendi bebeğimde babyCloudSynced
    // false kalır çünkü kendi premium'um yok → uyarı çıkar.)
    final baby = ref.watch(activeBabyProvider);
    if (baby != null && ref.watch(babyCloudSyncedProvider(baby.id))) {
      return const SizedBox.shrink();
    }
    if (ref.watch(_nagDismissedProvider)) return const SizedBox.shrink();
    // Premium süresi dolmuşsa farklı mesaj: veri yerelde güvende + grace.
    final sub = ref.watch(subscriptionProvider).asData?.value;
    final lapsed = sub?.isLapsed ?? false;
    final graceLeft = lapsed ? sub!.graceDaysLeft() : 0;
    final title =
        lapsed ? tr('Premium\'un sona erdi') : tr('Verilerin yalnız bu telefonda');
    final body = lapsed
        ? (graceLeft > 0
            ? trp(
                'Verilerin artık telefonunda — kaybolmaz. {n} gün içinde yeniden '
                'abone olursan eski bulut yedeğinden kaldığın yerden devam edersin.',
                {'n': graceLeft})
            : tr('Verilerin telefonunda güvende. Yeniden abone olup tekrar buluta '
                'yedekleyebilirsin.'))
        : tr('Telefonun kaybolursa veriler de kaybolur. Premium ile buluta '
            'yedekle, her cihazdan eriş.');
    return Padding(
      // Yatay boşluk ebeveynden (liste zaten 16 padding'li); yalnız dikey.
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/premium'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.coral.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(
              children: [
                Icon(
                    lapsed
                        ? Icons.workspace_premium_rounded
                        : Icons.cloud_off_rounded,
                    color: AppColors.coral,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5,
                            color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: AppColors.muted),
                  onPressed: () =>
                      ref.read(_nagDismissedProvider.notifier).dismiss(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paylaşılan bebeğin SAHİBİNİN premium'u bittiğinde (grace), üyenin eklediği kayıtlar
/// yalnız yerelde kalır (buluta gitmez, ailedekilere ulaşmaz). Üye "kaydettim" sanıp
/// veriyi paylaşılmamış bırakmasın diye açık uyarı. Yalnız aktif bebek bu oturumda
/// 403 (bulut salt-okunur) almışsa VE paylaşılan (sahibi başkası) bebekse görünür.
class SharedReadonlyBanner extends ConsumerWidget {
  const SharedReadonlyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) return const SizedBox.shrink();
    final shared = baby.myRole == 'parent' || baby.myRole == 'caregiver';
    final readonly = ref.watch(cloudReadonlyBabiesProvider).contains(baby.id);
    if (!shared || !readonly) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.diaperBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.diaper.withValues(alpha: 0.45), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.diaper, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Değişiklikler paylaşılmıyor'),
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: AppColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('Bu bebeğin sahibinin Premium aboneliği aktif değil — eklediklerin '
                        'yalnız bu telefonda kalıyor, ailedeki diğerleriyle paylaşılmıyor. '
                        'Abonelik tekrar aktif olunca otomatik eşitlenir.'),
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
