
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/baby.dart';
import '../../models/cycle.dart';
import '../babies/baby_controller.dart';
import '../babies/premature_section.dart';

/// Yeni bebeği oluşturur, aktif yapar ve (gebelikse) Adet Takvimi'ni eşitler.
/// Onboarding profil formu ve "Bebek ekle" ekranı ortak kullanır.
Future<Baby> createBaby(
  WidgetRef ref, {
  required String name,
  required BabyStatus status,
  required BabyGender gender,
  required DateTime date,
  DateTime? lmp,
  int? gestWeeks,
  int gestDays = 0,
}) async {
  final born = status == BabyStatus.born;
  final baby = await ref.read(babyControllerProvider.notifier).create(
        name: name,
        status: status,
        gender: gender,
        birthDate: born ? date : null,
        dueDate: born ? null : date,
        gestationalWeeks: born ? gestWeeks : null,
        gestationalDays: born ? gestDays : 0,
      );
  ref.read(activeBabyIdProvider.notifier).set(baby.id);
  // İleri senkron: Adet Takvimi kuruluysa ve gebelik (bekleme) bebeği
  // eklendiyse yaşam-döngüsü de gebeliğe geçer — aksi halde bebek tarafı
  // gebelik gösterirken adet ekranı takip/TTC'de kalırdı (çift durum).
  // SAT girildiyse çapa da güncellenir (gebelik özeti LMP'den hesaplanır).
  if (!born) {
    try {
      final repo = ref.read(cycleRepositoryProvider);
      final cs = await repo.getSettings();
      if (cs.breastfeeding != null &&
          cs.lifecycleMode != CycleLifecycleMode.pregnant) {
        await repo.patchSettings({
          'lifecycle_mode': CycleLifecycleMode.pregnant.name,
          'predictions_hidden': false,
          'baby': baby.id,
          if (lmp != null)
            'first_period_date': '${lmp.year.toString().padLeft(4, '0')}-'
                '${lmp.month.toString().padLeft(2, '0')}-'
                '${lmp.day.toString().padLeft(2, '0')}',
        });
      }
    } catch (_) {}
  }
  return baby;
}

/// "Bebek ekle" formu (ek bebek): durum anahtarı + ad/tarih → oluştur, ana
/// sayfaya dön. İlk kurulum onboarding'de [BabyProfileScreen] ile yapılır.
class BabySetupScreen extends ConsumerStatefulWidget {
  const BabySetupScreen({super.key});

  @override
  ConsumerState<BabySetupScreen> createState() => _BabySetupScreenState();
}

class _BabySetupScreenState extends ConsumerState<BabySetupScreen> {
  final _name = TextEditingController();
  BabyStatus _status = BabyStatus.born;

  @override
  void initState() {
    super.initState();
    // Ad yazıldıkça rebuild → PopScope.canPop (_dirty) güncel kalsın.
    _name.addListener(() {
      if (mounted) setState(() {});
    });
  }
  BabyGender _gender = BabyGender.unknown;
  DateTime? _date; // doğmuşsa doğum tarihi, gebelikse tahmini doğum tarihi (TDT)
  bool _useLmp = false; // gebelik: TDT yerine SAT'tan hesapla
  DateTime? _lmp; // son adet tarihi (SAT) — TDT bundan üretilir
  int? _gestWeeks; // prematüre: doğumdaki gebelik haftası (null = değil)
  int _gestDays = 0; // gebelik haftası üstüne gün (0..6)
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
        // TDT = SAT + 280: daha eski SAT geçmişte bir TDT üretirdi.
        firstDate: now.subtract(const Duration(days: _gestationDays)),
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
    // Gebelik: tahmini doğum tarihi bugünden ~42 haftaya kadar olabilir. Eskiden
    // üst sınır "gelecek yılın 1 Ocak'ı"ydı → sonbaharda gebeliğin başındaki
    // kullanıcı TDT'sini HİÇ seçemiyordu. Seçici bugünden değil makul bir
    // varsayılandan açılır — bugünde açılınca dokunmadan "Tamam" diyen kullanıcı
    // "40. hafta / 0 gün kaldı" ile başlıyordu.
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? (isBorn ? now : now.add(const Duration(days: 120))),
      firstDate: isBorn ? DateTime(now.year - 5) : now,
      lastDate: isBorn ? now : now.add(const Duration(days: 300)),
      helpText: isBorn ? tr('Doğum tarihi') : tr('Tahmini doğum tarihi'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    var name = _name.text.trim();
    if (name.isEmpty) {
      // Doğmuş bebekte ad zorunlu; bekleme modunda ad henüz bilinmeyebilir
      // ("İsim (varsa)") → varsayılanla devam et.
      if (_status == BabyStatus.born) {
        _snack(tr('Bebeğin adını gir'));
        return;
      }
      name = tr('Bebeğim');
    }
    if (_date == null) {
      _snack(_status == BabyStatus.born
          ? tr('Doğum tarihini seç')
          : (_useLmp ? tr('Son adet tarihini seç') : tr('Tahmini doğum tarihini seç')));
      return;
    }
    setState(() => _saving = true);
    try {
      await createBaby(
        ref,
        name: name,
        status: _status,
        gender: _gender,
        date: _date!,
        lmp: _useLmp ? _lmp : null,
        gestWeeks: _gestWeeks,
        gestDays: _gestDays,
      );
      if (mounted) context.go('/home');
    } catch (e) {
      _snack(apiErrorText(e));
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) => showAdToast(context, msg);

  /// Kullanıcı forma veri girdi mi? (BACK'te onaysız veri kaybını önlemek için.)
  bool get _dirty =>
      _name.text.trim().isNotEmpty || _date != null || _gestWeeks != null;

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(tr('Formdan çıkılsın mı?')),
        content: Text(tr('Girdiğin bilgiler kaydedilmeden silinecek.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(tr('Vazgeç')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(tr('Çık'),
                style: const TextStyle(
                    color: AppColors.fever, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (leave == true && mounted && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isBorn = _status == BabyStatus.born;
    // Dolu form BACK ile onaysız atılmasın (yaşam-döngüsü testi gözlemi):
    // veri girildiyse önce onay diyaloğu göster.
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Bebek ekle')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Yeni bebek'),
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Bilgileri gir, ekleyelim.'),
                style: TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              const SizedBox(height: 22),

              AdField(
                  label: tr('Bebek doğdu mu?'),
                  child: AdSides(
                    selected: isBorn ? 'born' : 'expecting',
                    onSelect: (v) => setState(() {
                      _status = v == 'born' ? BabyStatus.born : BabyStatus.expecting;
                      _date = null;
                      // Bekleme moduna geçince prematüre girişini temizle.
                      if (_status == BabyStatus.expecting) {
                        _gestWeeks = null;
                        _gestDays = 0;
                      }
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
                      'due': tr('Tahmini doğum tarihi'),
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
                  : AdSaveButton(
                      label: tr('Devam et'),
                      color: AppColors.coral,
                      onTap: _save),
            ],
          ),
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
