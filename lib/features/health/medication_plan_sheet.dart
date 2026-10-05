import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/medication.dart';
import '../../core/notification_service.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/medication_plan.dart';
import 'medication_widgets.dart';

/// Hazır öneriler — keşif kartı, boş durum ve "Yeni plan" sayfası ortak kullanır.
/// Yalnız AD + tipik saat önerir; doz bilerek boş bırakılır (doktor belirler).
List<({String name, String time})> medicationSuggestions() => [
      (name: tr('D vitamini'), time: '09:00'),
      (name: tr('Demir'), time: '08:00'),
      (name: tr('Probiyotik'), time: '12:00'),
      (name: tr('Multivitamin'), time: '10:00'),
    ];

/// "Günde kaç kez" seçimi saatleri bunlarla doldurur; "Özel"de dokunulmaz.
const _presets = <String, List<String>>{
  '1': ['09:00'],
  '2': ['08:00', '20:00'],
  '3': ['08:00', '14:00', '20:00'],
};

/// Bildirim id aralığı plan başına 10 slot ayırıyor (bkz. NotificationService).
const _maxTimes = 10;

/// Yeni plan / plan düzenleme sayfası. [presetName]/[presetTime] öneri
/// çipinden gelindiğinde alanları dolu açar.
Future<void> showMedicationPlanSheet(
  BuildContext context,
  String babyId, {
  MedicationPlan? existing,
  String? presetName,
  String? presetTime,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    shape: adSheetShape,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _PlanSheet(
          babyId: babyId,
          existing: existing,
          presetName: presetName,
          presetTime: presetTime),
    ),
  );
}

class _PlanSheet extends ConsumerStatefulWidget {
  final String babyId;
  final MedicationPlan? existing;
  final String? presetName;
  final String? presetTime;
  const _PlanSheet(
      {required this.babyId, this.existing, this.presetName, this.presetTime});

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  late final _name =
      TextEditingController(text: widget.existing?.name ?? widget.presetName ?? '');
  late final _dose = TextEditingController(text: widget.existing?.dose ?? '');
  late List<String> _times = widget.existing != null
      ? ([...widget.existing!.times]..sort())
      : [widget.presetTime ?? '09:00'];
  late String _freq = _freqFor(_times);
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  static String _freqFor(List<String> times) {
    for (final e in _presets.entries) {
      if (e.value.length == times.length &&
          List.generate(times.length, (i) => e.value[i] == times[i]).every((x) => x)) {
        return e.key;
      }
    }
    // Tek saat (ör. öneriden gelen 12:00) hâlâ "1 kez"dir.
    return times.length == 1 ? '1' : 'custom';
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  void _pickFreq(String f) {
    setState(() {
      _freq = f;
      final preset = _presets[f];
      if (preset == null) return;
      // "1 kez"e dönerken kullanıcının ilk saatini koru (09:00'a ezme).
      _times = f == '1' && _times.isNotEmpty ? [_times.first] : [...preset];
    });
  }

  Future<String?> _pickTime(String initial) async {
    final mins = medicationMinutes(initial);
    final picked = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: mins ~/ 60, minute: mins % 60));
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addTime() async {
    if (_times.length >= _maxTimes) return;
    final t = await _pickTime('16:00');
    if (t == null || _times.contains(t)) return;
    setState(() {
      _times = [..._times, t]..sort();
      _freq = _freqFor(_times);
    });
  }

  Future<void> _changeTime(String old) async {
    final t = await _pickTime(old);
    if (t == null || t == old || _times.contains(t)) return;
    setState(() {
      _times = [..._times.where((x) => x != old), t]..sort();
      _freq = _freqFor(_times);
    });
  }

