import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/notification_service.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import 'cycle_engine.dart';
import 'cycle_widgets.dart';

/// Varsayılan hatırlatıcı yapısı (ayar boşsa).
Map<String, dynamic> _defaultReminders() => {
      'period': {'on': true},
      'fertile': {'on': true},
      'pms': {'on': false},
      'log': {'on': true, 'time': '21:00'},
    };

/// Ekran 8 — Adet modülü ayarları & hatırlatıcılar.
class CycleSettingsScreen extends ConsumerWidget {
  const CycleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(cycleSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Adet Takvimi Ayarları')),
      ),
      body: settingsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.coral)),
        error: (e, _) => Center(child: Text(apiErrorText(e))),
        data: (settings) => _Body(settings: settings),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  final CycleSettings settings;
  const _Body({required this.settings});

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late Map<String, dynamic> _reminders;
  late bool _fertilityWarn;

  @override
  void initState() {
    super.initState();
    final r = widget.settings.reminders;
    // Değerler {on, time} map'i olmalı; ama eski/seed veri {key: bool} biçiminde
    // olabilir → map'e normalize et (yoksa 'bool is not a subtype of Map' patlar).
    _reminders = r.isEmpty
        ? _defaultReminders()
        : {
            for (final e in r.entries)
              e.key: e.value is Map
                  ? Map<String, dynamic>.from(e.value as Map)
                  : {'on': e.value == true},
          };
    _fertilityWarn = widget.settings.showFertilityWarning;
  }

  bool _on(String k) => _reminders[k]?['on'] == true;

  Future<void> _persist({Map<String, dynamic>? reminders, bool? fertilityWarn}) async {
    final next = widget.settings.copyWith(
      reminders: reminders ?? _reminders,
      showFertilityWarning: fertilityWarn ?? _fertilityWarn,
    );
    try {
      await ref.read(cycleRepositoryProvider).patchSettings(next.toPatchJson());
      ref.invalidate(cycleSettingsProvider);
      // Hatırlatıcıları döngü tahminine göre yeniden planla.
      final entries = await ref.read(cycleRepositoryProvider).listEntries();
      final status = computeStatus(next, entries);
      await NotificationService.instance.syncCycle(
        reminders: next.reminders,
        nextPeriod: status.nextPeriod,
        fertileStart: status.fertileStart,
      );
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  void _toggle(String k, bool v) {
    setState(() => _reminders[k] = {..._reminders[k] ?? {}, 'on': v});
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
      children: [
        adSec(tr('Hatırlatıcılar'),
            info: tr('Hatırlatıcılar cihaz bildirimleri olarak gelir; sessiz saat '
                'ayarına uyar.')),
        _card([
          _switchRow(tr('Yaklaşan adet'), tr('3 gün öncesinden bildir'), 'period'),
          _switchRow(tr('Doğurganlık penceresi'), tr('Pencere başında bildir'), 'fertile'),
          _switchRow(tr('PMS hatırlatıcısı'), tr('Adetten ~5 gün önce'), 'pms'),
          _switchRow(tr('Günlük kayıt'), tr('Her gün 21:00'), 'log', last: true),
        ]),
        adSec(tr('Emzirme & Doğurganlık'), info: CycleInfo.lam),
        _card([
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tr('LAM / doğurganlık uyarıları'),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 5),
                          AdInfoDot(title: tr('LAM'), body: CycleInfo.lam),
                        ],
                      ),
                      Text(tr('Emziren anneler için hatırlatmalar'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
                Switch(
                  value: _fertilityWarn,
                  activeThumbColor: AppColors.rose,
                  onChanged: (v) {
                    setState(() => _fertilityWarn = v);
                    _persist(fertilityWarn: v);
                  },
                ),
              ],
            ),
          ),
        ]),
        adSec(tr('Emzirme Durumu')),
        AdMenuItem(
          icon: 'heart',
          color: AppColors.roseD,
          bg: AppColors.roseBg,
          title: _bfLabel(widget.settings.breastfeeding),
          meta: tr('Güncelle'),
          onTap: _editBreastfeeding,
        ),
        adSec(tr('Veri')),
        _card([
          InkWell(
            onTap: _confirmDeleteAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Tüm adet verilerini sil'),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.coralDd)),
                        Text(tr('Geri alınamaz'),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted)),
                      ],
                    ),
                  ),
                  Icon(Icons.delete_outline, size: 20, color: AppColors.coralDd),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        AdMenuItem(
          icon: 'moon',
          color: AppColors.roseD,
          bg: AppColors.roseBg,
          title: tr('Modülü gizle'),
          meta: tr('Keşfet menüsünden kaldır'),
          onTap: _confirmHide,
        ),
      ],
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.softShadow),
        child: Column(children: children),
      );

  Widget _switchRow(String title, String sub, String key, {bool last = false}) {
    return Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line))),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
              ],
            ),
          ),
          Switch(
            value: _on(key),
            activeThumbColor: AppColors.rose,
            onChanged: (v) => _toggle(key, v),
          ),
        ],
      ),
    );
  }

  String _bfLabel(Breastfeeding? b) => switch (b) {
        Breastfeeding.exclusive => '🤱 ${tr('Sadece anne sütü')}',
        Breastfeeding.mixed => '🍼 ${tr('Karışık beslenme')}',
        Breastfeeding.none => '🥛 ${tr('Emzirmiyorum')}',
        null => tr('Seçilmedi'),
      };

  Future<void> _editBreastfeeding() async {
    final picked = await showModalBottomSheet<Breastfeeding>(
      context: context,
      shape: adSheetShape,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            adGrabHandle(),
            for (final b in Breastfeeding.values)
              ListTile(
                title: Text(_bfLabel(b),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: widget.settings.breastfeeding == b
                    ? Icon(Icons.check, color: AppColors.rose)
                    : null,
                onTap: () => Navigator.pop(ctx, b),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final next = widget.settings.copyWith(breastfeeding: picked);
    try {
      await ref.read(cycleRepositoryProvider).patchSettings(next.toPatchJson());
      ref.invalidate(cycleSettingsProvider);
      if (mounted) showAdToast(context, tr('Güncellendi'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await _confirm(
        tr('Tüm adet verilerini sil'),
        tr('Tüm adet/loşia kayıtların kalıcı olarak silinecek. Bu işlem geri '
            'alınamaz.'));
    if (!ok) return;
    try {
      final entries = await ref.read(cycleRepositoryProvider).listEntries();
      for (final e in entries) {
        await ref.read(cycleRepositoryProvider).deleteEntry(e.id);
      }
      ref.invalidate(cycleEntriesProvider);
      if (mounted) showAdToast(context, tr('Silindi'));
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _confirmHide() async {
    final ok = await _confirm(
        tr('Modülü gizle'),
        tr('Adet Takvimi Keşfet menüsünden kaldırılacak. Verilerin silinmez; '
            'istediğinde ayarlardan tekrar açabilirsin.'));
    if (!ok) return;
    final next = widget.settings.copyWith(enabled: false);
    try {
      await ref.read(cycleRepositoryProvider).patchSettings(next.toPatchJson());
      ref.invalidate(cycleSettingsProvider);
      // Bekleyen hatırlatıcıları temizle.
      await NotificationService.instance.syncCycle(reminders: const {});
      if (mounted) {
        showAdToast(context, tr('Modül gizlendi'));
        context.go('/discover');
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Vazgeç'),
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Devam'),
                  style: const TextStyle(
                      color: AppColors.coralDd, fontWeight: FontWeight.w900))),
        ],
      ),
    );
    return r ?? false;
  }
}
