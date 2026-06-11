import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'adena_icons.dart';
import 'i18n.dart';
import 'theme.dart';

/// Adena tasarım sistemi bileşenleri (design adena.css .ad-* sınıfları).
/// Uygulama geneli paylaşılır (formlar, ayarlar, auth, üyeler…).

/// Alan zemini (design var(--bg)) — açık/koyu uyumlu.
Color fieldBg(BuildContext c) =>
    Theme.of(c).brightness == Brightness.dark ? const Color(0xFF251D2E) : AppColors.cream;

/// .ad-field — üstte küçük etiket + içerik. [info] verilirse etiketin yanına
/// "!" yardım rozeti (AdInfoDot) eklenir; dokununca o alanın ne işe yaradığını
/// anlatan dialog açılır (basit kullanım ilkesi — her alanda olmalı).
class AdField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? info;
  const AdField({super.key, required this.label, required this.child, this.info});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 7),
            child: Row(
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.muted,
                        letterSpacing: 0.4)),
                if (info != null) ...[
                  const SizedBox(width: 6),
                  AdInfoDot(title: label, body: info!),
                ],
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Başlık/etiket yanındaki "!" yardım rozeti — dokununca [showAdInfo] ile o
/// özelliğin nasıl kullanıldığını ve ne işe yaradığını anlatan dialog açar.
/// Uygulama genelinde her alan/bölüm başlığının yanında bulunmalı.
class AdInfoDot extends StatelessWidget {
  final String title;
  final String body;
  final double size;
  const AdInfoDot({super.key, required this.title, required this.body, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showAdInfo(context, title, body),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.coral, width: 1.4),
        ),
        alignment: Alignment.center,
        child: Text('!',
            style: TextStyle(
                fontSize: size * 0.72,
                fontWeight: FontWeight.w900,
                height: 1.05,
                color: AppColors.coral)),
      ),
    );
  }
}

/// Bir alan/bölümün "ne işe yarar / nasıl kullanılır" açıklamasını gösteren
/// dialog (AdInfoDot buna açar). Sade, tek "Anladım" butonlu.
Future<void> showAdInfo(BuildContext context, String title, String body) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                      color: AppColors.feedBg, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Text('!',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.coralDark)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Text(body,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink2)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(foregroundColor: AppColors.coralDark),
                child: Text(tr('Anladım'),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// .ad-input — yuvarlak çizgi-çerçeveli metin alanı.
class AdInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final TextCapitalization capitalization;
  const AdInput({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.formatters,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textCapitalization: capitalization,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.line, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.coral, width: 1.5),
        ),
      ),
    );
  }
}

/// .ad-stepper — − [değer birim] + (değer aynı zamanda yazılabilir).
class AdStepper extends StatefulWidget {
  final TextEditingController controller;
  final String unit;
  final double step;
  final int decimals;
  final Color? accent; // null → AppColors.ink (tema-duyarlı)
  const AdStepper({
    super.key,
    required this.controller,
    required this.unit,
    this.step = 1,
    this.decimals = 0,
    this.accent,
  });

  @override
  State<AdStepper> createState() => _AdStepperState();
}

class _AdStepperState extends State<AdStepper> {
  String _fmt(double v) =>
      widget.decimals == 0 ? v.toStringAsFixed(0) : _trim(v.toStringAsFixed(widget.decimals));
  String _trim(String s) => s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;

  void _bump(int dir) {
    final cur = double.tryParse(widget.controller.text.replaceAll(',', '.')) ?? 0;
    var v = cur + dir * widget.step;
    if (v < 0) v = 0;
    final text = _fmt(v);
    widget.controller.text = text;
    widget.controller.selection = TextSelection.collapsed(offset: text.length);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: fieldBg(context), borderRadius: BorderRadius.circular(15)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _btn('−', () => _bump(-1)),
          const SizedBox(width: 8),
          // Sayı + birim BİRLİKTE ortalanır (design .ad-stepper .val); dar
          // sütunda (iki stepper yan yana) içerik büyüyünce taşmaz, hafif küçülür.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 22),
                    child: IntrinsicWidth(
                      child: TextField(
                        controller: widget.controller,
                        textAlign: TextAlign.center,
                        keyboardType:
                            TextInputType.numberWithOptions(decimal: widget.decimals > 0),
                        inputFormatters: widget.decimals > 0
                            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
                            : [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: widget.accent ?? AppColors.ink),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: '0',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(widget.unit,
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.muted)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _btn('+', () => _bump(1)),
        ],
      ),
    );
  }

  Widget _btn(String s, VoidCallback onTap) {
    // design .ad-stepper button — beyaz, gölgeli çip (krem zeminden ayrışsın).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppColors.smallShadow,
        ),
        alignment: Alignment.center,
        child: Text(s,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.coralDark)),
      ),
    );
  }
}

