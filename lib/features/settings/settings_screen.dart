import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
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
    final themeMode = ref.watch(themeControllerProvider).asData?.value ?? ThemeMode.system;
    final role = switch (baby?.myRole) {
      'owner' => tr('Sahip'),
      'parent' => tr('Ebeveyn'),
      'caregiver' => tr('Bakıcı'),
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // Profil başlığı (design ScrMenu)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.peach,
                  child: Text(
                    (user?.displayName.characters.firstOrNull ?? '?').toUpperCase(),
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
                      Text(user?.displayName ?? '—',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      Text(
                          '${user?.email ?? ''}${role != null ? ' · $role' : ''}',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: AppColors.muted),
                  onPressed: () => _editName(context, ref, user?.name ?? ''),
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
            onTap: baby == null ? null : () => context.push('/members'),
          ),
          AdMenuItem(
            icon: 'heart',
            color: AppColors.fever,
            bg: AppColors.feverBg,
            title: tr('Sağlık Hub'),
            meta: tr('Aşı · randevu · ateş & ilaç · hatırlatıcı'),
            onTap: baby == null ? null : () => context.push('/health'),
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
            meta: isPremium ? tr('Aktif · teşekkürler 💛') : tr('AI özet, sınırsız bakıcı ve daha fazlası'),
            onTap: () => context.push('/premium'),
          ),
          AdMenuItem(
            icon: 'ai',
            color: AppColors.med,
            bg: AppColors.medBg,
            title: tr('AI Veri Dışa Aktarımı'),
            meta: isPremium ? tr('Doktora hazır özet') : tr('Premium gerekli'),
            onTap: () => context.push('/ai-export'),
          ),

          adSec(tr('Uygulama')),
          AdMenuItem(
            icon: 'moon',
            color: AppColors.sleep,
            bg: AppColors.sleepBg,
            title: tr('Görünüm'),
            meta: '${ThemeController.label(themeMode)} · birimler',
            onTap: () => context.push('/appearance'),
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
          AdMenuItem(
            icon: 'logout',
            color: AppColors.muted,
            bg: AppColors.line,
            title: tr('Çıkış yap'),
            trailing: const SizedBox.shrink(),
            onTap: () => ref.read(authControllerProvider.notifier).logout(),
          ),

          const SizedBox(height: 8),
          Center(
            child: Text(tr('Adena Baby · sürüm 1.0.0'),
                style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
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
    if (newName == null || newName.isEmpty) return;
    try {
      await ref.read(authControllerProvider.notifier).updateName(newName);
      if (context.mounted) showAdToast(context, tr('Profil güncellendi'));
    } catch (e) {
      if (context.mounted) showAdToast(context, apiErrorText(e));
    }
  }
}
