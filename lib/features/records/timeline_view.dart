import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/skeleton.dart';
import '../../core/theme.dart';
import '../../models/record.dart';
import '../auth/auth_controller.dart';
import '../babies/family_settings.dart';
import '../babies/members_screen.dart';
import 'delete_record_sheet.dart';
import 'record_controller.dart';
import 'record_detail_sheet.dart';
import 'record_ui.dart';

/// Günlük akış — yerel kayıtları güne göre gruplanmış liste hâlinde gösterir,
/// üstte türe göre filtre.
class TimelineView extends ConsumerStatefulWidget {
  final String babyId;
  const TimelineView({super.key, required this.babyId});

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  RecordType? _filter; // null = tümü
  late DateTime _day; // seçili gün (gece yarısı)

  static DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _day = _todayDate();
  }

  void _shiftDay(int delta) => setState(() {
        _day = _day.add(Duration(days: delta));
        _filter = null;
      });

  @override
  Widget build(BuildContext context) {
    final isToday = _day == _todayDate();
    final async = ref.watch(dayRecordsProvider((babyId: widget.babyId, day: _day)));
    final all = async.asData?.value;

    return Column(
      children: [
        _DayNav(
          label: _dayLabel(_day),
          onPrev: () => _shiftDay(-1),
          onNext: isToday ? null : () => _shiftDay(1),
        ),
        if (all != null && all.isNotEmpty) ...[
          _DayChip(records: all),
          _FilterBar(
            present: _presentTypes(all),
            selected: _filter,
            onSelect: (t) => setState(() => _filter = t),
          ),
        ],
        Expanded(
          child: all == null
              ? const SkeletonRecordList()
              : all.isEmpty
                  ? _EmptyDay(isToday: isToday)
                  : _buildList(_applyFilter(all)),
        ),
      ],
    );
  }

  List<RecordType> _presentTypes(List<Record> records) {
    final set = <RecordType>{for (final r in records) r.type};
    return RecordType.values.where(set.contains).toList();
  }

  List<Record> _applyFilter(List<Record> records) =>
      _filter == null ? records : records.where((r) => r.type == _filter).toList();

  Widget _buildList(List<Record> records) {
    if (records.isEmpty) {
      return Center(
        child: Text(tr('Bu türde kayıt yok'),
            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 92 + MediaQuery.of(context).padding.bottom),
      itemCount: records.length,
      itemBuilder: (_, i) => _RecordTile(record: records[i]),
    );
  }

  String _dayLabel(DateTime d) {
    final diff = _todayDate().difference(d).inDays;
    final date = fmtDayMonth(d);
    if (diff == 0) return trp('Bugün · {date}', {'date': date});
    if (diff == 1) return trp('Dün · {date}', {'date': date});
    return '${fmtWeekdayFull(d)} · $date';
  }
}

/// Tarih geçişi (design .ad-tlday): ‹ etiket › — gelecekte gün yok.
class _DayNav extends StatelessWidget {
  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  const _DayNav({required this.label, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _btn(context, 'chevL', onPrev),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          _btn(context, 'chevR', onNext),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, String icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: AppColors.softShadow,
        ),
        alignment: Alignment.center,
        child: AdenaIcon(icon,
            size: 17, color: onTap == null ? AppColors.muted2 : AppColors.ink),
      ),
    );
  }
}

/// Gün özeti çipi (design .ad-daychip): "X bez · Y beslenme · Zsa uyku".
class _DayChip extends StatelessWidget {
  final List<Record> records;
  const _DayChip({required this.records});

  @override
  Widget build(BuildContext context) {
    final diapers = records.where((r) => r.type == RecordType.diaper).length;
    final feeds = records.where((r) => r.type == RecordType.feed).length;
    var sleepMin = 0;
    for (final r in records) {
      if (r.type == RecordType.sleep && r.data['duration'] is num) {
        sleepMin += (r.data['duration'] as num).toInt();
      }
    }
    final parts = <String>[
      if (diapers > 0) trp('{n} bez', {'n': diapers}),
      if (feeds > 0) trp('{n} beslenme', {'n': feeds}),
      if (sleepMin > 0)
        trp('{n}sa uyku', {
          'n': (sleepMin / 60).truncateToDouble() == sleepMin / 60
              ? (sleepMin ~/ 60).toString()
              : (sleepMin / 60).toStringAsFixed(1)
        }),
    ];
    if (parts.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: AppColors.softShadow,
          ),
          child: Text(parts.join(' · '),
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.muted)),
        ),
      ),
    );
  }
}

/// Seçili günde kayıt yoksa.
class _EmptyDay extends StatelessWidget {
  final bool isToday;
  const _EmptyDay({required this.isToday});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AdenaIcon('timeline', size: 46, color: AppColors.peach),
            const SizedBox(height: 12),
            Text(isToday ? tr('Bugün henüz kayıt yok') : tr('Bu günde kayıt yok'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(isToday ? tr('Alttaki + ile ilk kaydını ekle.') : tr('Başka bir güne göz at.'),
                style:
                    TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Türe göre filtre çubuğu (yatay, kaydırılabilir). "Tümü" + kaydı olan türler.
class _FilterBar extends StatelessWidget {
  final List<RecordType> present;
  final RecordType? selected;
  final ValueChanged<RecordType?> onSelect;
  const _FilterBar({required this.present, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tr('Tümü')),
              selected: selected == null,
              onSelected: (_) => onSelect(null),
            ),
          ),
          ...present.map((t) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: RecordUi.icon(t,
                      size: 18,
                      color: selected == t ? AppColors.coralDark : RecordUi.color(t)),
                  label: Text(RecordUi.label(t)),
                  selected: selected == t,
                  onSelected: (_) => onSelect(t),
                ),
              )),
        ],
      ),
    );
  }
}

class _RecordTile extends ConsumerWidget {
  final Record record;
  const _RecordTile({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(activeUnitsProvider);
    final who = _resolveWho(ref);
    return Dismissible(
      key: ValueKey(record.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.fever.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.fever),
      ),
      confirmDismiss: (_) async {
        // Anında silme yerine: kim/ne zaman ekledi + Sil onayı (design ScrEditModal).
        await showDeleteRecordSheet(context, ref, record);
        return false; // silme sheet'te yönetilir; provider tazelenince satır gider
      },
      child: GestureDetector(
        onTap: () => showRecordDetailSheet(context, ref, record),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(
            children: [
              RecordUi.chip(record.type, size: 40, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(RecordUi.summary(record, units),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    if (who != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Av(initial: who.initial, color: who.color),
                          const SizedBox(width: 6),
                          Text(trp('{name} ekledi', {'name': who.name}),
                              style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ],
                      )
                    else
                      Text(RecordUi.label(record.type),
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                ),
              ),
              Text(RecordUi.time(record.ts),
                  style: TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
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

/// Küçük üye avatarı (design .ad-who) — 18px renkli daire + baş harf.
class _Av extends StatelessWidget {
  final String initial;
  final Color color;
  const _Av({required this.initial, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initial,
          style: const TextStyle(
              color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
    );
  }
}

