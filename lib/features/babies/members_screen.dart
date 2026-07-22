import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/premium_gate.dart';
import '../../core/theme.dart';
import '../../data/baby_repository.dart';
import '../../data/subscription_repository.dart';
import '../../features/community/community_ui.dart' show showDeleteConfirm;
import '../../models/membership.dart';
import 'activity_watcher.dart';
import 'baby_controller.dart';

/// Aktif bebeğin üye listesi (FutureProvider — davet/rol değişince invalidate).
final membersProvider = FutureProvider.family<List<Membership>, String>(
  (ref, babyId) => ref.watch(babyRepositoryProvider).members(babyId),
);

/// Paylaşım ekranı: üyeler + roller + davet (sahip yönetir).
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final isOwner = baby.myRole == 'owner';
    final showProBadge = ref.watch(isDefinitelyFreeProvider);
    final async = ref.watch(membersProvider(baby.id));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Aile / Paylaşım')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.coral)),
        error: (e, _) => Center(child: Text(apiErrorText(e))),
        data: (members) => RefreshIndicator(
          color: AppColors.coral,
          onRefresh: () async {
            ref.invalidate(membersProvider(baby.id));
            await ref.read(membersProvider(baby.id).future);
          },
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            adSec(tr('Bu bebeği takip edenler')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.softShadow,
              ),
              child: Column(
                children: [
                  for (var i = 0; i < members.length; i++)
                    _MemberRow(
                      membership: members[i],
                      babyId: baby.id,
                      canManage: isOwner && !members[i].isOwner,
                      last: i == members.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (isOwner)
              AdSaveButton(
                label: tr('＋  Eş / bakıcı davet et'),
                color: AppColors.coral,
                // Aile/ekip paylaşımı premium özellik — değilse upsell aç.
                onTap: () => requirePremium(
                  context,
                  ref,
                  feature: tr('Aile paylaşımı'),
                  desc: tr('Eşini ve bakıcıları davet et; herkes aynı bebeği '
                      'birlikte takip etsin. Premium ile sınırsız üye + reklamsız.'),
                  onAllowed: () => _invite(context, ref, baby.id),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  tr('Yalnızca sahip üye davet edebilir veya çıkarabilir.'),
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            adSec(tr('Ekip bakımı')),
            AdMenuItem(
              icon: 'bell',
              color: AppColors.med,
              bg: AppColors.medBg,
              title: tr('Bakıcı akışı'),
              meta: tr('Ekibin canlı aktivite akışı'),
              // Ekip bakımı premium — değilse rozet + upsell.
              trailing: showProBadge ? const AdProBadge(withChevron: true) : null,
              onTap: () => requirePremium(
                context,
                ref,
                feature: tr('Ekip bakımı'),
                desc: tr('Bakıcıların canlı aktivite akışını gör; herkes ne '
                    'yaptığını anında bilsin. Premium ile aç.'),
                onAllowed: () => context.push('/caregiver'),
              ),
            ),

            // Aile etkinlik bildirimi (opt-in, cihaz-yerel): bir üye kayıt
            // eklediğinde haber ver. Doğal yeri burası — paylaşımla ilgili tercih.
            adSec(tr('Bildirimler')),
            Builder(builder: (context) {
              final on =
                  ref.watch(activityNotifEnabledProvider).asData?.value ?? false;
              void toggle() =>
                  ref.read(activityNotifEnabledProvider.notifier).set(!on);
              final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdMenuItem(
                    icon: 'bell',
                    color: AppColors.coral,
                    bg: AppColors.feedBg,
                    title: tr('Aile etkinlik bildirimleri'),
                    meta: tr('Bir üye kayıt eklediğinde haber ver'),
                    trailing:
                        Switch.adaptive(value: on, onChanged: (_) => toggle()),
                    onTap: toggle,
                  ),
                  // iOS notu: bildirim kapalıyken + uygulama force-quit'teyken widget
                  // güncellenmez (Apple sınırı; sessiz push force-quit'i uyandıramaz).
                  if (isIOS)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                      child: Text(
                        tr('iPhone\'da: bu bildirim kapalıyken, uygulama tamamen '
                            'kapatıldığında (kaydırılıp kapatıldığında) ana ekran '
                            'widget\'ı güncellenmeyebilir. Uygulama açık veya arka '
                            'plandayken güncellenir.'),
                        style: TextStyle(
                            fontSize: 12, height: 1.35, color: AppColors.muted),
                      ),
                    ),
                ],
              );
            }),
          ],
          ),
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref, String babyId) async {
    String role = 'parent';
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('Davet oluştur')),
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(tr('Bu kişi hangi rolle katılsın?'),
                      style: TextStyle(color: AppColors.muted)),
                ),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: role,
                  onChanged: (v) => setState(() => role = v!),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: 'parent',
                        title: Text(tr('Ebeveyn')),
                        subtitle: Text(tr('Kayıt ekler, okur, düzenler')),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      RadioListTile<String>(
                        value: 'caregiver',
                        title: Text(tr('Bakıcı')),
                        subtitle: Text(tr('Kayıt ekler ve okur')),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text(tr('Vazgeç'))),
            ElevatedButton(
              onPressed: () async {
                try {
                  final res = await ref
                      .read(babyRepositoryProvider)
                      .createInvitation(babyId, role: role);
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, res);
                } catch (e) {
                  if (context.mounted) showAdError(context, apiErrorText(e));
                }
              },
              child: Text(tr('Oluştur')),
            ),
          ],
        ),
      ),
    );

    if (created != null && context.mounted) {
      _showInviteCode(context, created['invite_code'] as String);
    }
  }

  void _showInviteCode(BuildContext context, String code) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(tr('Davet kodu')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Bu kodu paylaş; karşı taraf "Davet kodu gir" ile katılsın.'),
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            SelectableText(code,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 12),
            Text(tr('Kod 1 gün geçerlidir ve yalnızca bir kez kullanılabilir.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text(tr('Kapat'))),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(dialogCtx);
              if (context.mounted) showAdToast(context, tr('Kod kopyalandı'));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(tr('Kopyala')),
          ),
        ],
      ),
    );
  }
}

