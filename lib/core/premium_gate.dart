import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/subscription_repository.dart';
import 'adena_icons.dart';
import 'i18n.dart';
import 'theme.dart';

/// Premium duvarı: kullanıcı premium ise [onAllowed] çalışır; değilse özelliği
/// tanıtan bir upsell sayfası açar ve "Premium'a Geç" derse /premium'a götürür.
///
/// Kullanım: `requirePremium(context, ref, feature: tr('Aile paylaşımı'),
///   desc: tr('...'), onAllowed: () => _invite(...))`
Future<void> requirePremium(
  BuildContext context,
  WidgetRef ref, {
  required String feature,
  required String desc,
  required VoidCallback onAllowed,
}) async {
  if (ref.read(isPremiumProvider)) {
    onAllowed();
    return;
  }
  final go = await showPremiumUpsell(context, feature: feature, desc: desc);
  if (go == true && context.mounted) context.push('/premium');
}

/// Premium tanıtım sayfası (alt sheet). Döner: kullanıcı "Premium'a Geç" dedi mi.
Future<bool?> showPremiumUpsell(
  BuildContext context, {
  required String feature,
  required String desc,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
                color: AppColors.line, borderRadius: BorderRadius.circular(99)),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.premiumGoldLight, AppColors.premiumGold],
              ),
            ),
            alignment: Alignment.center,
            child: const AdenaIcon('star', size: 28, color: Colors.white, sw: 2.2),
          ),
          const SizedBox(height: 12),
          Text(feature,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(desc,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coral,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr("Premium'a Geç"),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Şimdi değil'),
                style: TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
}
