import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/cycle_repository.dart';
import '../../models/cycle.dart';
import 'cycle_loss.dart';

/// Yaşam-döngüsü (Flo-tarzı) mod yönetimi — tek merkez.
/// Adet ↔ TTC ↔ gebelik ↔ postpartum ↔ kayıp; tek çapa = son adet (LMP).
///
/// Kullanıcının doğrudan seçebildiği modlar: tracking, ttc, pregnant.
/// postpartum (doğum) ve loss (kayıp) olay-tetikli geçişlerdir (bkz akışlar).

/// Modun kullanıcıya görünen meta verisi.
class CycleModeMeta {
  final String title;
  final String desc;
  final IconData icon;
  final Color color;
  const CycleModeMeta(this.title, this.desc, this.icon, this.color);
}

CycleModeMeta cycleModeMeta(CycleLifecycleMode m) => switch (m) {
      CycleLifecycleMode.tracking => CycleModeMeta(
          tr('Adet takibi'),
          tr('Döngünü ve adetini izle'),
          Icons.calendar_month_rounded,
          AppColors.rose),
      CycleLifecycleMode.ttc => CycleModeMeta(
          tr('Gebe kalmaya çalışıyorum'),
          tr('Ovülasyon ve doğurgan pencereni takip et'),
          Icons.spa_rounded,
          AppColors.sageD),
      CycleLifecycleMode.pregnant => CycleModeMeta(
          tr('Hamileyim'),
          tr('Gebeliğini hafta hafta takip et'),
          Icons.pregnant_woman_rounded,
          AppColors.coralDd),
      CycleLifecycleMode.postpartum => CycleModeMeta(
          tr('Doğum sonrası'),
          tr('Loşia ve ilk adetin dönüşü'),
          Icons.child_care_rounded,
          AppColors.coralDd),
      CycleLifecycleMode.loss => CycleModeMeta(
          tr('İyileşme'),
          tr('Kendine zaman tanı'),
          Icons.favorite_rounded,
          AppColors.muted),
    };

/// Kullanıcının ayarlardan/ana ekrandan seçebildiği hedef modlar.
const selectableModes = [
  CycleLifecycleMode.tracking,
  CycleLifecycleMode.ttc,
  CycleLifecycleMode.pregnant,
];

/// Basit mod değişimi (tracking ↔ ttc) — yalnız bayrağı yazar.
/// ttc'ye geçişte ttcStartedAt damgalanır. pregnant/loss ayrı akışlarla yönetilir.
Future<void> setCycleLifecycleMode(
  WidgetRef ref,
  CycleLifecycleMode mode, {
  DateTime? ttcStartedAt,
}) async {
  final repo = ref.read(cycleRepositoryProvider);
  final fields = <String, dynamic>{
    'lifecycle_mode': mode.name,
    // tracking/ttc doğurganlık tahminini gösterir → gizleme kalkar.
    'predictions_hidden': false,
  };
  if (mode == CycleLifecycleMode.ttc && ttcStartedAt != null) {
    fields['ttc_started_at'] =
        '${ttcStartedAt.year.toString().padLeft(4, '0')}-'
        '${ttcStartedAt.month.toString().padLeft(2, '0')}-'
        '${ttcStartedAt.day.toString().padLeft(2, '0')}';
  }
  await repo.patchSettings(fields);
  ref.invalidate(cycleSettingsProvider);
}

/// Ayarlar/ana ekranda gösterilen mod seçici — "Hedefim" (Flo pariteti).
/// [onPregnant] "Hamileyim" seçilince gebelik köprüsünü tetikler (F4).
class CycleModeSwitcher extends ConsumerWidget {
  final CycleSettings settings;
  final VoidCallback onPregnant;
  const CycleModeSwitcher(
      {super.key, required this.settings, required this.onPregnant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = settings.lifecycleMode;
    return Column(
      children: [
        for (final m in selectableModes) ...[
          if (m != selectableModes.first) const SizedBox(height: 8),
          _tile(context, ref, m, active == m),
        ],
        // Kayıp/postpartum aktifse ayrıca göster (bilgi amaçlı, seçilemez satır).
        if (active == CycleLifecycleMode.postpartum ||
            active == CycleLifecycleMode.loss) ...[
          const SizedBox(height: 8),
          _tile(context, ref, active, true, readOnly: true),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, CycleLifecycleMode m,
      bool on,
      {bool readOnly = false}) {
    final meta = cycleModeMeta(m);
    return GestureDetector(
      onTap: readOnly ? null : () => _select(context, ref, m),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: on ? meta.color.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: on ? meta.color : AppColors.line, width: on ? 2 : 1.4),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.14),
                shape: BoxShape.circle),
            child: Icon(meta.icon, size: 21, color: meta.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta.title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w900)),
                Text(meta.desc,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted)),
              ],
            ),
          ),
          if (on)
            Icon(Icons.check_circle_rounded, size: 22, color: meta.color),
        ]),
      ),
    );
  }

  Future<void> _select(
      BuildContext context, WidgetRef ref, CycleLifecycleMode m) async {
    if (m == settings.lifecycleMode) return;
    // Gebelikten çıkış TEK kapıdan geçer (doğum/kayıp/takibe dön akışı) —
    // doğrudan tracking/ttc yazmak gebelik bebeğini yetim bırakır (Baby
    // expecting kalır, adet ekranı takip gösterir → tutarsız çift durum).
    if (settings.lifecycleMode == CycleLifecycleMode.pregnant) {
      await showCycleLossOrEnd(context, ref, settings);
      return;
    }
    if (m == CycleLifecycleMode.pregnant) {
      onPregnant();
      return;
    }
    try {
      await setCycleLifecycleMode(ref, m,
          ttcStartedAt:
              m == CycleLifecycleMode.ttc ? DateTime.now() : null);
      if (context.mounted) {
        showAdToast(context, trp('{m} moduna geçildi', {'m': cycleModeMeta(m).title}));
      }
    } catch (e) {
      if (context.mounted) showAdError(context, apiErrorText(e));
    }
  }
}