/// Rol → (avatar gradyanı, pill zemini, pill yazısı, etiket) — design renkleri.
({List<Color> grad, Color pillBg, Color pillFg, String label}) _roleStyle(String role) =>
    switch (role) {
      'owner' => (
          grad: [const Color(0xFFFF9E8A), const Color(0xFFE2553F)],
          pillBg: AppColors.feedBg,
          pillFg: AppColors.coralDd,
          label: tr('Sahip')
        ),
      'parent' => (
          grad: [const Color(0xFFB3A6F2), const Color(0xFF7C6BE0)],
          pillBg: AppColors.sleepBg,
          pillFg: const Color(0xFF6F5FD6),
          label: tr('Ebeveyn')
        ),
      _ => (
          grad: [const Color(0xFF7FD4AC), const Color(0xFF349970)],
          pillBg: AppColors.growthBg,
          pillFg: const Color(0xFF349970),
          label: tr('Bakıcı')
        ),
    };

class _MemberRow extends ConsumerWidget {
  final Membership membership;
  final String babyId;
  final bool canManage;
  final bool last;
  const _MemberRow(
      {required this.membership,
      required this.babyId,
      required this.canManage,
      required this.last});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = membership.user;
    final s = _roleStyle(membership.role);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: s.grad,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            alignment: Alignment.center,
            child: Text((u.displayName.characters.firstOrNull ?? '?').toUpperCaseTr(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                const SizedBox(height: 1),
                Text(u.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration:
                BoxDecoration(color: s.pillBg, borderRadius: BorderRadius.circular(999)),
            child: Text(s.label,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w900, color: s.pillFg)),
          ),
          // Rol davet anında belirlenir; sonradan değiştirme yok. Sahip yalnız
          // üyeyi çıkarabilir.
          if (canManage)
            IconButton(
              icon: Icon(Icons.person_remove_outlined,
                  color: AppColors.muted, size: 20),
              tooltip: tr('Çıkar'),
              onPressed: () => _remove(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final name = membership.user.displayName;
    final ok = await showDeleteConfirm(
      context,
      title: trp('{name} çıkarılsın mı?', {'name': name}),
      message: tr('Bu kişi artık bu bebeği takip edemeyecek ve eklediği '
          'erişim kaldırılacak. Dilersen tekrar davet edebilirsin.'),
      confirmLabel: tr('Çıkar'),
    );
    if (!ok) return;
    try {
      await ref.read(babyRepositoryProvider).removeMember(babyId, membership.user.id);
      ref.invalidate(membersProvider(babyId));
      if (context.mounted) {
        showAdToast(context, trp('{name} çıkarıldı', {'name': membership.user.displayName}));
      }
    } catch (e) {
      if (context.mounted) showAdError(context, apiErrorText(e));
    }
  }
}