/// .ad-tabs — segment sekmeleri (ör. beslenme türü).
class AdTabs extends StatelessWidget {
  final Map<String, String> options; // key → etiket
  final String selected;
  final ValueChanged<String> onSelect;
  const AdTabs(
      {super.key, required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    final n = keys.length;
    final idx = keys.indexOf(selected).clamp(0, n - 1);
    // Tek kayan vurgu (thumb) → geçişte iki sekme aynı anda vurgulanmaz.
    final x = n <= 1 ? 0.0 : (2 * idx + 1 - n) / (n - 1);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment(x, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: AppColors.softShadow,
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final e in options.entries)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Text(e.value,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: e.key == selected ? AppColors.coralDark : AppColors.muted,
                          )),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// .ad-choice — ikon + etiketli seçim ızgarası (ör. bez türü).
class AdChoice extends StatelessWidget {
  final List<({String key, String label, String icon, Color color, Color bg})> items;
  final String selected;
  final ValueChanged<String> onSelect;
  const AdChoice(
      {super.key, required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 11),
          Expanded(child: _tile(context, items[i])),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, ({String key, String label, String icon, Color color, Color bg}) it) {
    final on = it.key == selected;
    return GestureDetector(
      onTap: () => onSelect(it.key),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: on ? AppColors.feedBg : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? AppColors.coral : AppColors.line, width: 2),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: it.bg, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: AdenaIcon(it.icon, size: 22, color: it.color),
            ),
            const SizedBox(height: 8),
            Text(it.label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// .ad-sides — iki seçenekli yan-yana tile (ör. pompa zamanlaması).
class AdSides extends StatelessWidget {
  final List<({String key, String label, String? small})> items;
  final String selected;
  final ValueChanged<String> onSelect;
  const AdSides(
      {super.key, required this.items, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    // Bir tile'da alt etiket varsa hepsi o satırı rezerve eder → eşit yükseklik
    // (biri "sıradaki" yazıp diğeri boş kalınca tasarım bozulmasın).
    final anySmall = items.any((e) => e.small != null);
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _tile(context, items[i], anySmall)),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, ({String key, String label, String? small}) it,
      bool reserveSmall) {
    final on = it.key == selected;
    return GestureDetector(
      onTap: () => onSelect(it.key),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: on ? AppColors.feedBg : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: on ? AppColors.coral : AppColors.line, width: 2),
        ),
        child: Column(
          children: [
            Text(it.label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: on ? AppColors.coralDd : null)),
            if (reserveSmall) ...[
              const SizedBox(height: 3),
              Text((it.small ?? '').toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.muted,
                      letterSpacing: 0.3)),
            ],
          ],
        ),
      ),
    );
  }
}

/// NowChip — saat/tarih + "değiştir" zaman çipi (dokununca seçici açar).
class AdTimeChip extends StatelessWidget {
  final DateTime? value;
  final VoidCallback onTap;
  const AdTimeChip({super.key, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final text = v == null
        ? tr('Tarih/saat seç')
        : (DateUtils.isSameDay(v, DateTime.now())
            ? trp('Bugün · {t}', {'t': DateFormat('HH:mm').format(v)})
            : DateFormat('d MMM · HH:mm', 'tr_TR').format(v));
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: fieldBg(context), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            AdenaIcon('clock', size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Text(text,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w900, color: AppColors.ink2)),
            const Spacer(),
            Text(tr('değiştir'),
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.coralDark)),
          ],
        ),
      ),
    );
  }
}

