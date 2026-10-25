import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../babies/baby_switcher.dart';
import 'auth_controller.dart';

/// Hesap açılınca bekleyen eylemi (Premium / davet kodu) bir kez çalıştırır.
/// Asıl ekranların build'inde çağrılır; oturum yoksa bir şey yapmaz.
/// [only] verilirse yalnız o eylemler işlenir — ör. karşılama ekranı Premium'u
/// işlemez: bebeksiz hesapta /premium router tarafından geri çevrilir ve
/// istek kaybolurdu; Premium, aktarım sonrası ana sayfada açılır.
void consumePendingAuthAction(BuildContext context, WidgetRef ref,
    {Set<PendingAuthAction>? only}) {
  final action = ref.watch(pendingAuthActionProvider);
  if (action == PendingAuthAction.none) return;
  if (only != null && !only.contains(action)) return;
  if (ref.watch(authControllerProvider).asData?.value == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted || ref.read(pendingAuthActionProvider) != action) return;
    ref.read(pendingAuthActionProvider.notifier).set(PendingAuthAction.none);
    switch (action) {
      case PendingAuthAction.premium:
        context.push('/premium');
      case PendingAuthAction.invite:
        showAcceptInviteDialog(context, ref);
      case PendingAuthAction.none:
        break;
    }
  });
}
