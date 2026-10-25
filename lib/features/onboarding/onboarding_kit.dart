import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adena_icons.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

/// İlk açılış (onboarding) akışının ortak görsel kiti — "Gradyan & Cam"
/// (design/theme/Tasarimlar/OnboardingEkran.dc.html, Alternatif A).
///
/// Tüm onboarding ekranları (karşılama, rıza, formlar, giriş/kayıt, alt
/// sayfalar) bu parçaları kullanır; renk her zaman [AppColors]'tan gelir, dal
/// aksanı [OnbAccent] ile seçilir.

/// Onboarding dalı — aksan rengini belirler.
enum OnbBranch { baby, preg, cycle, ttc }

/// Dal aksanı: düz renk, metin rengi, açık zemin, gradyan ve buton gölgesi.
/// Koyu temada daha açık tonlar (tasarımdaki `dk`/`ds` değerleri).
class OnbAccent {
  final Color c; // ikon / kenar / seçili
  final Color t; // metin
  final Color soft; // açık zemin (hap, seçili kutu)
  final List<Color> grad; // buton + ikon plakası gradyanı
  final Color shadow; // buton gölgesi

  const OnbAccent._(this.c, this.t, this.soft, this.grad, this.shadow);

  /// Renkler [AppColors]'tan (tema duyarlı); gradyanlar onaylı karşılama
  /// ekranının plaka gradyanları.
  static OnbAccent of(BuildContext context, OnbBranch b) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (b) {
      OnbBranch.baby => OnbAccent._(
          dark ? AppColors.coral : AppColors.coralDark,
          dark ? AppColors.coral : AppColors.coralDd,
          AppColors.feedBg,
          const [AppColors.coral, AppColors.coralDark],
          const Color(0x47E2553F)),
      OnbBranch.preg => OnbAccent._(
          AppColors.gold,
          dark ? AppColors.gold : const Color(0xFFCC8A3C),
          AppColors.goldBg,
          const [Color(0xFFE3B255), Color(0xFFCC8A3C)],
          const Color(0x47CC8A3C)),
      OnbBranch.cycle || OnbBranch.ttc => OnbAccent._(
          AppColors.rose,
          AppColors.roseD,
          AppColors.roseBg,
          const [Color(0xFFD9799A), Color(0xFFB0466B)],
          const Color(0x42B0466B)),
    };
  }

  /// Dal dışı ekranlar (hesap, davet, aktarım) mercan kullanır.
  static OnbAccent coral(BuildContext context) => of(context, OnbBranch.baby);

  /// Gebe kalma alt-aksanı (adaçayı) — yalnız hedef plakası ve etiket.
  static Color get sage => AppColors.sage;

/// Hedef kartı ikon plakası gradyanı (gebe kalma: gül → adaçayı).
  static List<Color> plate(BuildContext context, OnbBranch b) =>
      b == OnbBranch.ttc ? [const Color(0xFFD9799A), sage] : of(context, b).grad;
}

bool _dark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

/// Cam yüzey rengi/kenarı (kart, alan, segment zemini).
Color onbCardFill(BuildContext context) =>
    _dark(context) ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.58);
Color onbFieldFill(BuildContext context) =>
    _dark(context) ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.66);
Color onbFieldBorder(BuildContext context) =>
    _dark(context) ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.9);

/// Ekran başlığı / alt başlık stilleri.
const onbTitleStyle =
    TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.6, height: 1.15);
TextStyle onbSubStyle() => TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, height: 1.45, color: AppColors.ink2);

/// Yuvarlak cam geri düğmesi (44px).
class OnbBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  const OnbBackButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: GestureDetector(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: onbCardFill(context),
            shape: BoxShape.circle,
            border: Border.all(color: onbFieldBorder(context)),
            boxShadow: AppColors.softShadow,
          ),
          alignment: Alignment.center,
          child: Transform.flip(
            flipX: rtl,
            child: AdenaIcon('chevL', size: 20, color: AppColors.ink, sw: 2.2),
          ),
        ),
      ),
    );
  }
}

