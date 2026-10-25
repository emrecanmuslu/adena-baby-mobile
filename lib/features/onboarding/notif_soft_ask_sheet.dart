import 'package:flutter/material.dart';

import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/notif_soft_ask.dart';
import '../../core/notification_service.dart';
import 'onboarding_kit.dart';

/// Bildirim ön-izni alt sayfası (tasarım [9]) — dala göre metin. "Bildirimleri
/// aç" → sistem izin penceresi; "Şimdi değil" → sistem hiç çağrılmaz.
/// [force] false iken: daha önce sorulduysa ya da izin zaten açıksa açılmaz.
/// Dönüş: sistem bildirim izni açık mı.
Future<bool> showNotifSoftAsk(
  BuildContext context, {
  required OnbBranch branch,
  bool force = false,
}) async {
  final notif = NotificationService.instance;
  if (await notif.systemEnabled()) {
    await NotifSoftAsk.record(accepted: true);
    return true;
  }
  if (!force && await NotifSoftAsk.asked()) return false;
  if (!context.mounted) return false;
  final yes = await showOnbSheet<bool>(
    context,
    builder: (ctx) => _SoftAsk(branch: branch),
  );
  await NotifSoftAsk.record(accepted: yes == true);
  if (yes != true) return false;
  return notif.requestPermission();
}

class _SoftAsk extends StatelessWidget {
  final OnbBranch branch;
  const _SoftAsk({required this.branch});

  @override
  Widget build(BuildContext context) {
    final a = OnbAccent.of(context, branch);
    final (title, body) = switch (branch) {
      OnbBranch.baby => (
          tr('Sonraki beslenmeyi hatırlatalım mı?'),
          tr('Beslenme düzenine göre zamanı gelince haber veririz. Gece '
              'sessiz saatlere uyarız.'),
        ),
      OnbBranch.preg => (
          tr('Her hafta bebeğinin gelişimini haber verelim mi?'),
          tr('Yeni haftaya girdiğinde kısa bir not gönderelim.'),
        ),
      OnbBranch.cycle || OnbBranch.ttc => (
          tr('Adetin ve doğurgan pencerenden önce haber verelim mi?'),
          '',
        ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: a.soft, shape: BoxShape.circle),
            child: Stack(alignment: Alignment.center, children: [
              PositionedDirectional(
                top: 18,
                end: 14,
                child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: a.c.withValues(alpha: 0.35),
                        shape: BoxShape.circle)),
              ),
              PositionedDirectional(
                bottom: 22,
                start: 16,
                child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: a.c.withValues(alpha: 0.25),
                        shape: BoxShape.circle)),
              ),
              AdenaIcon('bell', size: 58, color: a.c, sw: 1.7),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1.25)),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: onbSubStyle()),
        ],
        const SizedBox(height: 24),
        OnbPrimaryButton(
          label: tr('Bildirimleri aç'),
          accent: a,
          onTap: () => Navigator.pop(context, true),
        ),
        const SizedBox(height: 4),
        OnbTextButton(
          label: tr('Şimdi değil'),
          onTap: () => Navigator.pop(context, false),
        ),
      ],
    );
  }
}
