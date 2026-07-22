import 'package:flutter/material.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

/// "Bloom" paylaşımlı bileşen kiti — tasarım cycle.css `.cy-*` sınıflarının
/// Flutter karşılığı. Serif (Newsreader) yerine **Nunito w900** (uygulama fontu).
/// Renkler AppColors token'larından (rose/sage/gold/lochia + tema-duyarlı nötrler).

/// .cy-card / .soft / .tint
Widget cycCard(BuildContext c,
    {required Widget child,
    bool soft = false,
    bool tint = false,
    EdgeInsetsGeometry? padding,
    Color? color}) {
  return Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color ?? (tint ? AppColors.roseBg : Theme.of(c).colorScheme.surface),
      borderRadius: BorderRadius.circular(24),
      boxShadow: tint ? null : (soft ? AppColors.smallShadow : AppColors.softShadow),
    ),
    child: child,
  );
}

/// .cy-eyebrow — büyük-harf etiket + gradyan çizgi + opsiyonel link
class CycEyebrow extends StatelessWidget {
  final String text;
  final String? suffix;
  final String? link;
  final VoidCallback? onLink;
  final bool first;
  final String? info;
  final String? infoTitle;
  const CycEyebrow(this.text,
      {super.key,
      this.suffix,
      this.link,
      this.onLink,
      this.first = false,
      this.info,
      this.infoTitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 10 : 22, 4, 13),
      child: Row(
        children: [
          Text(text.toUpperCaseTr(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: AppColors.muted)),
          if (info != null) ...[
            const SizedBox(width: 6),
            AdInfoDot(title: infoTitle ?? text, body: info!),
          ],
          if (suffix != null) ...[
            const SizedBox(width: 6),
            Text(suffix!,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.line2, AppColors.line2.withValues(alpha: 0)]),
              ),
            ),
          ),
          if (link != null)
            GestureDetector(
              onTap: onLink,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(link!,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.roseD)),
              ),
            ),
        ],
      ),
    );
  }
}

/// .cy-note — bilgi kutusu (blush/clay) + ikon + gövde (+ opsiyonel "!" rozeti)
Widget cycNote(BuildContext c,
    {required IconData icon,
    required String body,
    bool clay = false,
    String? infoTitle,
    String? info}) {
  final tint = clay ? AppColors.lochiaBg : AppColors.roseBg;
  final ic = clay ? AppColors.lochia : AppColors.roseD;
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(18)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: ic),
      const SizedBox(width: 11),
      Expanded(
        child: Text(body,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
                color: AppColors.ink2)),
      ),
      if (info != null) ...[
        const SizedBox(width: 8),
        AdInfoDot(title: infoTitle ?? '', body: info),
      ],
    ]),
  );
}

/// .cy-pill — küçük renkli rozet
enum CycTone { rose, sage, gold, clay }

Widget cycPill(String text, {CycTone tone = CycTone.rose}) {
  final (bg, fg) = switch (tone) {
    CycTone.rose => (AppColors.roseBg, AppColors.roseD),
    CycTone.sage => (AppColors.sageBg, AppColors.sageD),
    CycTone.gold => (AppColors.goldBg, AppColors.goldD),
    CycTone.clay => (AppColors.lochiaBg, AppColors.lochia),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: fg)),
  );
}

/// .cy-cta — tam genişlik büyük buton (rose / ghost / clay)
Widget cycCta(BuildContext c, String label,
    {required VoidCallback onTap,
    bool ghost = false,
    Color? color,
    IconData? icon}) {
  final base = color ?? AppColors.rose;
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: ghost ? Theme.of(c).colorScheme.surface : base,
        borderRadius: BorderRadius.circular(20),
        border: ghost ? Border.all(color: AppColors.line, width: 1.5) : null,
        boxShadow: ghost
            ? AppColors.smallShadow
            : [BoxShadow(color: base.withValues(alpha: 0.30), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: ghost ? AppColors.roseD : Colors.white),
          const SizedBox(width: 9),
        ],
        Text(label,
            style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: ghost ? AppColors.roseD : Colors.white)),
      ]),
    ),
  );
}

/// .cy-act — küçük satır-içi blush aksiyon
Widget cycAct(String label, {required VoidCallback onTap, IconData? icon}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
            color: AppColors.roseBg, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.roseD),
            const SizedBox(width: 7),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.roseD)),
        ]),
      ),
    );

/// .cy-card içi "Mini" insight kartı (label + ikon + büyük değer)
Widget cycMini(BuildContext c,
    {required String label,
    required String value,
    Widget? icon,
    Color? valueColor}) {
  return Expanded(
    child: cycCard(c,
        soft: true,
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text(label.toUpperCaseTr(),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      color: AppColors.muted)),
            ),
            ?icon,
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: valueColor ?? AppColors.ink,
                  height: 1)),
        ])),
  );
}

/// .cy-stat — 3'lü istatistik kartı
Widget cycStat(BuildContext c, String n, String unit, String label) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 13),
      decoration: BoxDecoration(
          color: Theme.of(c).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppColors.smallShadow),
      child: Column(children: [
        Text.rich(TextSpan(
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1),
          children: [
            TextSpan(text: n),
            if (unit.isNotEmpty)
              TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.muted)),
          ],
        )),
        const SizedBox(height: 7),
        Text(label.toUpperCaseTr(),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppColors.muted)),
      ]),
    ),
  );
}

/// .cy-chip — belirti çipi (seçili/değil)
Widget cycChip(String text, {bool on = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: on ? AppColors.roseBg : AppColors.cream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? AppColors.rose : AppColors.line, width: 1.5),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: on ? AppColors.roseD : AppColors.muted)),
    );

/// "Bloom" başlık (serif yerine Nunito w900)
TextStyle cycTitleStyle({double size = 19, Color? color}) => TextStyle(
    fontSize: size, fontWeight: FontWeight.w900, color: color ?? AppColors.ink, height: 1.05);
