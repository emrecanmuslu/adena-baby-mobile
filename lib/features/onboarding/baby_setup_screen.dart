import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
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
  DateTime? _date; // doğmuşsa doğum tarihi, gebelikse tahmini tarih
  bool _saving = false;

  final _dateFmt = DateFormat('d MMMM y', 'tr_TR');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final isBorn = _status == BabyStatus.born;
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
          : tr('Tahmini doğum tarihini seç'));
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
                    ? 'Merhaba${user != null ? ' ${user.displayName}' : ''} 👋'
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

              AdField(
                label: isBorn ? tr('Doğum tarihi') : tr('Tahmini doğum tarihi'),
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _date != null ? _dateFmt.format(_date!) : tr('Tarih seç'),
                            style: TextStyle(
                              color: _date != null ? null : AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        AdenaIcon('calendar', size: 19, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),

              AdField(
                label: tr('Cinsiyet (isteğe bağlı)'),
                child: AdSides(
                  selected: _gender.name,
                  onSelect: (v) => setState(() => _gender = BabyGender.values.byName(v)),
                  items: [
                    (key: 'female', label: tr('Kız'), small: null),
                    (key: 'male', label: tr('Erkek'), small: null),
                    (key: 'unknown', label: tr('Henüz belli değil'), small: null),
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
