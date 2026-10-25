import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../data/memory_repository.dart';
import '../../data/mom_repository.dart';
import '../../data/push_error_repository.dart';
import '../../data/record_repository.dart';
import '../../data/sync_merge.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';

/// K-1 (TASARIM-SENKRON.md §6b): sunucunun KALICI reddettiği yerel
/// değişikliklerin listesi + "değişikliği geri al" / "tümünü geri al".
/// Geri al = sunucu kopyasını GET edip uygula (dirty=false, pushError=null);
/// satır sunucuda yoksa kullanıcı ONAYIYLA yerelden sil (bebek: silinmez,
/// yerelde temiz kalır — KARAR-BEKLEYEN.md).
void showPushErrorSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    shape: adSheetShape,
    isScrollControlled: true,
    builder: (_) => const _PushErrorSheet(),
  );
}

class _PushErrorSheet extends ConsumerStatefulWidget {
  const _PushErrorSheet();

  @override
  ConsumerState<_PushErrorSheet> createState() => _PushErrorSheetState();
}

class _PushErrorSheetState extends ConsumerState<_PushErrorSheet> {
  List<PushErrorItem>? _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final acct = ref.read(activeAccountIdProvider);
    final items = acct == null
        ? const <PushErrorItem>[]
        : await ref.read(pushErrorRepositoryProvider).list(acct);
    if (mounted) setState(() => _items = items);
  }

  String _kindLabel(PushErrorKind k) => switch (k) {
        PushErrorKind.baby => tr('Bebek'),
        PushErrorKind.memory => tr('Anı'),
        PushErrorKind.mom => tr('Anne takibi'),
        PushErrorKind.cycleEntry => tr('Âdet'),
        PushErrorKind.cycleSettings => tr('Âdet ayarları'),
        PushErrorKind.health => tr('Gelişim'),
      };

  String _healthLabel(String id) {
    if (id.startsWith('vaccine/')) return tr('Aşı');
    if (id.startsWith('tooth/')) return tr('Diş');
    return tr('Gelişim');
  }

  String _errorLabel(PushErrorItem it) {
    if (it.error == 'role') return tr('Bu işlem için ebeveyn/sahip olmalısın');
    if (it.isDeleted) return tr('Silme gönderilemedi');
    return it.error;
  }

  /// Tek öğe: sunucu kopyasını uygula; sunucuda yoksa onayla sil / yerelde bırak.
  /// Döner: öğe listeden düştü mü.
  Future<bool> _revert(PushErrorItem it, {bool confirm = true}) async {
    final repo = ref.read(pushErrorRepositoryProvider);
    final r = await repo.revert(it);
    switch (r) {
      case RevertResult.applied:
        _afterChange(it);
        if (mounted) showAdToast(context, tr('Sunucudaki hâli yüklendi'));
        return true;
      case RevertResult.failed:
        if (mounted) showAdError(context, tr('Sunucuya ulaşılamadı'));
        return false;
      case RevertResult.notOnServer:
        if (it.kind == PushErrorKind.baby && !it.isDeleted) {
          await repo.discard(it); // silmez: bayrak temizlenir, yerelde kalır
          _afterChange(it);
          if (mounted) showAdToast(context, tr('Bu kayıt yalnız bu cihazda kalacak'));
          return true;
        }
        if (confirm) {
          final ok = await _confirmDelete();
          if (!ok) return false;
        }
        if (it.kind == PushErrorKind.baby && it.isDeleted) {
          // Bekleyen bebek silmesi + sunucuda yok → yerel satır + çocuk verisi.
          final id = it.id;
          try {
            await ref.read(recordRepositoryProvider).purgeBaby(id);
            await ref.read(memoryRepositoryProvider).purgeBaby(id);
            await ref.read(momRepositoryProvider).purgeBaby(id);
            await ref.read(healthRepositoryProvider).purgeBaby(id);
          } catch (_) {}
        }
        await repo.discard(it);
        _afterChange(it);
        if (mounted) showAdToast(context, tr('Yerel değişiklik silindi'));
        return true;
    }
  }

  void _afterChange(PushErrorItem it) {
    switch (it.kind) {
      case PushErrorKind.baby:
        ref.read(babyControllerProvider.notifier).refresh();
        if (it.babyId != null) ref.invalidate(familySettingsProvider(it.babyId!));
      case PushErrorKind.health:
        final b = it.babyId!;
        ref.invalidate(vaccinesProvider(b));
        ref.invalidate(milestonesProvider(b));
        ref.invalidate(teethProvider(b));
      case PushErrorKind.memory:
      case PushErrorKind.mom:
      case PushErrorKind.cycleEntry:
      case PushErrorKind.cycleSettings:
        break; // Stream provider'lar DB'den kendiliğinden tazelenir
    }
  }

  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(tr('Bu kayıt sunucuda yok. Yerel değişiklik silinsin mi?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vazgeç'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sil'))),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _one(PushErrorItem it) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _revert(it);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  /// Tümü: sunucuda olanlar uygulanır; sunucuda olmayanlar listede kalır
  /// (tek tek onay gerektirir — toplu sessiz silme YOK).
  Future<void> _all() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      for (final it in List.of(_items ?? const <PushErrorItem>[])) {
        if (!mounted) return;
        final r = await ref.read(pushErrorRepositoryProvider).revert(it);
        if (r == RevertResult.applied) _afterChange(it);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          adGrabHandle(),
          const SizedBox(height: 12),
          Text(tr('Gönderilemeyen değişiklikler'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (items == null)
            const Padding(
                padding: EdgeInsets.all(24), child: CircularProgressIndicator())
          else if (items.isEmpty)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr('Sunucudaki hâli yüklendi'),
                    style: TextStyle(color: AppColors.muted)))
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final it = items[i];
                  final kind = it.kind == PushErrorKind.health
                      ? _healthLabel(it.id)
                      : _kindLabel(it.kind);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('$kind · ${it.title}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        [if (it.subtitle != null) it.subtitle!, _errorLabel(it)]
                            .join(' · '),
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _one(it),
                      child: Text(tr('Değişikliği geri al')),
                    ),
                  );
                },
              ),
            ),
          if (items != null && items.length > 1) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _all,
                child: Text(tr('Tümünü geri al')),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