/// .ad-save — tam genişlik kategori-renkli kaydet (veya ghost ikincil).
class AdSaveButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool ghost;
  const AdSaveButton(
      {super.key,
      required this.label,
      required this.color,
      required this.onTap,
      this.ghost = false});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final child = Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16));
    return SizedBox(
      width: double.infinity,
      child: ghost
          ? OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: BorderSide(color: AppColors.line, width: 1.5),
                shape: shape,
              ),
              child: child,
            )
          : FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: shape,
              ),
              child: child,
            ),
    );
  }
}

/// Renkli yuvarlak-kare ikon çipi (design .ad-ic) — menü/satır ikonları için.
class AdIconChip extends StatelessWidget {
  final String icon;
  final Color color;
  final Color bg;
  final double size;
  const AdIconChip(this.icon,
      {super.key, required this.color, required this.bg, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.34)),
      alignment: Alignment.center,
      child: AdenaIcon(icon, size: size * 0.52, color: color),
    );
  }
}

/// .ad-menuitem — ayarlar/menü satırı: ikon çipi + başlık + meta + sağ öğe.
class AdMenuItem extends StatelessWidget {
  final String icon;
  final Color color;
  final Color bg;
  final String title;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  const AdMenuItem({
    super.key,
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    this.meta,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                AdIconChip(icon, color: color, bg: bg),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: titleColor)),
                      if (meta != null) ...[
                        const SizedBox(height: 1),
                        Text(meta!,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted)),
                      ],
                    ],
                  ),
                ),
                trailing ??
                    AdenaIcon('chevR', size: 18, color: AppColors.muted2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sürükleme tutamağı (design .ad-grab) — bottom sheet'lerin üstünde.
Widget adGrabHandle() => Container(
      width: 40,
      height: 5,
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      decoration:
          BoxDecoration(color: AppColors.line2, borderRadius: BorderRadius.circular(3)),
    );

/// Bottom sheet üst köşe yarıçapı (design .ad-sheet 28px).
const adSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
);

/// Adena toast (design .ad-toast): koyu zemin + check + mesaj + opsiyonel
/// "Geri al" + altta coral timerline. SnackBar yerine kullanılır.
void showAdToast(BuildContext context, String message,
    {VoidCallback? onUndo, Duration duration = const Duration(milliseconds: 2800)}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _AdToast(
      message: message,
      onUndo: onUndo,
      duration: duration,
      onClose: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _AdToast extends StatefulWidget {
  final String message;
  final VoidCallback? onUndo;
  final Duration duration;
  final VoidCallback onClose;
  const _AdToast(
      {required this.message,
      required this.onUndo,
      required this.duration,
      required this.onClose});

  @override
  State<_AdToast> createState() => _AdToastState();
}

class _AdToastState extends State<_AdToast> with TickerProviderStateMixin {
  late final AnimationController _timer =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _close();
        })
        ..forward();
  late final AnimationController _in = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220))
    ..forward();
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    _in.reverse().whenComplete(widget.onClose);
  }

  @override
  void dispose() {
    _timer.dispose();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? Colors.black : AppColors.ink;
    final curved = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 88 + MediaQuery.of(context).padding.bottom,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(curved),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 13, 13, 13),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x332C1812), blurRadius: 28, offset: Offset(0, 12)),
                  ],
                ),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const AdenaIcon('check',
                              size: 14, color: Colors.white, sw: 2.4),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(widget.message,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5)),
                        ),
                        if (widget.onUndo != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              widget.onUndo!();
                              _close();
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(11)),
                              child: Text(tr('Geri al'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Positioned(
                      left: -16,
                      right: -13,
                      bottom: -13,
                      child: AnimatedBuilder(
                        animation: _timer,
                        builder: (_, _) => FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1 - _timer.value,
                          child: Container(height: 3, color: AppColors.coral),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bölüm başlığı (design .ad-sec) — uygulama geneli. [info] verilirse başlığın
/// yanına "!" yardım rozeti eklenir (bkz AdInfoDot).
Widget adSec(String title, {Color? color, String? info}) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 18, 3, 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: color ?? AppColors.muted,
              letterSpacing: 0.7,
            ),
          ),
          if (info != null) ...[
            const SizedBox(width: 6),
            AdInfoDot(title: title, body: info),
          ],
        ],
      ),
    );
