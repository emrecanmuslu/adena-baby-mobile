import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/exact_alarm_prompt.dart';
import '../../core/api_error.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/dates.dart';
import '../../core/medication.dart';
import '../../core/medication/med_names.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../babies/exact_alarm_resync.dart';
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

/// Plan formu girdisi (İlaç v2, ILAC-TASARIM §5.1) — doğrulama saf ve testli.
class MedPlanDraft {
  final String name;
  final MedKind kind;
  final MedFreq freq;
  final List<String> times;
  final int? intervalHours;
  final int? everyNDays;
  final Set<int> weekdays;
  final DateTime start;
  final DateTime? end;
  final int? prnMinIntervalMin;
  final int? prnMaxPerDay;
  const MedPlanDraft({
    required this.name,
    required this.kind,
    required this.freq,
    required this.times,
    this.intervalHours,
    this.everyNDays,
    this.weekdays = const {},
    required this.start,
    this.end,
    this.prnMinIntervalMin,
    this.prnMaxPerDay,
  });
}

/// Formdaki ilk hata metni (çevrilmiş) ya da null. [taken] = bu bebeğin
/// (düzenlenen hariç) diğer plan adları.
String? validateMedPlanDraft(MedPlanDraft d, Iterable<String> taken) {
  if (d.name.trim().isEmpty) return tr('İlaç/vitamin adını gir');
  final key = medNameKey(d.name);
  if (taken.any((n) => medNameKey(n) == key)) return tr('Bu adla bir plan zaten var');
  if (d.kind == MedKind.scheduled) {
    if (d.times.isEmpty) return tr('En az bir saat ekle');
    switch (d.freq) {
      case MedFreq.interval:
        final h = d.intervalHours;
        if (h == null || h < 1 || h > 48) return tr('Aralık 1–48 saat olmalı');
      case MedFreq.everyNDays:
        final n = d.everyNDays;
        if (n == null || n < 2 || n > 30) return tr('Gün aralığı 2–30 olmalı');
      case MedFreq.weekly:
        if (d.weekdays.isEmpty) return tr('En az bir gün seç');
      case MedFreq.daily:
        break;
    }
  } else {
    final m = d.prnMinIntervalMin;
    if (m != null && (m < 1 || m > 10080)) return tr('En kısa aralık en çok 7 gün olabilir');
    final x = d.prnMaxPerDay;
    if (x != null && (x < 1 || x > 48)) return tr('Günlük sınır 1–48 olmalı');
  }
  if (d.end != null && d.end!.isBefore(d.start)) {
    return tr('Bitiş tarihi başlangıçtan önce olamaz');
  }
  return null;
}

