import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/baby.dart';
import '../auth/auth_controller.dart';
import '../babies/baby_controller.dart';
import '../babies/baby_switcher.dart';

/// Bebek kurulumu: "Bebek doğdu mu?" → ad/tarih → oluştur.
/// [onboarding] true → ilk kurulum (router yönlendirir); false → ek bebek (geri döner).
class BabySetupScreen extends ConsumerStatefulWidget {
  final bool onboarding;
  const BabySetupScreen({super.key, this.onboarding = true});

  @override
  ConsumerState<BabySetupScreen> createState() => _BabySetupScreenState();
}

class _BabySetupScreenState extends ConsumerState<BabySetupScreen> {
  final _name = TextEditingController();
  BabyStatus _status = BabyStatus.born;
  BabyGender _gender = BabyGender.unknown;
  DateTime? _date; // doğmuşsa doğum tarihi, gebelikse tahmini doğum tarihi (TDT)
  bool _useLmp = false; // gebelik: TDT yerine SAT'tan hesapla
  DateTime? _lmp; // son adet tarihi (SAT) — TDT bundan üretilir
  bool _saving = false;

  /// Gebelik = 40 hafta. Naegele kuralı: TDT = SAT + 280 gün.
  static const int _gestationDays = 280;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final isBorn = _status == BabyStatus.born;
    // Gebelik + SAT modu: son adet tarihini seç, TDT'yi otomatik hesapla.
    if (!isBorn && _useLmp) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _lmp ?? now.subtract(const Duration(days: 56)),
        firstDate: now.subtract(const Duration(days: 300)),
        lastDate: now,
        helpText: tr('Son adet tarihi (SAT)'),
      );
      if (picked != null) {
        setState(() {
          _lmp = picked;
          _date = picked.add(const Duration(days: _gestationDays)); // TDT
        });
      }
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: isBorn ? DateTime(now.year - 5) : now,
      lastDate: isBorn ? now : DateTime(now.year + 1),
      helpText: isBorn ? tr('Doğum tarihi') : tr('Tahmini doğum tarihi'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack(tr('Bebeğin adını gir'));
      return;
    }
    if (_date == null) {
      _snack(_status == BabyStatus.born
          ? tr('Doğum tarihini seç')
          : (_useLmp ? tr('Son adet tarihini seç') : tr('Tahmini doğum tarihini seç')));
      return;
    }
    setState(() => _saving = true);
    try {
      final baby = await ref.read(babyControllerProvider.notifier).create(
            name: name,
            status: _status,
            gender: _gender,
            birthDate: _status == BabyStatus.born ? _date : null,
            dueDate: _status == BabyStatus.expecting ? _date : null,
          );
      ref.read(activeBabyIdProvider.notifier).set(baby.id);
      // Onboarding'de router redirect ana sayfaya götürür; ek bebekte elle dön.
      if (!widget.onboarding && mounted) context.go('/home');
    } catch (e) {
      _snack(apiErrorText(e));
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => showAdToast(context, msg);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final isBorn = _status == BabyStatus.born;

    final onboarding = widget.onboarding;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: onboarding ? null : Text(tr('Bebek ekle')),
        actions: [
          if (onboarding)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => ref.read(authControllerProvider.notifier).logout(),
              child: Text(tr('Çıkış')),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                onboarding
                    ? trp('Merhaba{name} 👋',
                        {'name': user != null ? ' ${user.displayName}' : ''})
                    : tr('Yeni bebek'),
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                onboarding
                    ? tr('Profili birlikte oluşturalım.')
                    : tr('Bilgileri gir, ekleyelim.'),
                style: TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 22),

              // Doğdu mu? seçimi
              AdField(
                label: tr('Bebek doğdu mu?'),
                child: AdSides(
                  selected: isBorn ? 'born' : 'expecting',
                  onSelect: (v) => setState(() {
                    _status = v == 'born' ? BabyStatus.born : BabyStatus.expecting;
                    _date = null;
                  }),
                  items: [
                    (key: 'born', label: tr('🎉 Doğdu'), small: tr('Hemen takip')),
                    (key: 'expecting', label: tr('🤰 Bekliyoruz'), small: tr('Bekleme odası')),
                  ],
                ),
              ),

              AdField(
                label: isBorn ? tr('Bebeğin adı') : tr('İsim (varsa)'),
                child: AdInput(
                  controller: _name,
                  hint: tr('ör. Aden'),
                  capitalization: TextCapitalization.words,
                ),
              ),

              // Gebelikte: TDT'yi doğrudan gir ya da SAT'tan hesaplat.
              if (!isBorn)
                AdField(
                  label: tr('Tarihi nasıl gireceksin?'),
                  info: tr('Tahmini doğum tarihini biliyorsan onu seç. Bilmiyorsan '
                      'son adet tarihini (SAT) seç — doğum tarihini biz hesaplarız '
                      '(SAT + 40 hafta). Doktorunun verdiği tarih önceliklidir.'),
                  child: AdTabs(
                    options: {
                      'due': tr('Doğum tarihi'),
                      'lmp': tr('Son adet (SAT)'),
                    },
                    selected: _useLmp ? 'lmp' : 'due',
                    onSelect: (v) => setState(() {
                      _useLmp = v == 'lmp';
                      _date = null;
                      _lmp = null;
                    }),
                  ),
                ),

              AdField(
                label: isBorn
                    ? tr('Doğum tarihi')
                    : (_useLmp ? tr('Son adet tarihi (SAT)') : tr('Tahmini doğum tarihi')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.line, width: 1.5),
                        ),
                        child: Builder(builder: (_) {
                          final shown = _useLmp ? _lmp : _date;
                          return Row(
                            children: [
                              Expanded(
                                child: Text(
                                  shown != null ? fmtDayMonthYear(shown) : tr('Tarih seç'),
                                  style: TextStyle(
                                    color: shown != null ? null : AppColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              AdenaIcon('calendar', size: 19, color: AppColors.muted),
                            ],
                          );
                        }),
                      ),
                    ),
                    // SAT'tan hesaplanan TDT özeti.
                    if (!isBorn && _useLmp && _lmp != null && _date != null) ...[
                      const SizedBox(height: 8),
                      _DueFromLmp(due: _date!, lmp: _lmp!),
                    ],
                  ],
                ),
              ),

              if (!isBorn) const SizedBox(height: 2),
              AdField(
                label: tr('Cinsiyet (isteğe bağlı)'),
                child: AdSides(
                  selected: _gender.name,
                  onSelect: (v) => setState(() => _gender = BabyGender.values.byName(v)),
                  items: [
                    (key: 'female', label: tr('Kız'), small: null),
                    (key: 'male', label: tr('Erkek'), small: null),
                    (key: 'unknown', label: tr('Belirsiz'), small: null),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              _saving
                  ? FilledButton(
                      onPressed: null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.coral,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      ),
                    )
                  : AdSaveButton(label: tr('Devam et'), color: AppColors.coral, onTap: _save),

              // Davetli ebeveyn/bakıcı: yeni bebek yaratmak yerine kodla katıl.
              if (onboarding) ...[
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.line, thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(tr('veya'),
                          style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5)),
                    ),
                    Expanded(child: Divider(color: AppColors.line, thickness: 1)),
                  ],
                ),
                const SizedBox(height: 16),
                AdSaveButton(
                  label: tr('Davet kodum var'),
                  color: AppColors.coralDark,
                  ghost: true,
                  onTap: () => _saving ? null : showAcceptInviteDialog(context, ref),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('Eşin veya bakıcın bebeği zaten eklediyse, paylaştığı kodla katıl.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// SAT'tan hesaplanan tahmini doğum tarihi + güncel gebelik haftası özeti.
class _DueFromLmp extends StatelessWidget {
  final DateTime due;
  final DateTime lmp;
  const _DueFromLmp({required this.due, required this.lmp});

  @override
  Widget build(BuildContext context) {
    final days = DateTime.now().difference(lmp).inDays;
    final week = (days ~/ 7).clamp(0, 42);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.feedBg,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Text('🤰', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              trp('Tahmini doğum: {due} · ~{w}. hafta', {'due': fmtDayMonthYear(due), 'w': week}),
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.coralDd),
            ),
          ),
        ],
      ),
    );
  }
}
