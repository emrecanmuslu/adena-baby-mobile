import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/app_version_footer.dart';
import '../../core/i18n.dart';
import '../../core/premium_gate.dart';
import '../../core/theme.dart';
import '../../core/tour.dart';
import '../../data/subscription_repository.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_controller.dart';
import 'theme_controller.dart';

/// Ayarlar: profil, paylaşım, hesap işlemleri.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final baby = ref.watch(activeBabyProvider);

    final isPremium =
        ref.watch(subscriptionProvider).asData?.value.isPremium ?? false;
    // Rozetleri yalnız "kesin free" iken göster — açılışta yüklenirken flaş olmasın.
    final showProBadge = ref.watch(isDefinitelyFreeProvider);
    // Bekleme (gebelik) modu: bebek doğmadan anlamsız olan menüler gizlenir
    // (Sağlık Hub = aşı/ateş/ilaç/hatırlatıcı, AI dışa aktarım = kayıt özeti).
    final expecting = baby?.isExpecting ?? false;
    final themeMode = ref.watch(themeControllerProvider).asData?.value ?? ThemeMode.system;
    final role = switch (baby?.myRole) {
      'owner' => tr('Sahip'),
      'parent' => tr('Ebeveyn'),
      'caregiver' => tr('Bakıcı'),
      _ => null,
    };
    // Hesap zorunlu → profil her zaman hesaptan gelir.
    final profileName = user?.displayName ?? '—';
    final avatarInitial =
        (profileName.characters.firstOrNull ?? '?').toUpperCaseTr();
    final profileSubtitle = user != null
        ? '${user.email}${role != null ? ' · $role' : ''}'
        : '';

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // Profil başlığı (design ScrMenu). Hesaplıda: ad/e-posta + düzenle kalemi.
          // MİSAFİRDE: düzenlenecek sunucu profili yok → yerine "hesap oluştur" CTA
          // (verini yedekle & paylaş dürtüsü; dokununca /login).
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            child: user == null
                ? Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                    decoration: BoxDecoration(
                      color: AppColors.feedBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.coral.withValues(alpha: 0.25),
                          width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.coral.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: const Text('🍼',
                                  style: TextStyle(fontSize: 22)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(tr('Verilerini kaybetme'),
                                  style: const TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w900)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr('Hesap oluştur; verilerini yedekle, ailenle paylaş '
                              've her cihazdan eriş.'),
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.coral,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => context.push('/register'),
                            child: Text(tr('Kayıt ol'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 15)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: GestureDetector(
                            onTap: () => context.push('/login'),
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w700),
                                children: [
                                  TextSpan(text: tr('Zaten hesabın var mı? ')),
                                  TextSpan(
                                      text: tr('Giriş yap'),
                                      style: const TextStyle(
                                          color: AppColors.coralDark,
                                          fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.peach,
                        child: Text(
                          avatarInitial,
                          style: const TextStyle(
                              color: AppColors.coralDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profileName.isNotEmpty ? profileName : '—',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900)),
                            Text(profileSubtitle,
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Adı düzenle'),
                        icon: Icon(Icons.edit_outlined, color: AppColors.muted),
                        onPressed: () => _editName(context, ref, profileName),
                      ),
                    ],
                  ),
          ),

          adSec(tr('Ayarlar & Profil')),
          AdMenuItem(
            icon: 'family',
            color: AppColors.doctor,
            bg: AppColors.doctorBg,
            title: tr('Aile / Paylaşım'),
            meta: baby?.name,
            // Aile paylaşımı premium — değilse altın "Premium" rozeti.
            trailing: showProBadge ? const AdProBadge(withChevron: true) : null,
            // Paylaşım cloud + hesap + premium gerektirir: bebek ancak premium'da
            // buluta gider; free'de yerelde kalır → /members 403 verirdi. Önce
            // hesap, sonra premium kapısı. İstisna: bebek bana ait değilse
            // (paylaşımlı; myRole parent/caregiver) sahibi yüklemiştir, ben üyeyim
            // → bebek sunucuda, premium aramadan aç.
            onTap: baby == null
                ? null
                : () => requireAccount(context, ref,
                    feature: tr('Aile / Paylaşım'),
                    desc: tr('Bebeğini eşin veya bakıcınla paylaşmak için ücretsiz '
                        'bir hesap oluştur.'),
                    onAllowed: () {
                      final shared = baby.myRole == 'parent' ||
                          baby.myRole == 'caregiver';
                      if (shared) {
                        context.push('/members');
                        return;
                      }
                      requirePremium(context, ref,
                          feature: tr('Aile / Paylaşım'),
                          desc: tr('Bebeğini eşin veya bakıcınla paylaş; '
                              'etkinlikleri birlikte takip edin.'),
                          onAllowed: () => context.push('/members'));
                    }),
          ),
          // Keşfet (Bebeğin Sağlığı · Topluluk · Uzman Rehberi · Anılar) takip
          // modunda alt menüdeki ✨ slotundan açılır; bekleme modunda alt menü
          // olmadığından erişim buradan verilir (tekrar olmasın diye yalnız o zaman).
          if (expecting)
            AdMenuItem(
              icon: 'compass',
              color: AppColors.pump,
              bg: AppColors.pumpBg,
              title: tr('Keşfet'),
              meta: tr('Topluluk · Uzman Rehberi · Anılar'),
              onTap: baby == null ? null : () => context.push('/discover'),
            ),
          AdMenuItem(
            icon: 'edit',
            color: AppColors.growth,
            bg: AppColors.growthBg,
            title: tr('Bebek bilgileri'),
            meta: baby?.name,
            onTap: baby == null ? null : () => context.push('/baby-edit'),
          ),

          adSec(tr('Premium')),
          AdMenuItem(
            icon: 'star',
            color: AppColors.premiumInk,
            bg: AppColors.premiumBg,
            title: tr('Adena Premium'),
            meta: isPremium
                ? tr('Aktif · teşekkürler 💛')
                : tr('Reklamsız · aile paylaşımı · bulut yedek'),
            onTap: () => context.push('/premium'),
          ),

          adSec(tr('Uygulama')),
          AdMenuItem(
            icon: 'moon',
            color: AppColors.sleep,
            bg: AppColors.sleepBg,
            title: tr('Görünüm'),
            meta: trp('{theme} · birimler', {'theme': ThemeController.label(themeMode)}),
            onTap: () => context.push('/appearance'),
          ),
          AdMenuItem(
            icon: 'compass',
            color: AppColors.coral,
            bg: AppColors.feedBg,
            title: tr('Tanıtım turları'),
            meta: tr('Ekran tanıtımlarını yeniden göster'),
            onTap: () async {
              await ref.read(tourControllerProvider.notifier).resetAll();
              if (context.mounted) {
                showAdToast(context, tr('Tanıtım turları sıfırlandı'));
              }
            },
          ),

          AdMenuItem(
            icon: 'comment',
            color: AppColors.growth,
            bg: AppColors.growthBg,
            title: tr('Geri Bildirim'),
            meta: tr('Özellik iste · sorun bildir'),
            onTap: () => context.push('/feedback'),
          ),

          adSec(tr('Hesap')),
          AdMenuItem(
            icon: 'shield',
            color: AppColors.pump,
            bg: AppColors.pumpBg,
            title: tr('Veri & Gizlilik'),
            meta: tr('Verini indir · yedekleme · hesabı sil'),
            onTap: () => context.push('/privacy'),
          ),
          // "Çıkış yap" yalnız GERÇEK oturumda gösterilir. Misafirin çıkacağı bir
          // oturum yok (hesaba geçiş üstteki "Hesap oluştur" CTA'sında); ayrıca guest
          // logout activeAccount'ı bozup bebeği restart'a kadar kaybediyordu → gizle.
          if (user != null)
            AdMenuItem(
              icon: 'logout',
              color: AppColors.muted,
              bg: AppColors.line,
              title: tr('Çıkış yap'),
              trailing: const SizedBox.shrink(),
              // Tek dokunuşla anında çıkış yanlışlıkla oluyordu (BULGU-10) → önce onay.
              // Çıkış birkaç ağ çağrısı yapar (FCM kaydı sil + sunucu); loader olmadan
              // basılmamış gibi hissettiriyordu → engelleyici göstergeyle geri bildirim ver.
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: Text(tr('Çıkış yap')),
                    content: Text(tr('Çıkış yapılsın mı? Verilerin bu cihazda '
                        'kalır; tekrar giriş yapınca kaldığın yerden devam edersin.')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: Text(tr('Vazgeç')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: Text(tr('Çıkış yap'),
                            style: const TextStyle(
                                color: AppColors.fever,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(child: CircularProgressIndicator()),
                );
                try {
                  await ref.read(authControllerProvider.notifier).logout();
                } finally {
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                }
              },
            ),

          // Yalnız debug build'lerde: Geliştirici sayfası (API ortamı vb.).
          if (kDebugMode)
            AdMenuItem(
              icon: 'gear',
              color: AppColors.sleep,
              bg: AppColors.sleepBg,
              title: 'Geliştirici',
              meta: 'API ortamı · debug',
              onTap: () => context.push('/dev'),
            ),
          const SizedBox(height: 8),
          const Center(child: AppVersionFooter()),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final controller = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(tr('Adını düzenle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Ad')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text(tr('Vazgeç'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
            child: Text(tr('Kaydet')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty) return;
    try {
      await ref.read(authControllerProvider.notifier).updateName(newName);
      if (context.mounted) showAdToast(context, tr('Profil güncellendi'));
    } catch (e) {
      if (context.mounted) showAdError(context, apiErrorText(e));
    }
  }
}
