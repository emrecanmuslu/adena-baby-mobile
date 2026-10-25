import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'i18n.dart';
import 'theme.dart';

/// Tanıtım turunda vurgulanan ekran öğeleri — öğe [KeyedSubtree] ile bu
/// anahtarı taşır; tur, öğenin ekrandaki dikdörtgenini anahtardan okur.
/// (design/Adena Baby App/Tasarimlar/Tanıtım Turu — spotlight + cam balon)
class CoachKeys {
  CoachKeys._();
  // Ana ekran
  static final quick = GlobalKey(debugLabel: 'coach.quick');
  static final plus = GlobalKey(debugLabel: 'coach.plus');
  static final summary = GlobalKey(debugLabel: 'coach.summary');
  static final pencil = GlobalKey(debugLabel: 'coach.pencil');
  static final profile = GlobalKey(debugLabel: 'coach.profile');
  // Bekleme odası
  static final fetus = GlobalKey(debugLabel: 'coach.fetus');
  static final week = GlobalKey(debugLabel: 'coach.week');
  static final born = GlobalKey(debugLabel: 'coach.born');
  // Grafikler
  static final chart = GlobalKey(debugLabel: 'coach.chart');
}

/// Tur adımı: başlık + metin + vurgulanacak öğeler (boşsa balon ortada).
class CoachStep {
  final String title;
  final String body;
  final List<GlobalKey> targets;
  const CoachStep(this.title, this.body, [this.targets = const []]);
}

/// Spotlight turunu açar. [finalLabel] son adımın ana butonu ("Bitti" /
/// "İlk kaydı ekle"); [onFinal] son adımda ana butona basılınca (tur
/// kapandıktan sonra) çağrılır. Geç / sistem geri tuşu turu kapatır; dışarı
/// dokunmak kapatmaz.
Future<void> showCoachTour(
  BuildContext context, {
  required List<CoachStep> steps,
  String? finalLabel,
  VoidCallback? onFinal,
}) async {
  final finished = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) =>
        _CoachOverlay(steps: steps, finalLabel: finalLabel ?? tr('Bitti')),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
  );
  if (finished == true) onFinal?.call();
}

class _CoachOverlay extends StatefulWidget {
  final List<CoachStep> steps;
  final String finalLabel;
  const _CoachOverlay({required this.steps, required this.finalLabel});

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay>
    with SingleTickerProviderStateMixin {
  int _i = 0;
  List<RRect> _holes = const [];
  bool _focused = false; // kaydırma bitti, delikler canlı izlenebilir

  // Delikler her karede yeniden ölçülür: hedef sonradan kayarsa (ölçümden
  // sonra devam eden kaydırma, içerik yüklenip yerleşimin değişmesi, AppBar
  // daralması) vurgu eski yerde kalıp yanlış öğeyi gösteriyordu.
  // Hareket durunca (~0.5 sn sabit kalınca) durur — sürekli kare istemez.
  int _stableFrames = 0;
  late final Ticker _ticker = createTicker((_) {
    if (!_focused || !mounted) return;
    final next = _measure(_step.targets);
    if (!_sameHoles(next, _holes)) {
      _stableFrames = 0;
      setState(() => _holes = next);
    } else if (++_stableFrames > 30) {
      _ticker.stop();
    }
  });

  /// Delikleri bir süre canlı izle (kaydırma/yerleşim oturana dek).
  void _track() {
    _stableFrames = 0;
    if (!_ticker.isActive) _ticker.start();
  }

  static bool _sameHoles(List<RRect> a, List<RRect> b) {
    if (a.length != b.length) return false;
    for (var k = 0; k < a.length; k++) {
      if ((a[k].left - b[k].left).abs() > 0.5 ||
          (a[k].top - b[k].top).abs() > 0.5 ||
          (a[k].width - b[k].width).abs() > 0.5 ||
          (a[k].height - b[k].height).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusStep());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  CoachStep get _step => widget.steps[_i];
  bool get _last => _i == widget.steps.length - 1;

  /// Hedef ekran dışındaysa sayfayı kaydır (300ms), sonra delikleri ölç.
  Future<void> _focusStep() async {
    final keys = _step.targets;
    final first = keys.isEmpty ? null : keys.first.currentContext;
    if (first != null && first.mounted) {
      final box = first.findRenderObject() as RenderBox?;
      final size = MediaQuery.of(context).size;
      if (box != null && box.hasSize) {
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        // Büyük hedef (ör. fetüs görseli) üste yaslanır ki altına balon sığsın.
        final tall = box.size.height > size.height * 0.4;
        if (tall || top < 80 || bottom > size.height - 110) {
          await Scrollable.ensureVisible(
            first,
            alignment: tall ? 0.0 : 0.25,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _holes = _measure(keys);
      _focused = true;
    });
    _track();
  }

  List<RRect> _measure(List<GlobalKey> keys) {
    final out = <RRect>[];
    for (final k in keys) {
      final ctx = k.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      final pad = r.shortestSide < 64 ? 4.0 : 6.0;
      final rect = r.inflate(pad);
      // Küçük/kare öğe → daire; büyük blok → yumuşak köşeli dikdörtgen.
      final radius = (r.width - r.height).abs() < 12
          ? rect.shortestSide / 2
          : 24.0;
      out.add(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }
    return out;
  }

  void _next() {
    if (_last) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _i++;
      _holes = const [];
      _focused = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusStep());
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final scrim = dark ? const Color(0xB30A060E) : const Color(0x8C3D2B26);
    final n = widget.steps.length;
    return PopScope(
      // Sistem geri tuşu turu kapatır (görüldü sayılır).
      // showGeneralDialog sayfasında Material yok → metin teması için şart.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // dışarı dokunmak turu kapatmaz
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(_i),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  builder: (_, t, _) => CustomPaint(
                    painter: _ScrimPainter(
                      holes: _holes,
                      color: scrim,
                      reveal: t,
                    ),
                  ),
                ),
              ),
            ),
            _bubble(context, size, dark, n),
          ],
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context, Size size, bool dark, int n) {
    final width = math.min(358.0, size.width - 32);
    final pad = MediaQuery.of(context).padding;
    final target = _holes.isEmpty ? null : _holes.first.outerRect;
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _BubbleLayout(
          target: target,
          width: width,
          safe: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 8),
        ),
        child: _BubbleHost(
          // Yerleşim (altta/üstte/sabit) ancak balon ölçülünce kesinleşir —
          // ok yönünü ve konumunu delegate'in kararı belirler.
          builder: (placement) => _CoachBubble(
            width: width,
            dark: dark,
            maxHeight: size.height - pad.top - pad.bottom - 16,
            arrowX: placement.arrowX,
            arrowUp: placement.arrowUp,
            counter: '${_i + 1}/$n',
            title: _step.title,
            body: _step.body,
            dots: n,
            index: _i,
            primary: _last ? widget.finalLabel : tr('İleri'),
            onPrimary: _next,
            onSkip: () => Navigator.of(context).pop(false),
          ),
          target: target,
          width: width,
          safe: EdgeInsets.fromLTRB(16, pad.top + 8, 16, pad.bottom + 8),
          screen: size,
        ),
      ),
    );
  }
}

