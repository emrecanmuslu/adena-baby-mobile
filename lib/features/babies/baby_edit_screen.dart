import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/baby_repository.dart';
import '../../data/cycle_repository.dart';
import '../../data/health_repository.dart';
import '../../models/baby.dart';
import '../../models/cycle.dart';
import 'baby_actions.dart';
import 'baby_controller.dart';
import 'baby_photo.dart';
import 'premature_section.dart';

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
  int? _gestWeeks; // prematüre: doğumdaki gebelik haftası (null = değil)
  int _gestDays = 0; // gebelik haftası üstüne gün (0..6)
  bool _saving = false;
  bool _init = false;
  bool _photoBusy = false;

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
    _gestWeeks = b.gestationalWeeks;
    _gestDays = b.gestationalDays;
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
    // DateTime(now.year + 1) "gelecek yılın 1 Ocak'ı" demekti — TDT sonraki
    // yıla sarkınca initialDate > lastDate assert'iyle seçici hiç açılmıyordu.
    final first = isBorn ? DateTime(now.year - 5) : now;
    final last = isBorn ? now : DateTime(now.year + 1, now.month, now.day);
    var init = _date ?? now;
    if (init.isAfter(last)) init = last;
    if (init.isBefore(first)) init = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
      helpText: isBorn ? tr('Doğum tarihi') : tr('Tahmini doğum tarihi'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickPhoto(Baby b, ImageSource source) async {
    try {
      final x = await ImagePicker()
          .pickImage(source: source, maxWidth: 1200, imageQuality: 85);
      if (x == null) return;
      setState(() => _photoBusy = true);
      await ref.read(babyRepositoryProvider).updatePhoto(b.id, x.path);
      ref.invalidate(babyControllerProvider);
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  /// Kamera / galeri kaynağı seçtiren küçük sheet (anı fotoğrafıyla aynı desen).
  void _choosePhotoSource(Baby b) {
    showModalBottomSheet(
      context: context,
      shape: adSheetShape,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: adGrabHandle()),
            ListTile(
              leading: const AdenaIcon('camera', size: 22, color: AppColors.coralDd),
              title: Text(tr('Kamera'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(b, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const AdenaIcon('charts', size: 22, color: AppColors.pump),
              title: Text(tr('Galeri'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(b, ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
      // Prematüre alanları yalnız doğmuş bebekte (null → temizle).
      if (!b.isExpecting) ...{
        'gestational_age_weeks': _gestWeeks,
        'gestational_age_days': _gestWeeks == null ? 0 : _gestDays,
      },
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
      // Cycle temizliği: silinen bebek adet modülüne bağlıysa bağ kopar; bir
      // GEBELİK bebeği silindiyse mod da gebelikte takılı kalmasın (kayıp
      // akışı dışı silme = kaçış kapısı; adet çapasına dokunmayız).
      try {
        final repo = ref.read(cycleRepositoryProvider);
        final cs = await repo.getSettings();
        final wasLinked = cs.babyId == b.id;
        final orphanPregnant =
            b.isExpecting && cs.lifecycleMode == CycleLifecycleMode.pregnant;
        if (wasLinked || orphanPregnant) {
          await repo.patchSettings({
            if (wasLinked) 'baby': null,
            if (orphanPregnant) ...{
              'lifecycle_mode': CycleLifecycleMode.tracking.name,
              'predictions_hidden': false,
            },
          });
          ref.invalidate(cycleSettingsProvider);
        }
      } catch (_) {}
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
            Center(
              child: GestureDetector(
                onTap: _photoBusy ? null : () => _choosePhotoSource(baby),
                child: Stack(
                  children: [
                    BabyAvatar(
                      photo: baby.photo,
                      size: 92,
                      placeholder: Container(
                        width: 92,
                        height: 92,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFFE0D2), Color(0xFFFFC1AC)],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: baby.isExpecting
                            ? const Text('🤰', style: TextStyle(fontSize: 34))
                            : AdenaIcon('baby', size: 38, color: Colors.white, sw: 1.8),
                      ),
                    ),
                    if (_photoBusy)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: Colors.black26),
                          child: const Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white)),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.coral,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                        ),
                        child: const AdenaIcon('camera', size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
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
                          _date != null ? fmtDayMonthYear(_date!) : tr('Tarih seç'),
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

            // Prematüre girişi yalnız doğmuş bebekte (bekleme modunda gizli).
            if (isBorn)
              PrematureSection(
                weeks: _gestWeeks,
                days: _gestDays,
                onChanged: (w, d) => setState(() {
                  _gestWeeks = w;
                  _gestDays = d;
                }),
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
