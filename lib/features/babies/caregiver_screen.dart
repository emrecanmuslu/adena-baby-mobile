import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../data/sharing_repository.dart';
import '../../models/activity_event.dart';
import '../../models/record.dart';
import '../../models/user.dart';
import '../records/record_ui.dart';
import 'baby_controller.dart';

/// Bakıcı akışı (design ScrCaregiver): ekibin canlı aktivite akışı (salt-okunur).
class CaregiverScreen extends ConsumerWidget {
  const CaregiverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    final activityAsync = ref.watch(activityProvider(baby.id));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Bakıcı akışı')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          adSec(tr('Canlı aktivite')),
          activityAsync.when(
            loading: () => Column(
              children: [
                for (var i = 0; i < 3; i++)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 9),
                    child: Skeleton(height: 62, radius: 16),
                  ),
              ],
            ),
            error: (e, _) => _Note(apiErrorText(e)),
            data: (events) {
              if (events.isEmpty) {
                return _Note(
                    tr('Ekip üyeleri kayıt ekledikçe burada canlı olarak görünür.'));
              }
              return Column(
                children: [for (final e in events) _ActivityRow(event: e)],
              );
            },
          ),
        ],
      ),
    );
  }

}

/// Aktivite satırı (design .ad-entry): kategori ikonu + "{actor} {eylem}" + avatar + zaman.
class _ActivityRow extends StatelessWidget {
  final ActivityEvent event;
  const _ActivityRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final type = _typeOf(event.action);
    final who = event.actor?.displayName ?? tr('Biri');
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          RecordUi.chip(type, size: 40, radius: 13),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trp('{who} {action}',
                        {'who': who, 'action': _actionLabel(event.action, type)}),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _Avatar(user: event.actor),
                    const SizedBox(width: 6),
                    Text(_relative(event.ts),
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Küçük kullanıcı avatarı (baş harf + kullanıcı rengi).
class _Avatar extends StatelessWidget {
  final User? user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final letter = (user?.displayName.characters.firstOrNull ?? '?').toUpperCase();
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _avatarColor(user)),
      alignment: Alignment.center,
      child: Text(letter,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10)),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
    );
  }
}

// ── yardımcılar ──

/// action kodundan kayıt tipi ("created_feed" → feed, "started_sleep" → sleep).
RecordType _typeOf(String action) {
  for (final t in RecordType.values) {
    if (action.contains(t.name)) return t;
  }
  return RecordType.feed;
}

/// "{actor} {eylem}" için Türkçe eylem etiketi.
String _actionLabel(String action, RecordType type) {
  if (action.contains('started_sleep')) return tr('uyku başlattı');
  if (action.contains('stopped_sleep') || action.contains('ended_sleep')) {
    return tr('uykuyu bitirdi');
  }
  if (action.startsWith('created_')) {
    return trp('{type} kaydı girdi', {'type': RecordUi.label(type)});
  }
  if (action.startsWith('updated_')) {
    return trp('{type} kaydını düzenledi', {'type': RecordUi.label(type)});
  }
  if (action.startsWith('deleted_')) {
    return trp('{type} kaydını sildi', {'type': RecordUi.label(type)});
  }
  return action.replaceAll('_', ' ');
}

String _relative(DateTime ts) {
  final d = DateTime.now().difference(ts);
  if (d.inMinutes < 1) return tr('az önce');
  if (d.inMinutes < 60) return trp('{n} dk önce', {'n': d.inMinutes});
  if (d.inHours < 24) return trp('{n} sa önce', {'n': d.inHours});
  if (d.inDays < 7) return trp('{n} gün önce', {'n': d.inDays});
  return fmtDayMon(ts);
}

Color _avatarColor(User? u) {
  final c = u?.avatarColor;
  if (c != null && c.isNotEmpty) {
    final hex = c.replaceAll('#', '');
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return AppColors.sleep;
}
