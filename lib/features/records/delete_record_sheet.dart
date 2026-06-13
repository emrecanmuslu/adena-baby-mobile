import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/record.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_controller.dart';
import '../babies/family_settings.dart';
import '../babies/members_screen.dart';
import 'record_controller.dart';
import 'record_ui.dart';

/// Kayıt silme onayı (design ScrEditModal — yalnız silme): kategori + tür özeti +
/// saat + "kim ne zaman ekledi" + Sil. Sil'e basınca soft-delete + undo'lu toast.
Future<void> showDeleteRecordSheet(
    BuildContext context, WidgetRef ref, Record record) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (_) => _DeleteRecordSheet(record: record),
  );
}

class _DeleteRecordSheet extends ConsumerWidget {
  final Record record;
  const _DeleteRecordSheet({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(activeUnitsProvider);
    final who = _resolveWho(ref);
    final stamp = DateFormat('d MMMM · HH:mm', 'tr_TR').format(record.ts);
    // Bakıcı yalnız KENDİ eklediği kaydı silebilir; owner/parent hepsini.
    final baby = ref.watch(activeBabyProvider);
    final me = ref.watch(authControllerProvider).asData?.value;
    final canDelete =
        (baby?.canFullWrite ?? true) || record.createdBy == me?.id;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Row(children: [
              RecordUi.chip(record.type, size: 38, radius: 13),
              const SizedBox(width: 10),
              Text(trp('{tur} kaydı', {'tur': RecordUi.label(record.type)}),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 16),
            AdField(
              label: tr('Tür'),
              child: _readonly(context, RecordUi.summary(record, units)),
            ),
            AdField(
              label: tr('Zaman'),
              child: _readonly(context, stamp),
            ),
            if (who != null)
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2, bottom: 6),
                child: Row(
                  children: [
                    _Av(initial: who.initial, color: who.color),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                          trp('{name} · {time}\'te ekledi',
                              {'name': who.name, 'time': RecordUi.time(record.ts)}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            if (canDelete)
              Material(
                color: AppColors.fever,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _delete(context, ref),
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AdenaIcon('trash', size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(tr('Sil'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                ),
              )
            else
              // Bakıcı, başkasının eklediği kaydı silemez — bilgi notu.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                    color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
                child: Text(
                    tr('Bu kaydı yalnız ekleyen kişi veya ebeveyn silebilir.'),
                    style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Kapat'),
                  style: TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readonly(BuildContext context, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
            color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
        child: Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      );

  void _delete(BuildContext context, WidgetRef ref) {
    final actions = ref.read(recordActionsProvider);
    actions.delete(record.id);
    Navigator.pop(context);
    showAdToast(context, tr('Kayıt silindi'),
        onUndo: () => actions.upsert(record.copyWith(isDeleted: false)));
  }

  /// created_by → görünen ad + baş harf + renk. Kendi kaydı → "Sen".
  ({String name, String initial, Color color})? _resolveWho(WidgetRef ref) {
    final cb = record.createdBy;
    if (cb == null) return null;
    final me = ref.watch(authControllerProvider).asData?.value;
    if (me != null && cb == me.id) {
      return (
        name: tr('Sen'),
        initial: (me.displayName.characters.firstOrNull ?? 'S').toUpperCase(),
        color: _avatarColor(cb),
      );
    }
    final members = ref.watch(membersProvider(record.baby)).asData?.value ?? const [];
    for (final m in members) {
      if (m.user.id == cb) {
        return (
          name: m.user.displayName,
          initial: (m.user.displayName.characters.firstOrNull ?? '?').toUpperCase(),
          color: _avatarColor(cb),
        );
      }
    }
    return null;
  }
}

const _avatarPalette = [
  Color(0xFFE2553F),
  Color(0xFF7C6BE0),
  Color(0xFF349970),
  Color(0xFF2F92C8),
  Color(0xFFB5821C),
];
Color _avatarColor(String id) => _avatarPalette[id.hashCode.abs() % _avatarPalette.length];

class _Av extends StatelessWidget {
  final String initial;
  final Color color;
  const _Av({required this.initial, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      alignment: Alignment.center,
      child: Text(initial,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}