/// Form üst barı: geri + 2 adımlı ilerleme göstergesi (2. adım aktif).
class OnbTopBar extends StatelessWidget {
  final OnbAccent accent;
  final bool showSteps;
  final VoidCallback? onBack;
  const OnbTopBar(
      {super.key, required this.accent, this.showSteps = true, this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
              alignment: AlignmentDirectional.centerStart,
              child: OnbBackButton(onTap: onBack)),
          if (showSteps)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 26,
                  height: 6,
                  decoration: BoxDecoration(
                      color: accent.c.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Container(
                  width: 36,
                  height: 6,
                  decoration: BoxDecoration(
                      color: accent.c, borderRadius: BorderRadius.circular(3))),
            ]),
        ],
      ),
    );
  }
}

/// Alan etiketi (13px, ink2).
class OnbLabel extends StatelessWidget {
  final String text;
  const OnbLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink2)),
      );
}

/// Cam metin alanı dekorasyonu (54px kutu, 16px radius).
InputDecoration onbInputDecoration(BuildContext context,
    {required String hint, Widget? suffix, OnbAccent? accent, bool error = false}) {
  final a = accent ?? OnbAccent.coral(context);
  OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
        color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 16),
    isDense: true,
    filled: true,
    fillColor: onbFieldFill(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    suffixIcon: suffix,
    enabledBorder: error ? b(AppColors.fever, 1.5) : b(onbFieldBorder(context), 1),
    focusedBorder: b(error ? AppColors.fever : a.c, 1.5),
    errorBorder: b(AppColors.fever, 1.5),
    focusedErrorBorder: b(AppColors.fever, 1.5),
    errorStyle: const TextStyle(
        color: AppColors.coralDd, fontWeight: FontWeight.w800, fontSize: 13),
  );
}

/// Alan altı hata satırı (ikonlu).
class OnbFieldError extends StatelessWidget {
  final String text;
  const OnbFieldError(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 7, 4, 0),
        child: Row(children: [
          const AdenaIcon('alert', size: 15, color: AppColors.coralDd, sw: 2.2),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.coralDd)),
          ),
        ]),
      );
}

/// Dokunulabilir seçim alanı (tarih vb.): değer/yer tutucu + sağda ikon.
class OnbPickField extends StatelessWidget {
  final String? value;
  final String placeholder;
  final String icon;
  final OnbAccent accent;
  final VoidCallback onTap;
  final bool active;
  const OnbPickField({
    super.key,
    required this.value,
    required this.placeholder,
    required this.accent,
    required this.onTap,
    this.icon = 'calendar',
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: onbFieldFill(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: active ? accent.c : onbFieldBorder(context),
                width: active ? 1.5 : 1),
          ),
          child: Row(children: [
            Expanded(
              child: Text(has ? value! : placeholder,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: has ? FontWeight.w800 : FontWeight.w600,
                      color: has ? AppColors.ink : AppColors.muted)),
            ),
            AdenaIcon(icon, size: 22, color: accent.c, sw: 2),
          ]),
        ),
      ),
    );
  }
}

/// İki (veya daha fazla) seçenekli segment — seçili beyaz/cam, aksan metni.
class OnbSegment<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final OnbAccent accent;
  final double minHeight;
  const OnbSegment({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.accent,
    this.minHeight = 44,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _dark(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: onbFieldFill(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onbFieldBorder(context)),
      ),
      child: Row(children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              button: true,
              selected: options[i].$1 == selected,
              child: GestureDetector(
                onTap: () => onChanged(options[i].$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: BoxConstraints(minHeight: minHeight),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: options[i].$1 == selected
                        ? (dark
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.96))
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow:
                        options[i].$1 == selected ? AppColors.softShadow : null,
                  ),
                  child: Text(options[i].$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14.5,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          color: options[i].$1 == selected
                              ? accent.t
                              : AppColors.ink2)),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Hap seçenekleri (cinsiyet vb.) — sarılır; seçili aksan zemini + kenar.
class OnbPills<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onChanged;
  final OnbAccent accent;
  const OnbPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        Semantics(
          button: true,
          selected: o.$1 == selected,
          child: GestureDetector(
            onTap: () => onChanged(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: o.$1 == selected ? accent.soft : onbFieldFill(context),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: o.$1 == selected ? accent.c : onbFieldBorder(context),
                    width: o.$1 == selected ? 1.5 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(o.$2,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: o.$1 == selected ? accent.t : AppColors.ink2)),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Ana eylem düğmesi: 56px, 16px radius, dal gradyanı + gölge.
class OnbPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final OnbAccent accent;
  final bool loading;
  final double height;
  const OnbPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.accent,
    this.loading = false,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: onTap == null ? 0.45 : (loading ? 0.62 : 1),
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: accent.grad,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: onTap == null
                  ? null
                  : [
                      BoxShadow(
                          color: accent.shadow,
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ],
            ),
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.6, color: Colors.white))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w900)),
                  ),
          ),
        ),
      ),
    );
  }
}

