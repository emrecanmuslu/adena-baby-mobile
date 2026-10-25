import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/age.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/glass.dart';
import '../../core/i18n.dart';
import '../../core/onboarding_paywall.dart';
import '../../core/theme.dart';
import '../../data/baby_repository.dart';
import '../../models/baby.dart';
import 'baby_setup_screen.dart';
import 'onboarding_draft.dart';
import 'onboarding_kit.dart';

/// Onboarding 2. adımı — bebek profili (doğdu, tasarım [3]) ya da gebelik
/// profili (hamileyim, tasarım [4]). Kaydedince router ana sayfaya geçer;
/// arada paywall, izin ya da tur YOK.
class BabyProfileScreen extends ConsumerStatefulWidget {
  final BabyStatus status;
  const BabyProfileScreen({super.key, required this.status});

  @override
  ConsumerState<BabyProfileScreen> createState() => _BabyProfileScreenState();
}

class _BabyProfileScreenState extends ConsumerState<BabyProfileScreen> {
  final _name = TextEditingController();
  BabyGender? _gender;
  DateTime? _date; // doğum tarihi | TDT
  bool _useLmp = false; // gebelik: TDT yerine son adet tarihinden hesapla
  DateTime? _lmp;
  bool _premature = false;
  int _gestWeeks = 34;
  int _gestDays = 0;
  String? _photo; // seçilen yerel dosya — bebek oluşunca yüklenir
  bool _nameError = false;
  bool _saving = false;

  bool get _born => widget.status == BabyStatus.born;

  /// Gebelik: 40 hafta. Naegele kuralı: TDT = SAT + 280 gün.
  static const _gestationDays = 280;

