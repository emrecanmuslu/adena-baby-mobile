import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/glass.dart';
import '../../core/i18n.dart';
import '../../core/legal_links.dart';
import '../../core/session_end.dart';
import '../../core/theme.dart';
import '../../data/local_session.dart';
import '../onboarding/consent_sheet.dart';
import '../onboarding/onboarding_kit.dart';
import 'auth_controller.dart';
import 'oauth_buttons.dart';

/// Giriş/hesap ekranının hangi bağlamdan açıldığı — üstteki açıklama satırı.
enum AuthContext { none, invite, premium }

AuthContext authContextFrom(String? q) => switch (q) {
      'invite' => AuthContext.invite,
      'premium' => AuthContext.premium,
      _ => AuthContext.none,
    };

/// Giriş yap / Hesap oluştur — tek ekran, iki sekme (tasarım [7]). Hesap
/// isteğe bağlıdır: karşılamadaki "Giriş yap", davet kodu ve premium/yedekleme
/// akışlarından açılır. Rıza kutusu YOK — rıza "Başlamadan önce" sayfasında
/// bir kez alınır (alınmadıysa hesap oluşturmadan önce o sayfa açılır).
class AuthScreen extends ConsumerStatefulWidget {
  final bool register;
  final AuthContext ctx;
  const AuthScreen({super.key, this.register = false, this.ctx = AuthContext.none});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late bool _register = widget.register;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  late final TapGestureRecognizer _termsTap;

  /// O1: zorunlu çıkış nedeni — bir kez gösterilir, gösterilince provider +
  /// prefs temizlenir (eski neden sonraki çıkışta yanlış banner göstermesin).
  SessionEndReason? _endReason;

  @override
  void initState() {
    super.initState();
    _termsTap = TapGestureRecognizer()
      ..onTap = () => openLegalDoc(context, LegalDoc.terms);
    _endReason = ref.read(sessionEndReasonProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ref.read(sessionEndReasonProvider.notifier).set(null);
      if (_endReason == null) {
        final persisted = await SessionEndCache.read(); // başka isolate/süreç
        if (persisted != null && mounted) setState(() => _endReason = persisted);
      }
      await SessionEndCache.clear();
    });
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _endReasonText(SessionEndReason r) => switch (r) {
        SessionEndReason.superseded => tr(
            'Hesabına başka bir cihazdan giriş yapıldı; bu cihazdaki oturum kapatıldı.'),
        SessionEndReason.expired => tr('Oturumun sona erdi. Lütfen tekrar giriş yap.'),
        SessionEndReason.unknown => tr('Oturumun sonlandırıldı. Lütfen tekrar giriş yap.'),
      };

  /// Hesap oluşturmadan (ya da sosyal girişten) önce yasal rıza — yerelde
  /// alınmadıysa "Başlamadan önce" sayfası açılır.
  Future<bool> _ensureConsent() async {
    if (ref.read(localConsentProvider)) return true;
    return showConsentSheet(context, accent: OnbAccent.coral(context));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final auth = ref.read(authControllerProvider.notifier);
    if (_register) {
      if (!await _ensureConsent()) return;
      await auth.register(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim());
    } else {
      await auth.login(email: _email.text.trim(), password: _password.text);
    }
    // Yönlendirme router redirect ile otomatik; hata varsa aşağıda gösterilir.
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/onboarding');
    }
  }

  String get _title => switch (widget.ctx) {
        AuthContext.invite =>
          tr('Davete katılmak için giriş yap ya da hesap oluştur.'),
        AuthContext.premium => tr('Premium ve bulut yedekleme hesabınla çalışır.'),
        AuthContext.none =>
          _register ? tr('Hesabını oluştur 💛') : tr('Tekrar hoş geldin 👋'),
      };

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;
    final coral = OnbAccent.coral(context);
    final linkColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.coral
        : AppColors.coralDd;

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
                          child: OnbBackButton(onTap: _back),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_title,
                          style: TextStyle(
                              fontSize: widget.ctx == AuthContext.none ? 28 : 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              height: 1.25)),
                      if (_endReason != null) ...[
                        const SizedBox(height: 14),
                        _ForcedBand(
                          text: _endReasonText(_endReason!),
                          onClose: () => setState(() => _endReason = null),
                        ),
                      ],
                      const SizedBox(height: 18),
                      OnbSegment<bool>(
                        accent: coral,
                        selected: _register,
                        onChanged: loading
                            ? (_) {}
                            : (v) => setState(() => _register = v),
                        options: [
                          (false, tr('Giriş yap')),
                          (true, tr('Hesap oluştur')),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_register) ...[
                        OnbLabel(tr('Adın')),
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                          decoration: onbInputDecoration(context,
                              hint: tr('Ayşe'), accent: coral),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? tr('Adını gir')
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      OnbLabel(tr('E-posta')),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                        decoration: onbInputDecoration(context,
                            hint: 'ornek@eposta.com', accent: coral),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? tr('Geçerli bir e-posta gir')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      OnbLabel(_register
                          ? tr('Şifre (en az 6 karakter)')
                          : tr('Şifre')),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: [
                          _register
                              ? AutofillHints.newPassword
                              : AutofillHints.password
                        ],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => loading ? null : _submit(),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                        decoration: onbInputDecoration(
                          context,
                          hint: '••••••',
                          accent: coral,
                          suffix: IconButton(
                            tooltip: tr(_obscure ? 'Şifreyi göster' : 'Şifreyi gizle'),
                            icon: AdenaIcon('eye',
                                size: 20, color: AppColors.muted, sw: 2),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? tr('En az 6 karakter')
                            : null,
                      ),
                      if (!_register)
                        Row(children: [
                          const Spacer(),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: loading
                                ? null
                                : () => context.push('/forgot-password'),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 40),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.center,
                              child: Text(tr('Şifremi unuttum'),
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: linkColor)),
                            ),
                          ),
                        ]),
                      const SizedBox(height: 14),
                      OnbPrimaryButton(
                        label: _register ? tr('Hesap oluştur') : tr('Giriş yap'),
                        accent: coral,
                        loading: loading,
                        onTap: _submit,
                      ),
                      if (_register)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: tr('Kayıt olarak ')),
                              TextSpan(
                                  text: tr('Kullanım Şartları'),
                                  recognizer: _termsTap,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink2,
                                      decoration: TextDecoration.underline)),
                              TextSpan(text: tr('\'nı kabul etmiş olursun.')),
                            ]),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted),
                          ),
                        ),
                      OAuthSection(beforeSignIn: _ensureConsent),
                      // Yalnız debug: oturum açmadan API ortamını değiştirebilmek
                      // için Geliştirici sayfasına kısayol.
                      if (kDebugMode) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => context.push('/dev'),
                            icon: const Icon(Icons.settings_outlined, size: 16),
                            label: const Text('Geliştirici'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.muted),
                          ),
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

/// Zorunlu çıkış bandı (peach) — × ile kapanır.
class _ForcedBand extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const _ForcedBand({required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: dark ? AppColors.coral.withValues(alpha: 0.12) : AppColors.peachLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.coral.withValues(alpha: dark ? 0.35 : 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: AdenaIcon('info',
              size: 18,
              color: dark ? AppColors.coral : AppColors.coralDd,
              sw: 2.2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink2)),
        ),
        Semantics(
          button: true,
          label: MaterialLocalizations.of(context).closeButtonTooltip,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onClose,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                  child: AdenaIcon('close',
                      size: 16, color: AppColors.ink2, sw: 2.4)),
            ),
          ),
        ),
      ]),
    );
  }
}
