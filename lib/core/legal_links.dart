import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ad_widgets.dart';
import 'api_error.dart';
import 'config.dart';
import 'i18n.dart';

/// Yayınlanmış yasal belgeler (adenababy.com'da host edilir, içerik API'den
/// gelir). Her belgenin TR ve EN yolu FARKLI (basit prefix değil): TR kökte
/// `/gizlilik/`, EN `/en/privacy/` altında. Uygulama diline göre doğru yol seçilir.
enum LegalDoc { privacy, terms, kvkk, cookies }

/// Belge × locale → site yolu eşlemesi. Site Task 8'de bu yollarla yayınlandı.
const Map<LegalDoc, Map<String, String>> _paths = {
  LegalDoc.privacy: {'tr': '/gizlilik/', 'en': '/en/privacy/'},
  LegalDoc.terms: {'tr': '/kullanim-sartlari/', 'en': '/en/terms/'},
  LegalDoc.kvkk: {'tr': '/kvkk/', 'en': '/en/kvkk/'},
  LegalDoc.cookies: {'tr': '/cerezler/', 'en': '/en/cookies/'},
};

/// Geçerli uygulama diline göre belgenin tam URL'si.
String legalUrl(LegalDoc doc) {
  final locale = I18n.instance.locale == 'en' ? 'en' : 'tr';
  final path = _paths[doc]![locale]!;
  return '${AppConfig.websiteBaseUrl}$path';
}

/// Yasal belgeyi harici tarayıcıda açar. Açılamazsa kullanıcıya hata gösterir.
Future<void> openLegalDoc(BuildContext context, LegalDoc doc) async {
  final uri = Uri.parse(legalUrl(doc));
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showAdError(context, tr('Sayfa açılamadı. Lütfen daha sonra tekrar dene.'));
    }
  } catch (e) {
    if (context.mounted) showAdError(context, apiErrorText(e));
  }
}