/// İkincil metin düğmesi (48px dokunma alanı).
class OnbTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  const OnbTextButton(
      {super.key, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color ?? AppColors.ink2)),
          ),
        ),
      );
}

/// Cam alt sayfa — tutma çubuğu + 28px üst radius + 24px blur.
Future<T?> showOnbSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) async {
  // Sayfa kapanınca alttaki rota kendi kapsamının son odaklı alanına geri
  // dönüp klavyeyi kendiliğinden açıyordu (ör. tarih seçince ad alanı).
  // Odaklı DÜĞÜMÜN kendisinde unfocus → kapsamın odak geçmişi temizlenir
  // (kapsamda `FocusScope.of(context).unfocus()` geçmişi temizlemez).
  FocusManager.instance.primaryFocus?.unfocus();
  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    barrierColor: _dark(context)
        ? const Color(0x8C0A060E)
        : const Color(0x573D2B26),
    builder: (ctx) => PopScope(
      canPop: dismissible,
      child: OnbSheetBody(child: builder(ctx)),
    ),
  );
  return result;
}

/// Alt sayfa gövdesi (klavye için alt boşluk + güvenli alan dahil).
class OnbSheetBody extends StatelessWidget {
  final Widget child;
  const OnbSheetBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = _dark(context);
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xDB251C30)
                  : const Color(0xE6FFF8F4),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                  top: BorderSide(color: onbFieldBorder(context))),
            ),
            padding: EdgeInsets.fromLTRB(22, 10, 22, 24 + mq.padding.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                          color: AppColors.line2,
                          borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Onboarding takvim alt sayfası (tasarım [4] "tarih seçici açık"). Ay ızgarası,
/// ileri/geri, [first]..[last] dışı günler pasif. Seçilen günü döndürür.
Future<DateTime?> showOnbDatePicker(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  required OnbAccent accent,
}) {
  DateTime d0(DateTime d) => DateTime(d.year, d.month, d.day);
  final f = d0(first), l = d0(last);
  var sel = d0(initial);
  if (sel.isBefore(f)) sel = f;
  if (sel.isAfter(l)) sel = l;
  return showOnbSheet<DateTime>(
    context,
    builder: (ctx) => _OnbCalendar(
        title: title, initial: sel, first: f, last: l, accent: accent),
  );
}

class _OnbCalendar extends StatefulWidget {
  final String title;
  final DateTime initial, first, last;
  final OnbAccent accent;
  const _OnbCalendar({
    required this.title,
    required this.initial,
    required this.first,
    required this.last,
    required this.accent,
  });

  @override
  State<_OnbCalendar> createState() => _OnbCalendarState();
}

class _OnbCalendarState extends State<_OnbCalendar> {
  late DateTime _sel = widget.initial;
  late DateTime _month = DateTime(widget.initial.year, widget.initial.month);

  bool get _canPrev =>
      DateTime(_month.year, _month.month).isAfter(
          DateTime(widget.first.year, widget.first.month));
  bool get _canNext =>
      DateTime(_month.year, _month.month).isBefore(
          DateTime(widget.last.year, widget.last.month));

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    final loc = MaterialLocalizations.of(context);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    // Pazartesi başlangıçlı ızgara (tr/eu); DateTime.weekday 1=Pzt.
    final lead = DateTime(_month.year, _month.month, 1).weekday - 1;
    final weekdays = List.generate(
        7, (i) => fmtWeekdayShort(DateTime(2024, 1, 1 + i))); // 1 Oca 2024 = Pzt
    final rtl = Directionality.of(context) == TextDirection.rtl;

