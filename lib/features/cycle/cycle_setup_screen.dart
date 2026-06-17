import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _step == 0
            ? null
            : IconButton(
                icon: Icon(Icons.chevron_left, color: AppColors.ink),
                onPressed: () => setState(() => _step--)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              Text(tr('Adet Takvimi Kurulumu').toUpperCase(),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      color: AppColors.roseD)),
              const SizedBox(height: 18),
              Expanded(
                child: switch (_step) {
                  0 => _step1(),
                  1 => _step2(),
                  _ => _step3(),
                },
              ),
              const SizedBox(height: 20),
              _dots(),
              const SizedBox(height: 14),
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
              width: i == _step ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                  color: i == _step ? AppColors.rose : AppColors.line2,
                  borderRadius: BorderRadius.circular(4)),
            ),
        ],
      );

  Widget _saveBtn(String label) => _saving
      ? FilledButton(
          onPressed: null,
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.rose,
              minimumSize: const Size.fromHeight(52),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white)),
        )
      : AdSaveButton(label: label, color: AppColors.rose, onTap: _next);

  // ── Adım 1 — Doğum tarihi ──
  Widget _step1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('Bebeğinin doğum tarihi'),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(tr('Döngü hesabı için başlangıç noktası — annenin değil, bebeğinin.'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(16),
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
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppColors.softShadow),
            child: Row(
              children: [
                AdIconChip('calendar', color: AppColors.roseD, bg: AppColors.roseBg, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_birth == null ? tr('Tarih seç') : fmtDayMonthYear(_birth!),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w900)),
                      Text(tr('Bebek profilinden · düzenlenebilir'),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ],
                  ),
                ),
                Icon(Icons.edit, size: 17, color: AppColors.roseD),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _infoCard(tr('Loşia ve adet farkı'), CycleInfo.lochiaVsPeriod),
        const Spacer(),
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
        Row(
          children: [
            Flexible(
              child: Text(tr('Emziriyor musun?'),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 6),
            AdInfoDot(title: tr('Emzirme ve doğurganlık'), body: CycleInfo.lam),
          ],
        ),
        const SizedBox(height: 4),
        Text(tr('Emzirme durumu döngü tahminlerini etkiler'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
        const SizedBox(height: 18),
        for (final o in opts) ...[
          _optTile(
            emoji: o.$2,
            title: o.$3,
            sub: o.$4,
            on: _bf == o.$1,
            onTap: () => setState(() => _bf = o.$1),
          ),
          const SizedBox(height: 10),
        ],
        const Spacer(),
        _saveBtn(tr('Devam')),
      ],
    );
  }

  // ── Adım 3 — Adet döndü mü? ──
  Widget _step3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('Adet döndü mü?'),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 18),
        _optTile(
          emoji: '🌸',
          title: tr('Henüz adet görmedim'),
          sub: tr('Bilgilendirme modu · tahmin yapılmaz'),
          on: !_periodReturned,
          onTap: () => setState(() => _periodReturned = false),
        ),
        const SizedBox(height: 10),
        _optTile(
          emoji: '📅',
          title: tr('İlk adetim geldi'),
          sub: tr('Tarih gir → döngü takibi başlar'),
          on: _periodReturned,
          onTap: () => setState(() => _periodReturned = true),
        ),
        if (_periodReturned) ...[
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(14),
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                  color: AppColors.roseBg,
                  borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 15, color: AppColors.roseD),
                  const SizedBox(width: 8),
                  Text(
                      _firstPeriod == null
                          ? tr('İlk adet tarihini seç')
                          : fmtDayMonthYear(_firstPeriod!),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.roseD)),
                ],
              ),
            ),
          ),
        ],
        const Spacer(),
        _saveBtn(tr('Tamamla')),
      ],
    );
  }

  Widget _infoCard(String title, String body) => Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
        decoration: BoxDecoration(
            color: AppColors.roseBg, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.roseD)),
                const SizedBox(width: 6),
                AdInfoDot(title: title, body: body),
              ],
            ),
            const SizedBox(height: 4),
            Text(body,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.ink2)),
          ],
        ),
      );

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
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: on ? AppColors.rose : AppColors.line, width: 2),
            boxShadow: on ? null : AppColors.softShadow,
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w800)),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ),
              Icon(on ? Icons.check_circle : Icons.chevron_right,
                  size: on ? 22 : 20,
                  color: on ? AppColors.rose : AppColors.muted2),
            ],
          ),
        ),
      );
}