/// Balonun ok konumu/yönü (ölçülen yüksekliğe göre hesaplanır).
class _Placement {
  final double? arrowX; // null → ok yok
  final bool arrowUp;
  const _Placement(this.arrowX, this.arrowUp);
}

const double _gap = 14;

/// Ölçülen balon yüksekliğine göre yerleşim kararı — delegate ve host aynı
/// kuralı kullanır: önce hedefin altı, sonra üstü; ikisine de sığmazsa
/// güvenli alanın altına sabitlenir (ok yok). Balon her zaman güvenli alanda.
({double top, _Placement placement}) _place(
  Rect? target,
  double width,
  double h,
  EdgeInsets safe,
  Size screen,
) {
  final topLimit = safe.top;
  final bottomLimit = screen.height - safe.bottom;
  final left = (screen.width - width) / 2;
  if (target == null) {
    return (
      top: ((screen.height - h) / 2).clamp(
        topLimit,
        math.max(topLimit, bottomLimit - h),
      ),
      placement: const _Placement(null, false),
    );
  }
  final ax = (target.center.dx - left - 8).clamp(14.0, width - 30);
  if (target.bottom + _gap + h <= bottomLimit) {
    return (top: target.bottom + _gap, placement: _Placement(ax, true));
  }
  if (target.top - _gap - h >= topLimit) {
    return (top: target.top - _gap - h, placement: _Placement(ax, false));
  }
  return (
    top: math.max(topLimit, bottomLimit - h),
    placement: const _Placement(null, false),
  );
}

