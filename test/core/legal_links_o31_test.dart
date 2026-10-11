import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/i18n.dart';
import 'package:adena_baby/core/legal_links.dart';

/// O31 — 5 ek dil (zh/hi/es/fr/ar) kullanıcısına Türkçe değil İngilizce yasal
/// belge açılır (bilgilendirilmiş rıza; Apple 3.1.2(c)).
void main() {
  tearDown(() => I18n.instance.apply('tr', const {}));

  test('tr → /gizlilik/, en → /en/privacy/', () {
    I18n.instance.apply('tr', const {});
    expect(legalUrl(LegalDoc.privacy), endsWith('/gizlilik/'));
    I18n.instance.apply('en', const {});
    expect(legalUrl(LegalDoc.privacy), endsWith('/en/privacy/'));
  });

  test('es/fr/ar/hi/zh → İngilizce belge', () {
    for (final l in ['es', 'fr', 'ar', 'hi', 'zh']) {
      I18n.instance.apply(l, const {});
      expect(legalUrl(LegalDoc.terms), endsWith('/en/terms/'), reason: l);
    }
  });
}
