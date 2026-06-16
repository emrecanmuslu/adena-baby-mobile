import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';
import 'oauth_buttons.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).login(
          email: _email.text.trim(),
          password: _password.text,
        );
    // Yönlendirme router redirect ile otomatik; hata varsa aşağıda gösterilir.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;

    // Hata mesajını snackbar ile göster.
    ref.listen(authControllerProvider, (prev, next) {
      if (next.hasError && !next.isLoading) {
        showAdError(context, apiErrorText(next.error));
      }
    });

    return Scaffold(
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
                        tr('Tekrar hoş geldin 👋'),
                        style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(height: 30),
                    AdField(
                      label: tr('E-posta'),
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        decoration: _dec('ornek@eposta.com'),
                        validator: (v) =>
                            (v == null || !v.contains('@')) ? tr('Geçerli bir e-posta gir') : null,
                      ),
                    ),
                    AdField(
                      label: tr('Şifre'),
                      child: TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        onFieldSubmitted: (_) => loading ? null : _submit(),
                        decoration: _dec('••••••••',
                            suffix: IconButton(
                              tooltip:
                                  tr(_obscure ? 'Şifreyi göster' : 'Şifreyi gizle'),
                              icon: Icon(
                                  _obscure ? Icons.visibility_off : Icons.visibility,
                                  color: AppColors.muted, size: 20),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            )),
                        validator: (v) =>
                            (v == null || v.length < 6) ? tr('En az 6 karakter') : null,
                      ),
                    ),
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
                            label: tr('Giriş Yap'), color: AppColors.coral, onTap: _submit),
                    const OAuthSection(),
                    const SizedBox(height: 18),
                    Center(
                      child: GestureDetector(
                        onTap: loading ? null : () => context.go('/register'),
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700),
                            children: [
                              TextSpan(text: tr('Hesabın yok mu? ')),
                              TextSpan(
                                  text: tr('Kayıt ol'),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