/// Kür süresi seçimi.
enum _Course { none, days, date }

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  late final MedicationPlan? _ex = widget.existing;
  late final _name = TextEditingController(text: _ex?.name ?? widget.presetName ?? '');
  late final _dose = TextEditingController(text: _ex?.dose ?? '');
  late MedKind _kind = _ex?.kind ?? MedKind.scheduled;
  late MedFreq _sched = _ex?.freq ?? MedFreq.daily;
  late List<String> _times = (_ex != null && _ex.times.isNotEmpty)
      ? ([..._ex.times]..sort())
      : [widget.presetTime ?? '09:00'];
  late String _freq = _freqFor(_times);
  late final _interval = TextEditingController(text: '${_ex?.intervalHours ?? 8}');
  late final _everyN = TextEditingController(text: '${_ex?.everyNDays ?? 2}');
  late Set<int> _weekdays = {...?_ex?.weekdays.toSet()}.isNotEmpty
      ? _ex!.weekdays.toSet()
      : {DateTime.now().weekday};
  late DateTime _start = _ex?.startDate ?? _today();
  late _Course _course = _ex?.endDate == null ? _Course.none : _Course.date;
  late DateTime? _end = _ex?.endDate;
  late final _days = TextEditingController(
      text: _ex?.endDate != null && _ex?.startDate != null
          ? '${_ex!.endDate!.difference(_ex.startDate!).inDays + 1}'
          : '7');
  late final _prnH = TextEditingController(
      text: _ex?.prnMinIntervalMin == null ? '' : '${_ex!.prnMinIntervalMin! ~/ 60}');
  late final _prnM = TextEditingController(
      text: _ex?.prnMinIntervalMin == null ? '' : '${_ex!.prnMinIntervalMin! % 60}');
  late final _prnMax =
      TextEditingController(text: _ex?.prnMaxPerDay == null ? '' : '${_ex!.prnMaxPerDay}');
  bool _saving = false;

  bool get _isEdit => _ex != null;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

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
    for (final c in [_name, _dose, _interval, _everyN, _days, _prnH, _prnM, _prnMax]) {
      c.dispose();
    }
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

  Future<DateTime?> _pickDate(DateTime initial, {DateTime? first}) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first ?? DateTime(2020),
        lastDate: DateTime(2100),
      );

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  DateTime? get _resolvedEnd => switch (_course) {
        _Course.none => null,
        _Course.days => _int(_days) == null || _int(_days)! < 1
            ? null
            : MedicationPlan.endDateForDays(_start, _int(_days)!),
        _Course.date => _end,
      };

  int? get _prnMinutes {
    final h = _int(_prnH), m = _int(_prnM);
    if (h == null && m == null) return null;
    final total = (h ?? 0) * 60 + (m ?? 0);
    return total == 0 ? null : total;
  }

  /// "Her X saatte" önizleme (ilk 4 doz).
  String _intervalPreview() {
    final h = _int(_interval);
    if (h == null || h < 1 || h > 48 || _times.isEmpty) return '';
    final m0 = medicationMinutes(_times.first);
    return [
      for (var i = 0; i < 4; i++)
        () {
          final m = (m0 + i * h * 60) % (24 * 60);
          return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
        }()
    ].join(' · ');
  }

  Widget _num(TextEditingController c, String hint, {double width = 80}) => SizedBox(
        width: width,
        child: AdInput(
          controller: c,
          hint: hint,
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      );

  Widget _timesEditor({bool single = false}) => Wrap(
        spacing: 7,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final t in single ? _times.take(1) : _times)
            _TimeEdit(
              time: t,
              onTap: () => _changeTime(t),
              onRemove: !single && _times.length > 1 ? () => _removeTime(t) : null,
            ),
          if (!single && _times.length < _maxTimes)
            MedChip(label: tr('Saat ekle'), icon: 'plus', dashed: true, height: 40, onTap: _addTime),
        ],
      );

  List<Widget> _scheduleFields() {
    final labelStyle =
        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.muted);
    return [
      AdField(
        label: tr('Sıklık'),
        child: Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final f in MedFreq.values)
              MedChip(
                label: switch (f) {
                  MedFreq.daily => tr('Her gün'),
                  MedFreq.interval => tr('Her X saatte'),
                  MedFreq.everyNDays => tr('Gün aşırı / N günde'),
                  MedFreq.weekly => tr('Haftalık'),
                },
                selected: _sched == f,
                onTap: () => setState(() => _sched = f),
              ),
          ],
        ),
      ),
      if (_sched == MedFreq.daily)
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
              _timesEditor(),
            ],
          ),
        ),
      if (_sched == MedFreq.interval)
        AdField(
          label: tr('Her kaç saatte bir?'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 7,
                runSpacing: 7,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final h in const [4, 6, 8, 12])
                    MedChip(
                      label: trp('{n} sa', {'n': h}),
                      selected: _int(_interval) == h,
                      onTap: () => setState(() => _interval.text = '$h'),
                    ),
                  _num(_interval, '8', width: 70),
                ],
              ),
              const SizedBox(height: 10),
              Text(tr('İlk doz'), style: labelStyle),
              const SizedBox(height: 6),
              _timesEditor(single: true),
              if (_intervalPreview().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_intervalPreview(), style: labelStyle),
              ],
            ],
          ),
        ),
      if (_sched == MedFreq.everyNDays)
        AdField(
          label: tr('Kaç günde bir?'),
          info: tr('Gün aşırı = 2. Başlangıç gününden itibaren sayılır.'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _num(_everyN, '2', width: 70),
              const SizedBox(height: 10),
              _timesEditor(),
            ],
          ),
        ),
      if (_sched == MedFreq.weekly)
        AdField(
          label: tr('Hangi günler?'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    MedChip(
                      label: fmtWeekdayShort(DateTime(2026, 10, 11 + d)), // 12 Eki 2026 = Pzt
                      selected: _weekdays.contains(d),
                      onTap: () => setState(() {
                        _weekdays = {..._weekdays};
                        _weekdays.contains(d) ? _weekdays.remove(d) : _weekdays.add(d);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _timesEditor(),
            ],
          ),
        ),
    ];
  }

  List<Widget> _prnFields() => [
        AdField(
          label: tr('En kısa aralık'),
          info: tr('İsteğe bağlı. Bu süre dolmadan "Verdim"e basarsan uyarırız. Doktorunun '
              'söylediği aralığı gir; Adena değer önermez.'),
          // Dar ekranda (320dp) alt satıra geçer — Row taşıyordu.
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _num(_prnH, tr('sa'), width: 70),
                const SizedBox(width: 6),
                Text(tr('saat')),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _num(_prnM, tr('dk'), width: 70),
                const SizedBox(width: 6),
                Text(tr('dakika')),
              ]),
            ],
          ),
        ),
        AdField(
          label: tr('Günde en fazla'),
          info: tr('İsteğe bağlı. Bugün bu kadar doz verildiyse "Verdim"de uyarırız.'),
          child: Row(children: [_num(_prnMax, '–'), const SizedBox(width: 8), Text(tr('doz'))]),
        ),
      ];

  Widget _courseField() => AdField(
        label: tr('Kür süresi'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                MedChip(
                    label: tr('Süresiz'),
                    selected: _course == _Course.none,
                    onTap: () => setState(() => _course = _Course.none)),
                MedChip(
                    label: tr('Gün sayısı'),
                    selected: _course == _Course.days,
                    onTap: () => setState(() => _course = _Course.days)),
                MedChip(
                    label: tr('Bitiş tarihi'),
                    selected: _course == _Course.date,
                    onTap: () => setState(() {
                          _course = _Course.date;
                          _end ??= _start.add(const Duration(days: 6));
                        })),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MedChip(
                  label: trp('Başlangıç: {d}', {'d': fmtDayMon(_start)}),
                  icon: 'calendar',
                  onTap: () async {
                    final d = await _pickDate(_start);
                    if (d != null) setState(() => _start = d);
                  },
                ),
                if (_course == _Course.days) ...[
                  _num(_days, '7', width: 70),
                  Text(tr('gün')),
                ],
                if (_course == _Course.date && _end != null)
                  MedChip(
                    label: trp('Bitiş: {d}', {'d': fmtDayMon(_end!)}),
                    icon: 'calendar',
                    onTap: () async {
                      final d = await _pickDate(_end!, first: _start);
                      if (d != null) setState(() => _end = d);
                    },
                  ),
              ],
            ),
          ],
        ),
      );

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
                    formatters: [LengthLimitingTextInputFormatter(kMedPlanNameMax)],
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
              label: tr('Tür'),
              child: AdTabs(
                options: {
                  MedKind.scheduled.wire: tr('Düzenli'),
                  MedKind.prn.wire: tr('İhtiyaç halinde'),
                },
                selected: _kind.wire,
                onSelect: (v) => setState(() => _kind = MedKind.fromWire(v)),
              ),
            ),
            if (_kind == MedKind.scheduled) ..._scheduleFields() else ..._prnFields(),
            _courseField(),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AdenaIcon('shieldAlert', size: 14, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        tr('Doz ve aralık bilgisini doktorunun önerisine göre gir; Adena doz önermez.'),
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
                  ),
                ],
              ),
            ),
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
                      label: _ex!.active ? tr('Duraklat') : tr('Devam ettir'),
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
    final others = ref.read(medicationPlansProvider(widget.babyId)).asData?.value ??
        const <MedicationPlan>[];
    final draft = MedPlanDraft(
      name: _name.text.trim(),
      kind: _kind,
      freq: _sched,
      times: _kind == MedKind.prn
          ? const []
          : (_sched == MedFreq.interval ? _times.take(1).toList() : _times),
      intervalHours: _int(_interval),
      everyNDays: _int(_everyN),
      weekdays: _weekdays,
      start: _start,
      end: _resolvedEnd,
      prnMinIntervalMin: _prnMinutes,
      prnMaxPerDay: _int(_prnMax),
    );
    final err = validateMedPlanDraft(
        draft, [for (final p in others) if (p.id != _ex?.id) p.name]);
    if (err != null) {
      showAdError(context, err);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(healthRepositoryProvider);
    final prn = draft.kind == MedKind.prn;
    final interval = !prn && draft.freq == MedFreq.interval;
    final everyN = !prn && draft.freq == MedFreq.everyNDays;
    final weekly = !prn && draft.freq == MedFreq.weekly;
    try {
      if (_isEdit) {
        await repo.updateMedicationPlan(
          _ex!.id,
          name: draft.name,
          dose: _dose.text.trim(),
          times: draft.times,
          kind: draft.kind,
          freq: draft.freq,
          intervalHours: Value(interval ? draft.intervalHours : null),
          everyNDays: Value(everyN ? draft.everyNDays : null),
          weekdays: weekly ? (draft.weekdays.toList()..sort()) : const [],
          startDate: draft.start,
          endDate: Value(draft.end),
          prnMinIntervalMin: Value(prn ? draft.prnMinIntervalMin : null),
          prnMaxPerDay: Value(prn ? draft.prnMaxPerDay : null),
        );
      } else {
        await repo.createMedicationPlan(
          widget.babyId,
          name: draft.name,
          dose: _dose.text.trim(),
          times: draft.times,
          kind: draft.kind,
          freq: draft.freq,
          intervalHours: interval ? draft.intervalHours : null,
          everyNDays: everyN ? draft.everyNDays : null,
          weekdays: weekly ? (draft.weekdays.toList()..sort()) : const [],
          startDate: draft.start,
          endDate: draft.end,
          prnMinIntervalMin: prn ? draft.prnMinIntervalMin : null,
          prnMaxPerDay: prn ? draft.prnMaxPerDay : null,
        );
        // M4/KB-4: ilk plan → kesin alarm izni açıklaması (yalnız Android, tek sefer).
        if (others.isEmpty && !prn && mounted) {
          await ExactAlarmPrompt(
                  onGranted: () =>
                      resyncAfterExactAlarmGranted(ref, babyId: widget.babyId))
              .maybeShow(context);
        }
      }
      ref.invalidate(medicationPlansProvider(widget.babyId));
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Kaydedildi'));
      }
    } on StateError {
      // KB-8: bakıcı planı yazamaz.
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, tr('Bu işlem için ebeveyn/sahip olmalısın'));
      }
    } catch (e) {
      // D28: hata sessiz kalmasın.
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  Future<void> _togglePause() async {
    final p = _ex!;
    try {
      await ref.read(healthRepositoryProvider).updateMedicationPlan(p.id, active: !p.active);
      ref.invalidate(medicationPlansProvider(widget.babyId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e)); // D28
    }
  }

  Future<void> _delete() async {
    final p = _ex!;
    try {
      await ref.read(healthRepositoryProvider).deleteMedicationPlan(p.id);
      // Bildirimler: planlar yenilenince planlayıcı (MedSchedulerSync) iptal eder.
      ref.invalidate(medicationPlansProvider(widget.babyId));
      if (mounted) {
        Navigator.pop(context);
        showAdToast(context, tr('Plan silindi'));
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e)); // D28
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
