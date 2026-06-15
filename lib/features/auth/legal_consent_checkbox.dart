import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/legal_links.dart';
import '../../core/theme.dart';

/// Tek birleşik yasal rıza kutusu: "18 yaşındayım ve Gizlilik Politikası ile
/// Kullanım Şartları'nı kabul ediyorum." Linkler tıklanır (harici tarayıcı).
/// Kayıt ekranı + rıza kapısı ortak kullanır. İşaretlenmeden devam edilemez.
class LegalConsentCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<LegalConsentCheckbox> createState() => _LegalConsentCheckboxState();
}

class _LegalConsentCheckboxState extends State<LegalConsentCheckbox> {
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

  @override
  Widget build(BuildContext context) {
    final link = const TextStyle(
        color: AppColors.coralDark, fontWeight: FontWeight.w800);
    return InkWell(
      onTap: () => widget.onChanged(!widget.value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: widget.value,
                onChanged: (v) => widget.onChanged(v ?? false),
                activeColor: AppColors.coral,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: AppColors.ink2,
                        fontWeight: FontWeight.w600),
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
            ),
          ],
        ),
      ),
    );
  }
}