    Widget nav(String icon, bool on, VoidCallback go) => Semantics(
          button: true,
          enabled: on,
          label: icon == 'chevL'
              ? loc.previousMonthTooltip
              : loc.nextMonthTooltip,
          child: GestureDetector(
            onTap: on ? go : null,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Transform.flip(
                  flipX: rtl,
                  child: AdenaIcon(icon,
                      size: 20,
                      sw: 2.2,
                      color: on ? AppColors.ink2 : AppColors.muted2),
                ),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4),
          child: Text(widget.title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          nav('chevL', _canPrev,
              () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
          Expanded(
            child: Text(fmtMonthYear(_month),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          ),
          nav('chevR', _canNext,
              () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1.05,
          children: [
            for (final w in weekdays)
              Center(
                child: Text(w,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted)),
              ),
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++)
              Builder(builder: (_) {
                final d = DateTime(_month.year, _month.month, day);
                final on = !d.isBefore(widget.first) && !d.isAfter(widget.last);
                final picked = DateUtils.isSameDay(d, _sel);
                return Semantics(
                  button: on,
                  selected: picked,
                  label: fmtDayMonthYear(d),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: on ? () => setState(() => _sel = d) : null,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: picked ? a.soft : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: picked ? a.c : Colors.transparent,
                            width: 1.5),
                      ),
                      child: Text('$day',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: picked ? FontWeight.w900 : FontWeight.w700,
                              color: picked
                                  ? a.t
                                  : (on ? AppColors.ink : AppColors.muted2))),
                    ),
                  ),
                );
              }),
          ],
        ),
        const SizedBox(height: 18),
        OnbPrimaryButton(
          label: tr('Seç'),
          accent: a,
          onTap: () => Navigator.pop(context, _sel),
        ),
      ],
    );
  }
}

/// Kutulu kod girişi (davet 8 / şifre sıfırlama 6). Kutular görsel; giriş tek
/// görünmez alanda — yapıştırma ve klavye otomatik doldurma da çalışır.
class OnbCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool error;
  final bool digitsOnly;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final OnbAccent accent;
  const OnbCodeInput({
    super.key,
    required this.controller,
    required this.length,
    required this.accent,
    this.error = false,
    this.digitsOnly = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  State<OnbCodeInput> createState() => _OnbCodeInputState();
}

class _OnbCodeInputState extends State<OnbCodeInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    final n = widget.length;
    final current = code.length.clamp(0, n - 1);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        Row(children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(width: n > 6 ? 6 : 8),
            Expanded(
              child: Container(
                height: n > 6 ? 56 : 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: onbFieldFill(context),
                  borderRadius: BorderRadius.circular(n > 6 ? 12 : 14),
                  border: Border.all(
                    color: widget.error
                        ? AppColors.fever
                        : (_focus.hasFocus && i == current
                            ? widget.accent.c
                            : onbFieldBorder(context)),
                    width: widget.error || (_focus.hasFocus && i == current)
                        ? 1.5
                        : 1,
                  ),
                ),
                child: Text(i < code.length ? code[i] : '',
                    style: TextStyle(
                        fontSize: n > 6 ? 21 : 22,
                        fontWeight: FontWeight.w900,
                        color: widget.error ? AppColors.coralDd : AppColors.ink)),
              ),
            ),
          ],
        ]),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              maxLength: n,
              showCursor: false,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: widget.digitsOnly
                  ? TextInputType.number
                  : TextInputType.visiblePassword,
              autofillHints:
                  widget.digitsOnly ? const [AutofillHints.oneTimeCode] : null,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(widget.digitsOnly ? '[0-9]' : '[A-Za-z0-9]')),
                _UpperCaseFormatter(),
              ],
              onSubmitted: widget.onSubmitted,
              decoration:
                  const InputDecoration(counterText: '', border: InputBorder.none),
            ),
          ),
        ),
      ]),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}