  void _removeTime(String t) {
    setState(() {
      _times = _times.where((x) => x != t).toList();
      _freq = _freqFor(_times);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: adGrabHandle()),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2, bottom: 14),
              child: Row(
                children: [
                  AdIconChip('med', color: AppColors.med, bg: AppColors.medBg, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_isEdit ? tr('Planı düzenle') : tr('Yeni plan'),
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
            AdField(
              label: tr('Ad'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdInput(
                    controller: _name,
                    hint: tr('örn. D vitamini'),
                    capitalization: TextCapitalization.sentences,
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final s in medicationSuggestions())
                          MedChip(
                            label: s.name,
                            selected: s.name == name,
                            onTap: () => setState(() => _name.text = s.name),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            AdField(
              label: tr('Doz (opsiyonel)'),
              child: AdInput(controller: _dose, hint: tr('örn. 1 damla')),
            ),
            AdField(
              label: tr('Günde kaç kez?'),
              info: tr('Her gün bu saat(ler)de hatırlatma alırsın. Birden fazla '
                  'doz için saat ekleyebilirsin.'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdTabs(
                    options: {
                      for (final n in const ['1', '2', '3']) n: trp('{n} kez', {'n': n}),
                      'custom': tr('Özel'),
                    },
                    selected: _freq,
                    onSelect: _pickFreq,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final t in _times)
                        _TimeEdit(
                          time: t,
                          onTap: () => _changeTime(t),
                          onRemove: _times.length > 1 ? () => _removeTime(t) : null,
                        ),
                      if (_times.length < _maxTimes)
                        MedChip(
                          label: tr('Saat ekle'),
                          icon: 'plus',
                          dashed: true,
                          height: 40,
                          onTap: _addTime,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AdenaIcon('bell', size: 14, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(tr('Her saatte bildirim gelir'),
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            AdSaveButton(
              label: _isEdit ? tr('Kaydet') : tr('Planı ekle'),
              color: AppColors.coral,
              loading: _saving,
              onTap: _save,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SheetAction(
                      label: widget.existing!.active ? tr('Duraklat') : tr('Devam ettir'),
                      onTap: _togglePause,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SheetAction(label: tr('Sil'), danger: true, onTap: _delete),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showAdError(context, tr('İlaç/vitamin adını gir'));
      return;
    }
    // "Verildi" kayıtları plana ADIYLA eşlenir → aynı adlı iki plan birbirinin
    // dozunu kapatırdı.
    final others = ref.read(medicationPlansProvider(widget.babyId)).asData?.value ??
        const <MedicationPlan>[];
    final clash = others.any((p) =>
        p.id != widget.existing?.id && p.name.trim().toLowerCase() == name.toLowerCase());
    if (clash) {
      showAdError(context, tr('Bu adla bir plan zaten var'));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(healthRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateMedicationPlan(widget.existing!.id,
            name: name, dose: _dose.text.trim(), times: _times);
      } else {
        await repo.createMedicationPlan(widget.babyId,
            name: name, dose: _dose.text.trim(), times: _times);
      }
      ref.invalidate(medicationPlansProvider(widget.babyId));
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Kaydedildi'));
      }
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _togglePause() async {
    final p = widget.existing!;
    await ref.read(healthRepositoryProvider).updateMedicationPlan(p.id, active: !p.active);
    ref.invalidate(medicationPlansProvider(widget.babyId));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final p = widget.existing!;
    await ref.read(healthRepositoryProvider).deleteMedicationPlan(p.id);
    await NotificationService.instance.cancelMedicationPlan(p.id);
    ref.invalidate(medicationPlansProvider(widget.babyId));
    if (mounted) {
      Navigator.pop(context);
      showAdToast(context, tr('Plan silindi'));
    }
  }
}

/// Düzenlenebilir saat çipi: dokun → saat seçici, X → kaldır.
class _TimeEdit extends StatelessWidget {
  final String time;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _TimeEdit({required this.time, required this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: EdgeInsetsDirectional.only(start: 14, end: onRemove != null ? 4 : 14),
      decoration: BoxDecoration(
        color: fieldBg(context),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Text(time,
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          if (onRemove != null)
            Semantics(
              button: true,
              label: tr('Kaldır'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                      child: AdenaIcon('close', size: 14, color: AppColors.muted, sw: 2.2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final String label;
  final bool danger;
  final VoidCallback onTap;
  const _SheetAction({required this.label, required this.onTap, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: danger ? AppColors.feverBg : fieldBg(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  color: danger ? AppColors.coralDd : AppColors.ink2)),
        ),
      ),
    );
  }
}
