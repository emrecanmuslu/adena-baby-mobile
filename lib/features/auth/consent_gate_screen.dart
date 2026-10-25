import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../onboarding/consent_sheet.dart';
import '../onboarding/onboarding_kit.dart';
import 'auth_controller.dart';

/// Yasal rıza kapısı — sunucu "rıza gerekli" dediğinde (sosyal giriş, yeni
/// politika sürümü) uygulamaya girmeden önce gösterilir. Onboarding'deki
/// "Başlamadan önce" alt sayfasıyla AYNI içerik ([ConsentForm]); kabul
/// edilince backend'e yazılır ve router devam ettirir.
class ConsentGateScreen extends ConsumerWidget {
  const ConsentGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider).asData?.value != null;
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConsentForm(accent: OnbAccent.coral(context)),
                    // Çıkış yalnız oturum açıkken anlamlı.
                    if (signedIn) ...[
                      const SizedBox(height: 6),
                      OnbTextButton(
                        label: tr('Çıkış yap'),
                        color: AppColors.muted,
                        onTap: () =>
                            ref.read(authControllerProvider.notifier).logout(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
