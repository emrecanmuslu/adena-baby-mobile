import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import 'cycle_kit.dart';
import 'cycle_widgets.dart';

/// Ekran 1 — Doğum sonrası kurulum sihirbazı (3 adım). İlk girişte tek seferlik.
/// Tamamlanınca [onDone] çağrılır; çağıran ayarları invalidate edip panoyu açar.
class CycleSetupView extends ConsumerStatefulWidget {
  final CycleSettings initial;
  final DateTime? babyBirthDate;
  final VoidCallback onDone;
  const CycleSetupView(
      {super.key,
      required this.initial,
      required this.onDone,
      this.babyBirthDate});

  @override
  ConsumerState<CycleSetupView> createState() => _CycleSetupViewState();
}

class _CycleSetupViewState extends ConsumerState<CycleSetupView> {
  int _step = 0;
  late DateTime? _birth;
  Breastfeeding? _bf;
  DateTime? _firstPeriod;
  bool _periodReturned = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _birth = widget.initial.birthDate ?? widget.babyBirthDate;
    _bf = widget.initial.breastfeeding;
    _firstPeriod = widget.initial.firstPeriodDate;
    _periodReturned = widget.initial.periodReturned;
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final next = widget.initial.copyWith(
      birthDate: _birth,
      breastfeeding: _bf ?? Breastfeeding.exclusive,
      firstPeriodDate: _periodReturned ? (_firstPeriod ?? DateTime.now()) : null,
      enabled: true,
    );
    try {
      await ref.read(cycleRepositoryProvider).patchSettings(next.toPatchJson());
      ref.invalidate(cycleSettingsProvider);
      ref.invalidate(cycleEntriesProvider);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
          child: Column(
            children: [
              // header: geri + nokta göstergesi + atla
              Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: _step == 0
                        ? null
                        : GestureDetector(
                            onTap: () => setState(() => _step--),
                            child: Icon(Icons.chevron_left_rounded,
                                color: AppColors.ink, size: 26)),
                  ),
                  const Spacer(),
                  _dots(),
                  const Spacer(),
                  GestureDetector(
                    onTap: _next,
                    child: Text(tr('Atla'),
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('Adet Takvimi · Kurulum').toUpperCase(),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        color: AppColors.roseD)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: switch (_step) {
                  0 => _step1(),
                  1 => _step2(),
                  _ => _step3(),
                },
              ),
              const SizedBox(height: 12),
              Text('🔒 ${tr('Verilerin gizli, yalnızca sana ait')}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _step ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                  color: i == _step ? AppColors.rose : AppColors.line2,
                  borderRadius: BorderRadius.circular(4)),
            ),
        ],
      );

  Widget _saveBtn(String label) =>
      cycCta(context, _saving ? '…' : label, onTap: _saving ? () {} : _next);

  // ── ortak: büyük soru + alt açıklama ──
  Widget _q(String text) => Text(text,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, height: 1.18));

  Widget _qsub(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, height: 1.5, color: AppColors.ink2)),
      );

  // ── Adım 1 — Doğum tarihi ──
  Widget _step1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _q(tr('Bebeğinin doğum tarihi')),
        _qsub(tr('Döngü hesabı için başlangıç noktası — annenin değil, bebeğinin.')),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dateCard(
                value: _birth,
                placeholder: tr('Tarih seç'),
                sub: tr('Bebek profilinden · düzenlenebilir'),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _birth ?? now,
                    firstDate: DateTime(now.year - 3),
                    lastDate: now,
                  );
                  if (picked != null) setState(() => _birth = picked);
                },
              ),
              const SizedBox(height: 14),
              cycNote(context,
                  clay: true,
                  icon: Icons.favorite_rounded,
                  body: tr('Doğumdan sonraki ilk ~6 hafta kanama loşiadır, adet değildir.'),
                  infoTitle: tr('Loşia ve adet farkı'),
                  info: CycleInfo.lochiaVsPeriod),
            ]),
          ),
        ),
        _saveBtn(tr('Devam')),
      ],
    );
  }

  // ── Adım 2 — Emzirme ──
  Widget _step2() {
    final opts = [
      (Breastfeeding.exclusive, '🤱', tr('Sadece anne sütü'), tr('LAM geçerli olabilir')),
      (Breastfeeding.mixed, '🍼', tr('Karışık beslenme'), tr('Anne sütü + mama')),
      (Breastfeeding.none, '🥛', tr('Emzirmiyorum'), tr('Adet daha erken dönebilir')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _q(tr('Emziriyor musun?'))),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AdInfoDot(title: tr('Emzirme ve doğurganlık'), body: CycleInfo.lam),
          ),
        ]),
        _qsub(tr('Emzirme durumu döngü tahminlerini etkiler.')),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final o in opts) ...[
                _optTile(
                  emoji: o.$2,
                  title: o.$3,
                  sub: o.$4,
                  on: _bf == o.$1,
                  onTap: () => setState(() => _bf = o.$1),
                ),
                const SizedBox(height: 11),
              ],
            ]),
          ),
        ),
        _saveBtn(tr('Devam')),
      ],
    );
  }

  // ── Adım 3 — Adet döndü mü? ──
  Widget _step3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _q(tr('Adetin döndü mü?')),
        _qsub(tr('İlk adetin döndüyse tarihini seç — döngü takibi buradan başlar.')),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _optTile(
                emoji: '🌸',
                title: tr('Henüz adet görmedim'),
                sub: tr('Bilgilendirme modu · tahmin yapılmaz'),
                on: !_periodReturned,
                onTap: () => setState(() => _periodReturned = false),
              ),
              const SizedBox(height: 11),
              _optTile(
                emoji: '📅',
                title: tr('İlk adetim geldi'),
                sub: tr('Tarih gir → döngü takibi başlar'),
                on: _periodReturned,
                onTap: () => setState(() => _periodReturned = true),
              ),
              if (_periodReturned) ...[
                const SizedBox(height: 12),
                _dateCard(
                  value: _firstPeriod,
                  placeholder: tr('İlk adet tarihini seç'),
                  sub: tr('dokun → takvimden seç'),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _firstPeriod ?? now,
                      firstDate: _birth ?? DateTime(now.year - 1),
                      lastDate: now,
                      helpText: tr('İlk adet tarihi'),
                    );
                    if (picked != null) setState(() => _firstPeriod = picked);
                  },
                ),
              ],
            ]),
          ),
        ),
        _saveBtn(tr('Tamamla')),
      ],
    );
  }

  // ── v3 tarih kartı ──
  Widget _dateCard({
    required DateTime? value,
    required String placeholder,
    required String sub,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: cycCard(context, child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: AppColors.roseBg, borderRadius: BorderRadius.circular(15)),
            child: Icon(Icons.calendar_today_rounded, size: 22, color: AppColors.roseD),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value == null ? placeholder : fmtDayMonthYear(value),
                  style: cycTitleStyle(size: 19)),
              const SizedBox(height: 1),
              Text(sub,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ]),
          ),
          Icon(Icons.edit_outlined, size: 18, color: AppColors.roseD),
        ])),
      );

  // ── v3 seçenek kartı (emoji kutu + başlık + alt + onay) ──
  Widget _optTile({
    required String emoji,
    required String title,
    required String sub,
    required bool on,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: on ? AppColors.roseBg : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? AppColors.rose : AppColors.line, width: 1.8),
            boxShadow: on ? null : AppColors.softShadow,
          ),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: on ? Colors.white.withValues(alpha: 0.6) : AppColors.roseBg,
                  borderRadius: BorderRadius.circular(14)),
              child: Text(emoji, style: const TextStyle(fontSize: 23)),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 1),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
              ]),
            ),
            Icon(on ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                size: on ? 24 : 22, color: on ? AppColors.rose : AppColors.muted2),
          ]),
        ),
      );
}
