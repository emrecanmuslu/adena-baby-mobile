import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/age.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'baby_controller.dart';
import 'premature_section.dart';

/// Doğum geçiş ekranı (design ScrBornFlow): bekleme → takip moduna geçişte
/// doğum tarihi + prematürite onayı, sonra "Takibe başla".
class BornFlowScreen extends ConsumerStatefulWidget {
  const BornFlowScreen({super.key});

  @override
  ConsumerState<BornFlowScreen> createState() => _BornFlowScreenState();
}

class _BornFlowScreenState extends ConsumerState<BornFlowScreen> {
  DateTime _birth = DateTime.now();
  int? _gestWeeks; // prematüre: doğumdaki gebelik haftası (null = değil)
  int _gestDays = 0; // gebelik haftası üstüne gün (0..6)
  bool _gestTouched = false; // kullanıcı prematüre alanını elle değiştirdi mi?
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // İlk açılışta (varsayılan doğum tarihi = bugün) TDT'den ön-doldur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_autoDerive);
    });
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Tahmini doğum tarihi (TDT) varsa, seçili doğum tarihinden gebelik yaşını
  /// otomatik türetir (kullanıcı elle dokunmadıysa). Zamanında doğum → kapalı.
  void _autoDerive() {
    if (_gestTouched) return;
    final baby = ref.read(activeBabyProvider);
    final due = baby?.dueDate;
    if (due == null) return; // doğrudan eklenen / TDT yok → elle aç
    final g = gestationalAgeFromDue(_birth, due);
    _gestWeeks = g?.weeks;
    _gestDays = g?.days ?? 0;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      helpText: tr('Doğum tarihi'),
    );
    if (d != null) {
      setState(() {
        _birth = d;
        _autoDerive(); // doğum tarihi değişince prematüreyi yeniden türet
      });
    }
  }

  Future<void> _start() async {
    final baby = ref.read(activeBabyProvider);
    if (baby == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(babyControllerProvider.notifier).updateBaby(baby.id, {
        'status': 'born',
        'birth_date': _iso(_birth),
        'gestational_age_weeks': _gestWeeks,
        'gestational_age_days': _gestWeeks == null ? 0 : _gestDays,
      });
      if (!mounted) return;
      // Bu ekran zaten "Tebrikler!" tebrik ekranı — ayrıca toast göstermek gereksiz.
      context.go('/home');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, tr('Geçiş başarısız'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 🎉 amblem
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFFFE0D2), Color(0xFFFFB59E)],
                        ),
                        boxShadow: [
                          BoxShadow(
                              color: Color(0x40E2553F),
                              blurRadius: 36,
                              offset: Offset(0, 16)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text('🎉', style: TextStyle(fontSize: 46)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text(tr('Tebrikler!'),
                        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 9),
                  Center(
                    child: Text(
                      tr('Bekleme modundan takip moduna geçiyoruz. '
                      'Önce doğum tarihini onaylayalım.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Onay kartı
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppColors.softShadow,
                    ),
                    child: Column(
                      children: [
                        _row(
                          icon: 'calendar',
                          color: AppColors.doctor,
                          bg: AppColors.doctorBg,
                          title: tr('Doğum tarihi'),
                          subtitle: fmtDayMonthYear(_birth),
                          trailing: AdenaIcon('edit', size: 18, color: AppColors.muted),
                          onTap: _pickDate,
                          divider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Prematüre girişi — TDT'den otomatik ön-dolar, düzenlenebilir.
                  PrematureSection(
                    weeks: _gestWeeks,
                    days: _gestDays,
                    onChanged: (w, d) => setState(() {
                      _gestWeeks = w;
                      _gestDays = d;
                      _gestTouched = true;
                    }),
                  ),

                  const SizedBox(height: 4),
                  _saving
                      ? FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.coral,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white)),
                        )
                      : AdSaveButton(
                          label: tr('Takibe başla'), color: AppColors.coral, onTap: _start),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row({
    required String icon,
    required Color color,
    required Color bg,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
    required bool divider,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: AppColors.line, width: 1))
              : null,
        ),
        child: Row(
          children: [
            AdIconChip(icon, color: color, bg: bg, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