class _BubbleLayout extends SingleChildLayoutDelegate {
  final Rect? target;
  final double width;
  final EdgeInsets safe;
  _BubbleLayout({
    required this.target,
    required this.width,
    required this.safe,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints(maxWidth: width, maxHeight: c.maxHeight - safe.vertical);

  @override
  Offset getPositionForChild(Size size, Size child) {
    final r = _place(target, width, child.height, safe, size);
    return Offset((size.width - width) / 2, r.top);
  }

  @override
  bool shouldRelayout(_BubbleLayout old) =>
      old.target != target || old.width != width || old.safe != safe;
}

/// Balonu bir kez ölçüp ok yönünü/konumunu ölçülen yüksekliğe göre seçer.
class _BubbleHost extends StatefulWidget {
  final Widget Function(_Placement) builder;
  final Rect? target;
  final double width;
  final EdgeInsets safe;
  final Size screen;
  const _BubbleHost({
    required this.builder,
    required this.target,
    required this.width,
    required this.safe,
    required this.screen,
  });

  @override
  State<_BubbleHost> createState() => _BubbleHostState();
}

class _BubbleHostState extends State<_BubbleHost> {
  final _key = GlobalKey();
  double? _h;

  void _measure() {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_h == null || (h - _h!).abs() > 0.5) setState(() => _h = h);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
    final placement = _h == null
        ? const _Placement(null, false)
        : _place(
            widget.target,
            widget.width,
            _h!,
            widget.safe,
            widget.screen,
          ).placement;
    // İlk karede (ölçülmeden) görünmez — yanlış yerde bir an belirmesin.
    return Opacity(
      opacity: _h == null ? 0 : 1,
      child: KeyedSubtree(key: _key, child: widget.builder(placement)),
    );
  }
}

/// Karartma + yuvarlatılmış delikler (path difference) + 2px beyaz kontur.
class _ScrimPainter extends CustomPainter {
  final List<RRect> holes;
  final Color color;
  final double reveal;
  _ScrimPainter({
    required this.holes,
    required this.color,
    required this.reveal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    var cut = Path();
    for (final h in holes) {
      cut.addRRect(h);
    }
    final scrim = holes.isEmpty
        ? full
        : Path.combine(PathOperation.difference, full, cut);
    canvas.drawPath(scrim, Paint()..color = color);
    if (holes.isEmpty) return;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.9 * reveal);
    for (final h in holes) {
      canvas.drawRRect(h, stroke);
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.holes != holes || old.color != color || old.reveal != reveal;
}

/// Ok uçlu cam balon: sayaç, başlık, metin, adım noktaları, Geç + ana buton.
class _CoachBubble extends StatelessWidget {
  final double width;
  final double maxHeight; // güvenli alan yüksekliği — aşarsa metin kayar
  final bool dark;
  final double? arrowX; // null → ok yok (ortalanmış balon)
  final bool arrowUp;
  final String counter, title, body, primary;
  final int dots, index;
  final VoidCallback onPrimary, onSkip;
  const _CoachBubble({
    required this.width,
    required this.maxHeight,
    required this.dark,
    required this.arrowX,
    required this.arrowUp,
    required this.counter,
    required this.title,
    required this.body,
    required this.dots,
    required this.index,
    required this.primary,
    required this.onPrimary,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final fill = dark
        ? const Color(
            0xFF2A2133,
          ) // %9 beyaz cam, koyu zemin üstünde opak eşdeğeri
        : Colors.white.withValues(alpha: 0.92);
    final border = dark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.7);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final ax = arrowX == null ? null : (rtl ? width - arrowX! - 16 : arrowX!);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$counter. $title. $body',
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          minWidth: width,
          maxHeight: maxHeight,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: border),
                    boxShadow: AppColors.softShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (dots > 1)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    counter,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                      color: AppColors.coralDd,
                                    ),
                                  ),
                                ),
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                body,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                  color: dark ? AppColors.ink2 : AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Tek satır: noktalar · Geç · ana düğme. Uzun metinde
                      // (dil / büyük yazı) ana düğmenin yazısı kendi içinde
                      // kırılır — satır taşmaz, balon genişliği sabit kalır.
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        child: Row(
                          children: [
                            if (dots > 1)
                              for (var j = 0; j < dots; j++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsetsDirectional.only(
                                    end: 6,
                                  ),
                                  width: j == index ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: j == index
                                        ? AppColors.coralDark
                                        : AppColors.muted.withValues(
                                            alpha: 0.45,
                                          ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            // Kalan genişliğin tamamı düğmelere; ana düğme
                            // yalnız gerçekten sığmazsa kendi içinde kırılır.
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: onSkip,
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(48, 44),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      foregroundColor: dark
                                          ? AppColors.muted
                                          : AppColors.ink2,
                                    ),
                                    child: Text(
                                      tr('Geç'),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: _PrimaryPill(
                                      label: primary,
                                      onTap: onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (ax != null)
              Positioned(
                left: ax,
                top: arrowUp ? -7 : null,
                bottom: arrowUp ? null : -7,
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(3),
                      border: Border(
                        left: arrowUp
                            ? BorderSide(color: border)
                            : BorderSide.none,
                        top: arrowUp
                            ? BorderSide(color: border)
                            : BorderSide.none,
                        right: arrowUp
                            ? BorderSide.none
                            : BorderSide(color: border),
                        bottom: arrowUp
                            ? BorderSide.none
                            : BorderSide(color: border),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        // Hizalama YOK: Container içeriği kadar kalsın (aksi halde verilen
        // genişliğin tamamını kaplayıp satırı kırıyordu).
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.coral, AppColors.coralDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40E2553F),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );
}
