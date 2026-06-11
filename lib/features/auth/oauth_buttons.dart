import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/social_auth_service.dart';
import 'auth_controller.dart';

/// Login/Register ekranlarında ortak sosyal giriş bölümü:
/// "veya" ayıracı + Google (+ uygunsa Apple) butonları. Hata/iptal akışı
/// AuthController.socialLogin içinde; hatalar ekranların mevcut snackbar
/// dinleyicisiyle gösterilir.
class OAuthSection extends ConsumerWidget {
  const OAuthSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(authControllerProvider).isLoading;
    void go(String provider) {
      if (loading) return;
      ref.read(authControllerProvider.notifier).socialLogin(provider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _OrDivider(),
        _OAuthButton(
          label: tr('Google ile devam et'),
          leading: SvgPicture.string(_kGoogleSvg, width: 19, height: 19),
          onTap: () => go('google'),
        ),
        if (SocialAuthService.appleAvailable) ...[
          const SizedBox(height: 10),
          _OAuthButton(
            label: tr('Apple ile devam et'),
            leading: SvgPicture.string(
              _kAppleSvg,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(AppColors.ink, BlendMode.srcIn),
            ),
            onTap: () => go('apple'),
          ),
        ],
      ],
    );
  }
}

/// "veya" ayıracı (design login).
class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.line, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(tr('veya'),
                style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5)),
          ),
          Expanded(child: Divider(color: AppColors.line, thickness: 1)),
        ],
      ),
    );
  }
}

/// OAuth (Google/Apple) butonu (design .ad-oauth) — logo + etiket.
class _OAuthButton extends StatelessWidget {
  final String label;
  final Widget leading;
  final VoidCallback onTap;
  const _OAuthButton(
      {required this.label, required this.leading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: AppColors.line, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 10),
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          ],
        ),
      ),
    );
  }
}

// Tasarımdaki (design/AdenaBaby/screens-onboard.jsx) inline marka logoları.
const String _kGoogleSvg =
    '<svg width="19" height="19" viewBox="0 0 48 48"><path fill="#4285F4" d="M45 24.5c0-1.6-.1-2.8-.4-4H24v7.3h12c-.2 1.9-1.5 4.8-4.4 6.7l6.7 5.2C42.5 41 45 33.7 45 24.5z"/><path fill="#34A853" d="M24 46c5.9 0 10.9-2 14.5-5.3l-6.7-5.2c-1.8 1.2-4.2 2.1-7.8 2.1-6 0-11-4-12.8-9.5l-7 5.4C7.8 40.5 15.3 46 24 46z"/><path fill="#FBBC05" d="M11.2 28.1c-.5-1.4-.7-2.9-.7-4.1s.3-2.7.7-4.1l-7-5.4C3.5 17.3 3 20.5 3 24s.5 6.7 1.2 9.5l7-5.4z"/><path fill="#EA4335" d="M24 10.4c3.3 0 5.5 1.4 6.8 2.6l5.9-5.8C33 3.7 28.9 2 24 2 15.3 2 7.8 7.5 4.2 14.5l7 5.4C13 14.4 18 10.4 24 10.4z"/></svg>';

const String _kAppleSvg =
    '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M17.05 12.04c-.03-2.6 2.13-3.85 2.22-3.91-1.21-1.77-3.09-2.01-3.76-2.04-1.6-.16-3.12.94-3.93.94-.81 0-2.06-.92-3.39-.89-1.74.03-3.35 1.01-4.25 2.57-1.81 3.15-.46 7.81 1.3 10.37.86 1.25 1.89 2.66 3.24 2.61 1.3-.05 1.79-.84 3.36-.84 1.57 0 2.01.84 3.39.81 1.4-.02 2.28-1.28 3.13-2.54.98-1.45 1.39-2.85 1.41-2.92-.03-.01-2.71-1.04-2.73-4.13zM14.54 4.34c.72-.87 1.2-2.08 1.07-3.28-1.03.04-2.28.69-3.02 1.56-.66.77-1.24 2-1.08 3.18 1.15.09 2.32-.59 3.03-1.46z"/></svg>';
