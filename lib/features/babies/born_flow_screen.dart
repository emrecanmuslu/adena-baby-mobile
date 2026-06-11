import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'baby_controller.dart';

/// Doğum geçiş ekranı (design ScrBornFlow): bekleme → takip moduna geçişte
/// doğum tarihi + prematürite onayı, sonra "Takibe başla".
class BornFlowScreen extends ConsumerStatefulWidget {
  const BornFlowScreen({super.key});

  @override
  ConsumerState<BornFlowScreen> createState() => _BornFlowScreenState();
}

class _BornFlowScreenState extends ConsumerState<BornFlowScreen> {
  DateTime _birth = DateTime.now();
  int _weeks = 40; // doğum haftası (≥37 zamanında)
  bool _saving = false;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      helpText: tr('Doğum tarihi'),
    );
    if (d != null) setState(() => _birth = d);
  }

  Future<void> _pickWeeks() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: false,
      shape: adSheetShape,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: adGrabHandle()),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 4),
                child: Text(tr('Doğum haftası'),
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 12),
                child: Text(tr('37 haftadan önce doğduysa düzeltilmiş yaş kullanılır.'),
                    style: TextStyle(
                        color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var w = 24; w <= 42; w++)
                    GestureDetector(
                      onTap: () => Navigator.pop(context, w),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: w == _weeks
                              ? AppColors.feedBg
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: w == _weeks ? AppColors.coral : AppColors.line,
                              width: 1.5),
                        ),
                        child: Text('$w',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: w == _weeks ? AppColors.coralDd : null)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _weeks = picked);
  }

  Future<void> _start() async {
    final baby = ref.read(activeBabyProvider);
    if (baby == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(babyControllerProvider.notifier).updateBaby(baby.id, {
        'status': 'born',
        'birth_date': _iso(_birth),
        'gestational_age_at_birth_weeks': _weeks,
      });
      if (!mounted) return;
      showAdToast(context, tr('Tebrikler! 🎉'));
      context.go('/home');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showAdToast(context, tr('Geçiş başarısız'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _weeks >= 37;
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
                          subtitle: DateFormat('d MMMM y', 'tr_TR').format(_birth),
                          trailing: AdenaIcon('edit', size: 18, color: AppColors.muted),
                          onTap: _pickDate,
                          divider: true,
                        ),
                        _row(
                          icon: 'check',
                          color: AppColors.coralDd,
                          bg: AppColors.feedBg,
                          title: term ? tr('Zamanında doğum') : tr('Prematüre doğum'),
                          subtitle: term
                              ? trp('{w} hafta · düzeltme gerekmez', {'w': _weeks})
                              : trp('{w} hafta · düzeltilmiş yaş kullanılır', {'w': _weeks}),
                          trailing:
                              AdenaIcon('chevD', size: 18, color: AppColors.muted),
                          onTap: _pickWeeks,
                          divider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
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
