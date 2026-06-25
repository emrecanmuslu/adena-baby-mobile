import 'package:dio/dio.dart';
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
Future<void> showAcceptInviteDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  // Diyalog YALNIZ kodu toplar. Katıl/dispose/nav'ı buton İÇİNDE yapmak, diyalog
  // KAPANIŞ ANİMASYONU (Material reverse ~200ms) sürerken çalışıp şu 3 çökmeyi
  // (kırmızı flash) tetikliyordu: "TextEditingController used after disposed"
  // (TextField hâlâ controller'a erişiyor), "Duplicate GlobalKeys
  // (_OverlayEntryWidgetState)" + '_dependents.isEmpty' (diyalog overlay'i hâlâ
  // canlıyken onboarding→home route geçişi/teardown çakışması). Çözüm: animasyon
  // TAMAMEN bitene kadar bekle; sonra dispose + katıl + nav (hepsi temiz).
  final code = await showDialog<String>(
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
          onPressed: () {
            final c = controller.text.trim();
            if (c.isEmpty) return;
            Navigator.pop(dialogCtx, c);
          },
          child: Text(tr('Katıl')),
        ),
      ],
    ),
  );
  // Diyalog kapanış animasyonu + route kaldırımı bitsin (controller artık kullanılmıyor,
  // overlay temiz). 350ms > Material reverse süresi.
  await Future.delayed(const Duration(milliseconds: 350));
  controller.dispose();
  if (code == null || code.isEmpty) return;
  // Toast GÖSTERME (kök Overlay'e entry ekleyip nav ile çakışıyordu) — home'a geçince
  // bebeğin görünmesi yeterli geri bildirim. Diyalog tamamen gittiği için setActive +
  // invalidate artık temiz çalışır; invalidate'in tetiklediği nav ayrı/temiz olur.
  try {
    final baby = await ref.read(babyRepositoryProvider).acceptInvitation(code);
    ref.read(activeBabyIdProvider.notifier).set(baby.id);
    ref.invalidate(babyControllerProvider);
  } catch (e) {
    if (context.mounted) {
      // Aile dolu (409 family_full) → net mesaj; diğer hatalarda (geçersiz/süresi
      // dolmuş kod) genel mesaj.
      final isFull = e is DioException && e.response?.statusCode == 409;
      showAdError(
          context,
          isFull
              ? tr('Bu aile dolu — en fazla 5 üye olabilir')
              : tr('Kod geçersiz veya süresi dolmuş'));
    }
  }
}
