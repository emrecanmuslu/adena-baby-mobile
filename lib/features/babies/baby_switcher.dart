import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../auth/auth_controller.dart';
import '../onboarding/invite_code_sheet.dart';
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
                    context.push('/login?ctx=invite');
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
Future<void> showAcceptInviteDialog(BuildContext context, WidgetRef ref) async {
  // Sayfa kodu toplar VE katılımı dener (hata sayfa içinde); başarıda bebeği
  // döndürür. Aktif bebek + invalidate sayfa kapanış animasyonu bittikten SONRA:
  // erken invalidate, kapanan sayfanın overlay'i hâlâ canlıyken onboarding→home
  // geçişiyle çakışıp "Duplicate GlobalKeys"/'_dependents.isEmpty' hatası veriyordu.
  final joined = await showInviteCodeSheet(context);
  if (joined == null) return;
  await Future.delayed(const Duration(milliseconds: 350));
  ref.read(activeBabyIdProvider.notifier).set(joined.id);
  ref.invalidate(babyControllerProvider);
}
