import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/health_repository.dart';
import '../../models/baby.dart';
import 'baby_actions.dart';
import 'baby_controller.dart';

/// Aktif bebeğin bilgilerini düzenle / sil / "doğdu" geçişi.
class BabyEditScreen extends ConsumerStatefulWidget {
  const BabyEditScreen({super.key});

  @override
  ConsumerState<BabyEditScreen> createState() => _BabyEditScreenState();
}

class _BabyEditScreenState extends ConsumerState<BabyEditScreen> {
  late final TextEditingController _name;
  BabyGender _gender = BabyGender.unknown;
  DateTime? _date; // born→birth_date, expecting→due_date
  bool _saving = false;
  bool _init = false;

  final _dateFmt = DateFormat('d MMMM y', 'tr_TR');

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  void _seed(Baby b) {
    if (_init) return;
    _init = true;
    _name.text = b.name;
    _gender = b.gender;
    _date = b.isExpecting ? b.dueDate : b.birthDate;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(Baby b) async {
    final now = DateTime.now();
    final isBorn = !b.isExpecting;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: isBorn ? DateTime(now.year - 5) : now,
      lastDate: isBorn ? now : DateTime(now.year + 1),
      helpText: isBorn ? tr('Doğum tarihi') : tr('Tahmini doğum tarihi'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(Baby b) async {
    if (_name.text.trim().isEmpty) {
      _snack(tr('Adı boş olamaz'));
      return;
    }
    setState(() => _saving = true);
    final fields = <String, dynamic>{
      'name': _name.text.trim(),
      'gender': _gender == BabyGender.unknown ? '' : _gender.name,
      if (_date != null)
        (b.isExpecting ? 'due_date' : 'birth_date'): _iso(_date!),
    };
    try {
      await ref.read(babyControllerProvider.notifier).updateBaby(b.id, fields);
      // Doğum tarihi değiştiyse backend aşı takvimini yeniden ürettir → tazele.
      if (!b.isExpecting && _date != b.birthDate) {
        ref.invalidate(vaccinesProvider(b.id));
      }
      if (mounted) {
        _snack(tr('Kaydedildi'));
        context.pop();
      }
    } catch (e) {
      _snack(apiErrorText(e));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Baby b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(tr('Bebeği sil')),
        content: Text(trp(
            '{name} ve tüm kayıtları kalıcı olarak silinecek. Bu geri alınamaz.',
            {'name': b.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('Vazgeç'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.fever),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(tr('Sil')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(babyControllerProvider.notifier).deleteBaby(b.id);
      ref.read(activeBabyIdProvider.notifier).set(null); // ilk bebeğe düşer
      if (mounted) context.go('/home');
    } catch (e) {
      _snack(apiErrorText(e));
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => showAdToast(context, msg);

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(activeBabyProvider);
    if (baby == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.coral)));
    }
    _seed(baby);
    final isOwner = baby.myRole == 'owner';
    final isBorn = !baby.isExpecting;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Bebek bilgileri')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdField(
              label: tr('Ad'),
              child: AdInput(
                controller: _name,
                hint: tr('ör. Aden'),
                capitalization: TextCapitalization.words,
              ),
            ),
            AdField(
              label: tr('Cinsiyet'),
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
            AdField(
              label: isBorn ? tr('Doğum tarihi') : tr('Tahmini doğum tarihi'),
              child: InkWell(
                onTap: () => _pickDate(baby),
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
            const SizedBox(height: 14),

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
                            strokeWidth: 2.5, color: Colors.white)),
                  )
                : AdSaveButton(
                    label: tr('Kaydet'), color: AppColors.coral, onTap: () => _save(baby)),

            // Gebelik → doğdu geçişi
            if (!isBorn) ...[
              const SizedBox(height: 10),
              AdSaveButton(
                label: tr('🎉  Bebeğim doğdu'),
                color: AppColors.coralDark,
                ghost: true,
                onTap: () => _saving ? null : openBornFlow(context),
              ),
            ],

            // Silme (yalnız sahip)
            if (isOwner) ...[
              const SizedBox(height: 36),
              AdSaveButton(
                label: tr('Bebeği sil'),
                color: AppColors.fever,
                ghost: true,
                onTap: () => _saving ? null : _delete(baby),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
