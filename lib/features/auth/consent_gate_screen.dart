import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/language_quick_pick.dart';
import '../../core/theme.dart';
import '../../data/local_session.dart';
import 'auth_controller.dart';
import 'legal_consent_checkbox.dart';

/// Yasal rıza kapısı — sosyal giriş yapan ya da güncel sürümü kabul etmemiş
/// kullanıcıya uygulamaya girmeden önce gösterilir. Tek birleşik rıza (18+ ve
/// Gizlilik/Şartlar) alınınca backend'e yazılır ve router devam ettirir.
class ConsentGateScreen extends ConsumerStatefulWidget {
  const ConsentGateScreen({super.key});

  @override
  ConsumerState<ConsentGateScreen> createState() => _ConsentGateScreenState();
}

/// GDPR-eşdeğeri katı bölgeler (AB/AEA + İngiltere + İsviçre). Buralarda ön-işaretli
/// rıza kutusu GEÇERSİZ (CJEU Planet49) → analitik varsayılan KAPALI başlamalı.
/// Bu kümede OLMAYAN ülkelerde (ör. ABD) kutu varsayılan AÇIK başlayabilir → daha
/// çok kullanıcı opt-in olur, AB'yi riske atmadan. Bölge bilinmezse güvenli=kapalı.
const _strictConsentRegions = {
  // AB-27
  'AT', 'BE', 'BG', 'HR', 'CY', 'CZ', 'DK', 'EE', 'FI', 'FR', 'DE', 'GR', 'HU',
  'IE', 'IT', 'LV', 'LT', 'LU', 'MT', 'NL', 'PL', 'PT', 'RO', 'SK', 'SI', 'ES', 'SE',
  // AEA (AB dışı) + İngiltere + İsviçre
  'IS', 'LI', 'NO', 'GB', 'CH',
};

/// Cihaz bölgesine göre analitik kutusunun varsayılanı. Katı bölge veya bilinmeyen
/// ülke → false (kapalı, yasal güvenli); diğer → true (açık).
bool _defaultAnalyticsConsent() {
  final cc = PlatformDispatcher.instance.locale.countryCode?.toUpperCase();
  if (cc == null || cc.isEmpty) return false;
  return !_strictConsentRegions.contains(cc);
}

class _ConsentGateScreenState extends ConsumerState<ConsentGateScreen> {
  bool _accepted = false;
  // Opsiyonel analitik rızası — varsayılan bölgeye göre (AB/UK/CH kapalı, diğer açık).
  bool _analytics = _defaultAnalyticsConsent();
  bool _saving = false;

  Future<void> _continue() async {
    if (!_accepted) {
      showAdError(context, tr('Devam etmek için kutucuğu işaretlemelisin.'));
      return;
    }
    setState(() => _saving = true);
    try {
      // Rıza her zaman YERELDE kaydedilir (hesaptan bağımsız). Oturum açıksa
      // backend'e de yazılır (consentRequired düşer). Router'ı yerel rıza açar.
      await ref.read(localConsentProvider.notifier).accept();
      await ref.read(localAnalyticsConsentProvider.notifier).set(_analytics);
      if (ref.read(authControllerProvider).asData?.value != null) {
        await ref.read(authControllerProvider.notifier).recordConsent();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandWordmark(fontSize: 28)),
                  const SizedBox(height: 18),
                  Text(
                    tr('Başlamadan önce'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('Devam etmek için Gizlilik Politikası ve Kullanım Şartları\'nı '
                        'kabul etmen ve 18 yaşında veya üzeri olduğunu onaylaman gerekir.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppColors.softShadow,
                    ),
                    child: LegalConsentCheckbox(
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Opsiyonel: kullanım analitiği rızası (varsayılan bölgeye göre —
                  // AB/UK/CH kapalı, diğer açık; "Devam"ı engellemez, kullanıcı değiştirebilir).
                  InkWell(
                    onTap: () => setState(() => _analytics = !_analytics),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _analytics,
                              activeColor: AppColors.coral,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (v) =>
                                  setState(() => _analytics = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr('İsteğe bağlı: uygulamayı geliştirmemize yardımcı '
                                  'olmak için isimsiz kullanım istatistiklerini paylaş. '
                                  'İstediğin an Ayarlar\'dan kapatabilirsin.'),
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _saving
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: AppColors.coral)),
                          ),
                        )
                      : AdSaveButton(
                          label: tr('Devam et'),
                          color: AppColors.coral,
                          onTap: _continue),
                  // Çıkış yalnız oturum açıkken anlamlı (hesapsız free'de gizli).
                  if (ref.watch(authControllerProvider).asData?.value != null) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _saving ? null : _logout,
                        child: Text(tr('Çıkış yap'),
                            style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                  // Dil seçici — kullanıcı isterse en alttan dili değiştirir.
                  const SizedBox(height: 26),
                  const LanguageQuickPick(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
