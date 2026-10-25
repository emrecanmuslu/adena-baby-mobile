import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/glass.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../onboarding/onboarding_kit.dart';
import 'auth_controller.dart';

/// Şifremi unuttum — iki aşamalı tek ekran (tasarım [7b]):
///  1) E-posta gir → sıfırlama kodu iste
///  2) E-postaya gelen 6 haneli kod + yeni şifre → sıfırla (başarılıysa router
///     otomatik giriş yaptırıp ana sayfaya yönlendirir).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _codeLength = 6;
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _codeSent = false; // false = aşama 1, true = aşama 2
  bool _requesting = false; // aşama 1 yerel yükleme durumu

  @override
  void initState() {
    super.initState();
    _code.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_codeSent && !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _requesting = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .requestPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() => _codeSent = true);
      showAdInfo(
        context,
        tr('Kodu gönderdik'),
        tr('E-postanı kontrol et. Kod birkaç dakika içinde gelir; '
            'spam/gereksiz klasörüne de bak.'),
      );
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).resetPassword(
          email: _email.text.trim(),
          code: _code.text.trim(),
          newPassword: _password.text,
        );
    // Başarılı → auth state dolar → router yönlendirir.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading || _requesting;
    final coral = OnbAccent.coral(context);

    // Sıfırlama (aşama 2) hatasını göster.
    ref.listen(authControllerProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        showAdError(context, apiErrorText(next.error));
      }
    });

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 56,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OnbBackButton(
                            onTap: _codeSent
                                ? () => setState(() {
                                      _codeSent = false;
                                      _code.clear();
                                    })
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(tr('Şifremi unuttum'), style: onbTitleStyle),
                      const SizedBox(height: 8),
                      Text(
                          _codeSent
                              ? trp('{email} adresine gelen 6 haneli kodu ve yeni '
                                  'şifreni gir.', {'email': _email.text.trim()})
                              : tr('E-postanı gir, sıfırlama kodu gönderelim'),
                          style: onbSubStyle()),
                      const SizedBox(height: 22),
                      if (!_codeSent) ...[
                        OnbLabel(tr('E-posta')),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.done,
                          textDirection: TextDirection.ltr,
                          onFieldSubmitted: (_) => loading ? null : _requestCode(),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                          decoration: onbInputDecoration(context,
                              hint: 'ornek@eposta.com', accent: coral),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? tr('Geçerli bir e-posta gir')
                              : null,
                        ),
                        const SizedBox(height: 18),
                        OnbPrimaryButton(
                          label: tr('Kod gönder'),
                          accent: coral,
                          loading: loading,
                          onTap: _requestCode,
                        ),
                      ] else ...[
                        OnbLabel(tr('Sıfırlama kodu')),
                        OnbCodeInput(
                          controller: _code,
                          length: _codeLength,
                          accent: coral,
                          digitsOnly: true,
                          autofocus: true,
                        ),
                        const SizedBox(height: 16),
                        OnbLabel(tr('Yeni şifre')),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => loading ? null : _reset(),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                          decoration: onbInputDecoration(
                            context,
                            hint: '••••••',
                            accent: coral,
                            suffix: IconButton(
                              tooltip:
                                  tr(_obscure ? 'Şifreyi göster' : 'Şifreyi gizle'),
                              icon: AdenaIcon('eye',
                                  size: 20, color: AppColors.muted, sw: 2),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 6)
                              ? tr('En az 6 karakter')
                              : null,
                        ),
                        const SizedBox(height: 18),
                        OnbPrimaryButton(
                          label: tr('Şifreyi güncelle'),
                          accent: coral,
                          loading: loading,
                          onTap: _code.text.length == _codeLength ? _reset : null,
                        ),
                        const SizedBox(height: 4),
                        OnbTextButton(
                          label: tr('Kodu tekrar gönder'),
                          onTap: loading ? null : _requestCode,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
