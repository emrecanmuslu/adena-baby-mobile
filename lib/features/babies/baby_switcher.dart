import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/baby_repository.dart';
import '../auth/auth_controller.dart';
import 'baby_controller.dart';

/// "+" sekmesinden açılan bebek ekleme sheet'i: yeni bebek ekle · davet kodu gir.
/// (Bebek seçimi artık üstteki yatay sekmelerden yapılır, burada listelenmez.)
Future<void> showAddBabySheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
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
                child: Text(tr('Bebek ekle'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              AdMenuItem(
                icon: 'plus',
                color: AppColors.coralDd,
                bg: AppColors.feedBg,
                title: tr('Yeni bebek ekle'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  context.push('/baby-add');
                },
              ),
              // Davet kabulü hesap gerektirir (cloud/paylaşım). Misafir kullanıcıya
              // davet kodu yerine giriş seçeneği göster.
              if (ref.read(authControllerProvider).asData?.value != null)
                AdMenuItem(
                  icon: 'link',
                  color: AppColors.pump,
                  bg: AppColors.pumpBg,
                  title: tr('Davet kodu gir'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    showAcceptInviteDialog(context, ref);
                  },
                )
              else
                AdMenuItem(
                  icon: 'logout',
                  color: AppColors.coral,
                  bg: AppColors.feedBg,
                  title: tr('Giriş yap / Hesap oluştur'),
                  meta: tr('Davet koduyla katılmak için hesap gerekir'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    context.push('/login');
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Başka bir ebeveyn/bakıcının paylaştığı davet kodunu girip katılma.
Future<void> showAcceptInviteDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  return showDialog(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(tr('Davet kodu')),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(hintText: tr('ör. A1B2C3D4')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: Text(tr('Vazgeç')),
        ),
        ElevatedButton(
          onPressed: () async {
            final code = controller.text.trim();
            if (code.isEmpty) return;
            Navigator.pop(dialogCtx);
            try {
              final baby = await ref.read(babyRepositoryProvider).acceptInvitation(code);
              ref.invalidate(babyControllerProvider);
              ref.read(activeBabyIdProvider.notifier).set(baby.id);
              if (context.mounted) {
                showAdToast(context, trp('{name} eklendi', {'name': baby.name}));
              }
            } catch (_) {
              if (context.mounted) {
                showAdError(context, tr('Kod geçersiz veya süresi dolmuş'));
              }
            }
          },
          child: Text(tr('Katıl')),
        ),
      ],
    ),
  );
}