  String get _route =>
      _born ? '/onboarding/baby/born' : '/onboarding/baby/expecting';

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_nameError && _name.text.trim().isNotEmpty) {
        setState(() => _nameError = false);
      }
      _persist();
    });
    _restore();
  }

  /// Her değişiklikte durumu yenile + taslağa yaz (uygulama kapanırsa geri gelsin).
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _persist();
  }

  bool _restored = false;

  Future<void> _restore() async {
    final d = await OnboardingDraft.read();
    _restored = true;
    if (d == null || d.route != _route || !mounted) return;
    final f = d.fields;
    _name.text = (f['name'] as String?) ?? '';
    setState(() {
      _date = OnboardingDraft.parseDay(f['date']);
      _useLmp = f['useLmp'] == true;
      _lmp = OnboardingDraft.parseDay(f['lmp']);
      _premature = f['premature'] == true;
      _gestWeeks = (f['gestWeeks'] as num?)?.toInt() ?? _gestWeeks;
      _gestDays = (f['gestDays'] as num?)?.toInt() ?? _gestDays;
      final g = f['gender'] as String?;
      _gender = g == null ? null : BabyGender.values.asNameMap()[g];
      final ph = f['photo'] as String?;
      _photo = ph != null && File(ph).existsSync() ? ph : null;
    });
  }

  void _persist() {
    // Taslak okunmadan yazma — boş form kayıtlı taslağı ezmesin.
    if (!_restored || _saving) return;
    OnboardingDraft.saveFields(_route, {
      'name': _name.text,
      'date': OnboardingDraft.day(_date),
      'useLmp': _useLmp,
      'lmp': OnboardingDraft.day(_lmp),
      'premature': _premature,
      'gestWeeks': _gestWeeks,
      'gestDays': _gestDays,
      'gender': _gender?.name,
      'photo': _photo,
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  OnbAccent get _accent =>
      OnbAccent.of(context, _born ? OnbBranch.baby : OnbBranch.preg);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final DateTime? picked;
    if (_born) {
      picked = await showOnbDatePicker(
        context,
        title: tr('Doğum tarihi'),
        initial: _date ?? today,
        first: DateTime(now.year - 5),
        last: today,
        accent: _accent,
      );
    } else if (_useLmp) {
      picked = await showOnbDatePicker(
        context,
        title: tr('Son adet tarihinin ilk günü'),
        initial: _lmp ?? today.subtract(const Duration(days: 112)),
        // TDT = SAT + 280: daha eski SAT geçmişte bir TDT (negatif geri
        // sayım) üretirdi.
        first: today.subtract(const Duration(days: _gestationDays)),
        last: today,
        accent: _accent,
      );
    } else {
      // Bugünden değil makul bir varsayılandan açılır — bugünde açılınca
      // dokunmadan "Seç" diyen kullanıcı "40. hafta" ile başlıyordu.
      picked = await showOnbDatePicker(
        context,
        title: tr('Tahmini doğum tarihi'),
        initial: _date ?? today.add(const Duration(days: 120)),
        first: today,
        last: today.add(const Duration(days: 300)),
        accent: _accent,
      );
    }
    if (picked == null || !mounted) return;
    setState(() {
      if (!_born && _useLmp) {
        _lmp = picked;
        _date = picked!.add(const Duration(days: _gestationDays));
      } else {
        _date = picked;
      }
    });
  }

  Future<void> _pickPhoto() async {
    final source = await showOnbSheet<ImageSource>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnbTextButton(
            label: tr('Fotoğraf çek'),
            color: AppColors.ink,
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          OnbTextButton(
            label: tr('Galeriden seç'),
            color: AppColors.ink,
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null) return;
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (x != null && mounted) setState(() => _photo = x.path);
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<void> _pickGestation() async {
    var w = _gestWeeks, d = _gestDays;
    final ok = await showOnbSheet<bool>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Doğumdaki gebelik haftası'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: w - 22,
                    ),
                    onSelectedItemChanged: (i) => w = 22 + i,
                    children: [
                      for (var i = 22; i <= 41; i++)
                        Center(
                          child: Text(
                            trp('{n} hf', {'n': i}),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    itemExtent: 40,
                    scrollController: FixedExtentScrollController(
                      initialItem: d,
                    ),
                    onSelectedItemChanged: (i) => d = i,
                    children: [
                      for (var i = 0; i <= 6; i++)
                        Center(
                          child: Text(
                            trp('{n} gün', {'n': i}),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OnbPrimaryButton(
            label: tr('Seç'),
            accent: _accent,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _gestWeeks = w;
        _gestDays = d;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    var name = _name.text.trim();
    if (name.isEmpty) {
      if (_born) {
        setState(() => _nameError = true);
        return;
      }
      // Bekleme modunda ad henüz bilinmeyebilir → varsayılanla devam et.
      name = tr('Bebeğim');
    }
    if (_date == null) {
      showAdToast(
        context,
        _born
            ? tr('Doğum tarihini seç')
            : (_useLmp
                  ? tr('Son adet tarihini seç')
                  : tr('Tahmini doğum tarihini seç')),
      );
      return;
    }
    setState(() => _saving = true);
    // Bebek oluşunca router bu ekranı kaldırır — repo'yu önceden al.
    final repo = ref.read(babyRepositoryProvider);
    final photo = _photo;
    final hadOnboarded = await OnboardingPaywall.onboardedAt() != null;
    try {
      // Premium Karşılama'yı sıraya al (ilk kayıttan sonra / ertesi gün açılır)
      // — bebek OLUŞTURULMADAN yazılır: create() redirect'i tetikler.
      // Taslak da önce silinir: başarıda ekran router ile hemen kalkar.
      // Oluşturma başarısız olursa üçü de geri alınır (catch).
      await OnboardingPaywall.markPending();
      await OnboardingPaywall.markOnboarded();
      await OnboardingDraft.clear();
      final baby = await createBaby(
        ref,
        name: name,
        status: widget.status,
        gender: _gender ?? BabyGender.unknown,
        date: _date!,
        lmp: _useLmp ? _lmp : null,
        gestWeeks: _born && _premature ? _gestWeeks : null,
        gestDays: _born && _premature ? _gestDays : 0,
      );
      if (photo != null) {
        try {
          await repo.updatePhoto(baby.id, photo);
        } catch (_) {
          // Foto sonradan Bebek Profili'nden eklenebilir; kurulumu düşürmesin.
        }
      }
    } catch (e) {
      await OnboardingPaywall.rollbackSetup(hadOnboarded: hadOnboarded);
      if (mounted) {
        // _saving düşünce setState override'ı taslağı yeniden yazar.
        await OnboardingDraft.start(_route);
        setState(() => _saving = false);
        if (mounted) showAdError(context, apiErrorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _accent;
    // Bilerek geri (ok ya da sistem geri tuşu) → karşılamaya dön, taslağı bırak
    // (yeniden açılışta forma atlamasın).
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) OnboardingDraft.clear();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: GlassBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OnbTopBar(accent: a),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 12, bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _born ? _bornFields(a) : _pregFields(a),
                      ),
                    ),
                  ),
                  OnbPrimaryButton(
                    label: _born
                        ? tr('Takibe başla')
                        : tr('Bekleme odasına gir'),
                    accent: a,
                    loading: _saving,
                    onTap: _save,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoButton(OnbAccent a) => Semantics(
    button: true,
    label: tr('Fotoğraf ekle'),
    excludeSemantics: true,
    child: GestureDetector(
      onTap: _pickPhoto,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: a.soft,
              border: Border.all(color: a.c, width: 2),
              image: _photo == null
                  ? null
                  : DecorationImage(
                      image: FileImage(File(_photo!)),
                      fit: BoxFit.cover,
                    ),
            ),
            alignment: Alignment.center,
            child: _photo == null
                ? AdenaIcon('camera', size: 24, color: a.c, sw: 2)
                : null,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 76,
            child: Text(
              tr('Fotoğraf ekle'),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: a.t,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _genderField(OnbAccent a, String unknownLabel) => [
    OnbLabel(tr('Cinsiyet (isteğe bağlı)')),
    OnbPills<BabyGender>(
      accent: a,
      selected: _gender,
      onChanged: (g) => setState(() => _gender = _gender == g ? null : g),
      options: [
        (BabyGender.female, tr('Kız')),
        (BabyGender.male, tr('Erkek')),
        (BabyGender.unknown, unknownLabel),
      ],
    ),
  ];

  List<Widget> _bornFields(OnbAccent a) => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Bebeğini tanıyalım 🍼'), style: onbTitleStyle),
              const SizedBox(height: 6),
              Text(
                tr('Birkaç bilgiyle profili hazırlayalım.'),
                style: onbSubStyle(),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _photoButton(a),
      ],
    ),
    const SizedBox(height: 20),
    OnbLabel(tr('Bebeğin adı')),
    TextField(
      controller: _name,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      decoration: onbInputDecoration(
        context,
        hint: tr('ör. Aden'),
        accent: a,
        error: _nameError,
      ),
    ),
    if (_nameError) OnbFieldError(tr('Bebeğin adını gir')),
    const SizedBox(height: 14),
    OnbLabel(tr('Doğum tarihi')),
    OnbPickField(
      value: _date == null ? null : fmtDayMonthYear(_date!),
      placeholder: tr('Tarih seç'),
      accent: a,
      onTap: _pickDate,
    ),
    const SizedBox(height: 14),
    OnbLabel(tr('Prematüre doğdu mu?')),
    OnbSegment<bool>(
      accent: a,
      selected: _premature,
      onChanged: (v) => setState(() => _premature = v),
      options: [(false, tr('Hayır')), (true, tr('Evet'))],
    ),
    if (_premature) ...[
      const SizedBox(height: 14),
      OnbLabel(tr('Doğumdaki gebelik haftası')),
      OnbPickField(
        value: trp('{w} hf + {d} gün', {'w': _gestWeeks, 'd': _gestDays}),
        placeholder: '',
        icon: 'chevD',
        accent: a,
        active: true,
        onTap: _pickGestation,
      ),
    ],
    const SizedBox(height: 14),
    ..._genderField(a, tr('Belirtmek istemiyorum')),
  ];

  List<Widget> _pregFields(OnbAccent a) {
    final due = _date;
    final week = due == null ? null : pregnancyDays(due) ~/ 7;
    return [
      Text(tr('Bekleme odası 🤰'), style: onbTitleStyle),
      const SizedBox(height: 6),
      Text(tr('Kaçıncı haftada olduğunu hesaplayalım.'), style: onbSubStyle()),
      const SizedBox(height: 22),
      OnbSegment<bool>(
        accent: a,
        minHeight: 48,
        selected: _useLmp,
        onChanged: (v) => setState(() {
          if (v == _useLmp) return;
          _useLmp = v;
          _date = null;
          _lmp = null;
        }),
        options: [
          (false, tr('Tahmini doğum tarihi')),
          (true, tr('Son adet tarihi (SAT)')),
        ],
      ),
      const SizedBox(height: 14),
      OnbLabel(
        _useLmp
            ? tr('Son adet tarihinin ilk günü')
            : tr('Tahmini doğum tarihi'),
      ),
      OnbPickField(
        value: _useLmp
            ? (_lmp == null ? null : fmtDayMonthYear(_lmp!))
            : (due == null ? null : fmtDayMonthYear(due)),
        placeholder: tr('Tarih seç'),
        accent: a,
        onTap: _pickDate,
      ),
      if (due != null && week != null) ...[
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: a.soft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AdenaIcon('sparkle', size: 15, color: a.t, sw: 2.2),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    trp('≈ {w}. hafta · Tahmini doğum: {due}', {
                      'w': week,
                      'due': fmtDayMonthYear(due),
                    }),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: a.t,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 14),
      OnbLabel(tr('Bebeğin adı (varsa)')),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        decoration: onbInputDecoration(
          context,
          hint: tr('Henüz yoksa boş bırakabilirsin'),
          accent: a,
        ),
      ),
      const SizedBox(height: 14),
      ..._genderField(a, tr('Henüz bilmiyorum')),
    ];
  }
}
