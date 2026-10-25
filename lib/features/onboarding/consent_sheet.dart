import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/legal_links.dart';
import '../../core/theme.dart';
import '../../data/local_session.dart';
import '../auth/auth_controller.dart';
import 'onboarding_kit.dart';

/// GDPR-eşdeğeri katı bölgeler (AB/AEA + İngiltere + İsviçre). Buralarda ön-işaretli
/// rıza kutusu GEÇERSİZ (CJEU Planet49) → analitik varsayılan KAPALI başlamalı.
/// Bu kümede OLMAYAN ülkelerde (ör. ABD) varsayılan AÇIK başlayabilir.
/// Bölge bilinmezse güvenli=kapalı.
const _strictConsentRegions = {
  // AB-27
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU',
  'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
  // AEA (AB dışı) + İngiltere + İsviçre
  'IS', 'LI', 'NO', 'GB', 'CH',
};

/// Cihaz bölgesine göre analitik anahtarının varsayılanı. Katı bölge veya
/// bilinmeyen ülke → false (kapalı, yasal güvenli); diğer → true (açık).
bool defaultAnalyticsConsent() {
  final cc = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
  if (cc == null || cc.isEmpty) return false;
  return !_strictConsentRegions.contains(cc);
}

/// Rızayı kaydet: her zaman YERELDE (hesaptan bağımsız) + oturum açıksa
/// backend'e (consentRequired düşer).
Future<void> recordLocalConsent(WidgetRef ref, {required bool analytics}) async {
  await ref.read(localConsentProvider.notifier).accept();
  await ref.read(localAnalyticsConsentProvider.notifier).set(analytics);
  if (ref.read(authControllerProvider).asData?.value != null) {
    await ref.read(authControllerProvider.notifier).recordConsent();
  }
}

/// "Başlamadan önce" alt sayfası (tasarım [2]) — ilk hedef kartı dokunuşunda
/// (ya da kayıt olmadan önce) bir kez. Kabul edilirse true döner; buton
/// dokunulan kartın aksan rengini alır.
Future<bool> showConsentSheet(BuildContext context, {required OnbAccent accent}) async {
  final ok = await showOnbSheet<bool>(
    context,
    builder: (_) => ConsentForm(accent: accent, inSheet: true),
  );
  return ok == true;
}

/// Rıza içeriği — alt sayfada ve (giriş sonrası) rıza kapısı ekranında ortak.
class ConsentForm extends ConsumerStatefulWidget {
  final OnbAccent accent;

  /// Alt sayfa içinde → kabulde `Navigator.pop(true)`; ekranda → router devam ettirir.
  final bool inSheet;
  const ConsentForm({super.key, required this.accent, this.inSheet = false});

  @override
  ConsumerState<ConsentForm> createState() => _ConsentFormState();
}

class _ConsentFormState extends ConsumerState<ConsentForm> {
  bool _accepted = false;
  bool _analytics = defaultAnalyticsConsent();
  bool _saving = false;
  late final TapGestureRecognizer _privacyTap;
  late final TapGestureRecognizer _termsTap;

  @override
  void initState() {
    super.initState();
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => openLegalDoc(context, LegalDoc.privacy);
    _termsTap = TapGestureRecognizer()
      ..onTap = () => openLegalDoc(context, LegalDoc.terms);
  }

  @override
  void dispose() {
    _privacyTap.dispose();
    _termsTap.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() => _saving = true);
    try {
      await recordLocalConsent(ref, analytics: _analytics);
      if (mounted && widget.inSheet) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    final link = TextStyle(
        color: a.t,
        fontWeight: FontWeight.w900,
        decoration: TextDecoration.underline,
        decorationColor: a.t);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('Başlamadan önce'),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
        const SizedBox(height: 8),
        Text(
            tr('Adena\'yı kullanmak için 18 yaşında veya üzeri olman ve şartları '
                'kabul etmen gerekiyor.'),
            style: onbSubStyle()),
        const SizedBox(height: 20),
        // Zorunlu kutu — tüm satır dokunulabilir; linkler ayrı.
        Semantics(
          checked: _accepted,
          child: GestureDetector(
            onTap: () => setState(() => _accepted = !_accepted),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: onbFieldFill(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: _accepted ? a.c : onbFieldBorder(context),
                    width: _accepted ? 1.5 : 1),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _accepted ? a.c : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: _accepted
                        ? null
                        : Border.all(color: AppColors.muted2, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: _accepted
                      ? const AdenaIcon('check', size: 16, color: Colors.white, sw: 3.2)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                          fontSize: 14.5,
                          height: 1.45,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                      children: [
                        TextSpan(text: tr('18 yaşındayım ve ')),
                        TextSpan(
                            text: tr('Gizlilik Politikası'),
                            style: link,
                            recognizer: _privacyTap),
                        TextSpan(text: tr(' ile ')),
                        TextSpan(
                            text: tr('Kullanım Şartları'),
                            style: link,
                            recognizer: _termsTap),
                        TextSpan(text: tr('\'nı kabul ediyorum.')),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // İsteğe bağlı analitik — kutu değil anahtar: zorunlu onaydan ayrışır.
        MergeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Uygulamayı geliştirmemize yardım et'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                      tr('İsimsiz kullanım istatistikleri. İstediğin an '
                          'Ayarlar\'dan kapatabilirsin.'),
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted)),
                ]),
              ),
              const SizedBox(width: 14),
              Switch(
                value: _analytics,
                activeThumbColor: Colors.white,
                activeTrackColor: a.c,
                inactiveTrackColor: AppColors.line2,
                inactiveThumbColor: Colors.white,
                trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                onChanged: (v) => setState(() => _analytics = v),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        OnbPrimaryButton(
          label: tr('Kabul et ve devam et'),
          accent: a,
          loading: _saving,
          onTap: _accepted ? _continue : null,
        ),
      ],
    );
  }
}
