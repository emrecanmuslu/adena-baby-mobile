import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';
import 'i18n.dart';
import 'theme.dart';

/// Ayarlar altındaki sürüm + ortam göstergesi.
/// 1. satır: "Adena Baby · v1.0.0 (2)" — pubspec'ten runtime okunur (build no
///    artınca otomatik güncellenir).
/// 2. satır: derleme modu (DEBUG/RELEASE) + hangi API'ye bağlı (yerel/canlı) —
///    test sırasında "debug mi prod mu, hangi sunucu" sorusunu anında yanıtlar.
class AppVersionFooter extends StatelessWidget {
  const AppVersionFooter({super.key});

  static String _buildMode() {
    if (kDebugMode) return 'DEBUG';
    if (kProfileMode) return 'PROFILE';
    return 'RELEASE';
  }

  static String _apiLabel() {
    final host = Uri.tryParse(AppConfig.apiBaseUrl)?.host ?? AppConfig.apiBaseUrl;
    if (host.contains('adenababy.com')) return tr('canlı API');
    return trp('yerel API ({host})', {'host': host});
  }

  @override
  Widget build(BuildContext context) {
    // Debug build'i göze çarpsın (yanlışlıkla debug dağıtmayı fark etmek için).
    final isDebug = kDebugMode || kProfileMode;
    final envColor = isDebug ? AppColors.coralDark : AppColors.muted2;
    return Column(
      children: [
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) {
            final v = snap.data;
            final label = v == null
                ? 'Adena Baby'
                : 'Adena Baby · v${v.version} (${v.buildNumber})';
            return Text(
              label,
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            );
          },
        ),
        const SizedBox(height: 2),
        Text(
          '${_buildMode()} · ${_apiLabel()}',
          style: TextStyle(
              color: envColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3),
        ),
      ],
    );
  }
}
