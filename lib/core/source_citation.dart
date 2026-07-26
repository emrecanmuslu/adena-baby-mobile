import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'adena_icons.dart';
import 'theme.dart';

/// Sağlık/tıbbi içerik için tıklanabilir kaynak atfı (Apple guideline 1.4.1 —
/// tıbbi bilgi/hesaplama içeren ekranlarda kaynak linki zorunlu).
class SourceCitation extends StatelessWidget {
  final String label;
  final String url;
  const SourceCitation({super.key, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdenaIcon('link', size: 12, color: AppColors.muted, sw: 2),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ),
      ),
    );
  }
}
