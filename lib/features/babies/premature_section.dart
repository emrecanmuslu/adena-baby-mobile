import 'package:flutter/material.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

/// Doğmuş bebeklerde "prematüre doğdu mu?" girişi (Evet/Hayır + gebelik haftası
/// & gün). Bekleme modunda GÖSTERİLMEZ. Bekleme→doğum geçişinde tahmini doğum
/// tarihinden ön-doldurulabilir; kullanıcı yine de düzenleyebilir.
///
/// Durum dışarıda (haftalar nullsa kapalı). [onChanged] her değişimde
/// `(weeks, days)` verir; kapalıyken `(null, 0)`.
class PrematureSection extends StatefulWidget {
  /// Mevcut gebelik haftası (null = prematüre değil / kapalı).
  final int? weeks;

  /// Gebelik haftası üstüne gün (0..6).
  final int days;

  /// Değişimde tetiklenir: kapalı → (null, 0); açık → (haftalar, gün).
  final void Function(int? weeks, int days) onChanged;

  const PrematureSection({
    super.key,
    required this.weeks,
    required this.days,
    required this.onChanged,
  });

  @override
  State<PrematureSection> createState() => _PrematureSectionState();
}

class _PrematureSectionState extends State<PrematureSection> {
  late final TextEditingController _weeks;
  late final TextEditingController _days;

  /// Geçerli gebelik haftası aralığı (canlı doğum eşiği ~ tam zamanına kadar).
  static const int _minWeeks = 22;
  static const int _maxWeeks = 41;
  static const int _defaultWeeks = 38;

  bool get _on => widget.weeks != null;

  @override
  void initState() {
    super.initState();
    _weeks = TextEditingController(text: widget.weeks?.toString() ?? '');
    _days = TextEditingController(text: widget.days.toString());
    // AdStepper hem +/- hem klavye ile controller metnini değiştirir; her
    // değişimde üst duruma yansıt (yalnız bölüm açıkken).
    _weeks.addListener(_onText);
    _days.addListener(_onText);
  }

  void _onText() {
    if (_on) _emit();
  }

  @override
  void didUpdateWidget(covariant PrematureSection old) {
    super.didUpdateWidget(old);
    // Dışarıdan ön-doldurma (ör. tahmini doğum tarihinden türetme) yansısın.
    final w = widget.weeks?.toString() ?? '';
    if (w != _weeks.text) _weeks.text = w;
    final d = widget.days.toString();
    if (d != _days.text) _days.text = d;
  }

  @override
  void dispose() {
    _weeks.dispose();
    _days.dispose();
    super.dispose();
  }

  void _toggle(bool on) {
    if (on == _on) return;
    if (on) {
      final w = int.tryParse(_weeks.text) ?? _defaultWeeks;
      final clamped = w.clamp(_minWeeks, _maxWeeks);
      _weeks.text = clamped.toString();
      widget.onChanged(clamped, _clampDays(int.tryParse(_days.text) ?? 0));
    } else {
      widget.onChanged(null, 0);
    }
  }

  int _clampDays(int d) => d.clamp(0, 6);

  void _emit() {
    // Henüz tam yazılmamış (boş) haftayı clamp'leme — kullanıcı silerken
    // değeri zorla 22'ye çekmeyelim; geçerli sayı varsa yansıt.
    final wRaw = int.tryParse(_weeks.text);
    if (wRaw == null) return;
    final w = wRaw.clamp(_minWeeks, _maxWeeks);
    final d = _clampDays(int.tryParse(_days.text) ?? 0);
    // Tekrarlı/aynı değerle onChanged → gereksiz rebuild/döngü olmasın.
    if (w == widget.weeks && d == widget.days) return;
    widget.onChanged(w, d);
  }

  @override
  Widget build(BuildContext context) {
    return AdField(
      label: tr('Prematüre doğdu mu?'),
      info: tr('Bebeğin 37. gebelik haftasından önce doğduysa prematüredir. '
          'Doğumdaki gebelik haftasını girersen, büyüme ve gelişimi "düzeltilmiş '
          'yaşa" (olması gereken doğum tarihine) göre değerlendiririz. Aşı takvimi '
          'her zaman gerçek doğum tarihine göre kalır.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdTabs(
            options: {
              'no': tr('Hayır'),
              'yes': tr('Evet'),
            },
            selected: _on ? 'yes' : 'no',
            onSelect: (v) => _toggle(v == 'yes'),
          ),
          if (_on) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _miniLabel(tr('Gebelik haftası')),
                      const SizedBox(height: 6),
                      AdStepper(
                        controller: _weeks,
                        unit: tr('hf'),
                        accent: AppColors.coralDark,
                        min: _minWeeks.toDouble(),
                        max: _maxWeeks.toDouble(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _miniLabel(tr('Gün')),
                      const SizedBox(height: 6),
                      AdStepper(
                        controller: _days,
                        unit: tr('gün'),
                        accent: AppColors.coralDark,
                        min: 0,
                        max: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniLabel(String s) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          s.toUpperCaseTr(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: AppColors.muted,
            letterSpacing: 0.3,
          ),
        ),
      );
}
