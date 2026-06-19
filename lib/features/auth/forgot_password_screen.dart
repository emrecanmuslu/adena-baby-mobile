import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';

/// Şifremi unuttum — iki aşamalı tek ekran:
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
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _codeSent = false; // false = aşama 1, true = aşama 2
  bool _requesting = false; // aşama 1 yerel yükleme durumu

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!_formKey.currentState!.validate()) return;
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
    // Başarılı → auth state dolar → router /home'a yönlendirir.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading || _requesting;

    // Sıfırlama (aşama 2) hatasını snackbar ile göster.
    ref.listen(authControllerProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        showAdError(context, apiErrorText(next.error));
      }
    });

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandWordmark()),
                    const SizedBox(height: 9),
                    Center(
                      child: Text(
                        _codeSent
                            ? tr('Yeni şifreni belirle')
                            : tr('Şifreni mi unuttun?'),
                        style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _codeSent
                            ? tr('E-postana gelen 6 haneli kodu ve yeni şifreni gir.')
                            : tr('Kayıtlı e-postanı gir, sana bir sıfırlama kodu gönderelim.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 26),
                    AdField(
                      label: tr('E-posta'),
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        // Aşama 2'de e-posta kilitli (kod o adrese gönderildi).
                        readOnly: _codeSent,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        decoration: _dec('ornek@eposta.com'),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? tr('Geçerli bir e-posta gir')
                            : null,
                      ),
                    ),
                    if (_codeSent) ...[
                      AdField(
                        label: tr('Sıfırlama kodu'),
                        child: TextFormField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          maxLength: 6,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, letterSpacing: 4),
                          decoration: _dec('______').copyWith(counterText: ''),
                          validator: (v) => (v == null || v.trim().length < 4)
                              ? tr('Kodu gir')
                              : null,
                        ),
                      ),
                      AdField(
                        label: tr('Yeni şifre'),
                        child: TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          onFieldSubmitted: (_) => loading ? null : _reset(),
                          decoration: _dec('••••••••',
                              suffix: IconButton(
                                tooltip: tr(_obscure
                                    ? 'Şifreyi göster'
                                    : 'Şifreyi gizle'),
                                icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: AppColors.muted,
                                    size: 20),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              )),
                          validator: (v) => (v == null || v.length < 6)
                              ? tr('En az 6 karakter')
                              : null,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    loading
                        ? FilledButton(
                            onPressed: null,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.coral,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            ),
                          )
                        : AdSaveButton(
                            label: _codeSent
                                ? tr('Şifreyi Sıfırla')
                                : tr('Sıfırlama Kodu Gönder'),
                            color: AppColors.coral,
                            onTap: _codeSent ? _reset : _requestCode,
                          ),
                    if (_codeSent) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: GestureDetector(
                          onTap: loading ? null : _requestCode,
                          child: Text(
                            tr('Kod gelmedi mi? Tekrar gönder'),
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.coralDark,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        suffixIcon: suffix,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.fever, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.fever, width: 1.5),
        ),
      );
}
