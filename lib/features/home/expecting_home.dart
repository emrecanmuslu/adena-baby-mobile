import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/age.dart';
import '../../core/config.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/ring.dart';
import '../../core/theme.dart';
import '../../data/pregnancy_repository.dart';
import '../../data/pregnancy_weeks.dart';
import '../../models/baby.dart';
import '../../models/mom_entry.dart';
import '../babies/baby_actions.dart';
import 'mom_tracking_screen.dart';

/// Bekleme (gebelik) modu ana ekran — design ScrWaiting: meyve boyut sahnesi +
/// doğuma kalan gün halkası + haftalık gelişim notu + "doğdu" CTA.
class ExpectingHome extends ConsumerWidget {
  final Baby baby;
  const ExpectingHome({super.key, required this.baby});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = baby.dueDate;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (due == null) {
      return _NoDue(onEdit: () => context.push('/baby-edit'));
    }

    final daysLeft = due.difference(todayDate).inDays;
    // 40 hafta = 280 gün. Paylaşılan saf hesap (bkz core/age.dart).
    final daysPregnant = pregnancyDays(due);
    final weeks = daysPregnant ~/ 7;
    final progress = (daysPregnant / 280).clamp(0.0, 1.0);
    final weeksLeft = (daysLeft / 7).ceil();
    // Gebelik verisi API'den (yüklenene/çevrimdışıyken gömülü tabloya düşer).
    final pw = ref.watch(pregnancyWeeksProvider).asData?.value ??
        PregnancyWeeksData.embedded;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      children: [
        // Gelişim görseli sahnesi (fetus görseli + boyut karşılaştırması)
        _FruitStage(daysPregnant: daysPregnant, data: pw),
        const SizedBox(height: 18),

        // Doğuma kalan halka kartı
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppColors.softShadow,
          ),
          child: Row(
            children: [
              Ring(
                size: 62,
                pct: progress,
                strokeWidth: 6,
                color: AppColors.coralDd,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(daysLeft > 0 ? '$daysLeft' : '0',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: AppColors.coralDd,
                            height: 1)),
                    Text(tr('GÜN'),
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: AppColors.muted,
                            letterSpacing: 0.5)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(daysLeft > 0 ? tr('Doğuma kalan') : tr('Bugünlerde!'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      trp('Tahmini: {due}', {'due': fmtDayMonthYear(due)}) +
                          (daysLeft > 0
                              ? trp(' · ~{w} hafta', {'w': weeksLeft})
                              : ''),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        _sec(tr('Bu hafta neler oluyor?')),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.peachLight,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            pw.noteFor(weeks),
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                height: 1.45),
          ),
        ),

        // Anne takibi (design ScrWaiting) — hızlı ekleme + detay ekranı.
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 22, 3, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(tr('ANNE TAKİBİ'),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.muted,
                        letterSpacing: 0.7)),
              ),
              GestureDetector(
                onTap: () => context.push('/mom'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Tümü'),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.coralDark)),
                    const SizedBox(width: 2),
                    const AdenaIcon('chevR', size: 14, color: AppColors.coralDark),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            _MomQuickBtn(
              icon: 'growth',
              color: AppColors.growth,
              bg: AppColors.growthBg,
              label: tr('Kilo'),
              onTap: () => showMomEntrySheet(context, ref, baby.id, MomKind.weight),
            ),
            const SizedBox(width: 10),
            _MomQuickBtn(
              icon: 'doctor',
              color: AppColors.doctor,
              bg: AppColors.doctorBg,
              label: tr('Randevu'),
              onTap: () =>
                  showMomEntrySheet(context, ref, baby.id, MomKind.appointment),
            ),
            const SizedBox(width: 10),
            _MomQuickBtn(
              icon: 'edit',
              color: AppColors.med,
              bg: AppColors.medBg,
              label: tr('Not'),
              onTap: () => showMomEntrySheet(context, ref, baby.id, MomKind.note),
            ),
          ],
        ),

        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => openBornFlow(context),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.coral,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: Text(tr('🎉  Bebeğim Doğdu'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(tr('Tarihi seç, takip moduna otomatik geçilir.'),
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: () => context.push('/baby-edit'),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(tr('Bilgileri düzenle')),
          style: TextButton.styleFrom(foregroundColor: AppColors.coralDark),
        ),
        const SizedBox(height: 14),
        const AdMedicalNote(),
      ],
    );
  }
}

/// Gelişim görseli sahnesi (design .ad-fruitstage): "X. Hafta Y. gün" rozeti +
/// haftalık 9:16 fetus görseli (API media'dan, kenarları zemine kaynaşacak
/// şekilde yumuşatılmış) + "bir X büyüklüğünde" + ölçü. Yan oklarla ±5 gün
/// ileri/geri gidilebilir; görsel yalnız hafta değişince değişir (gün içinde
/// aynı kalır). "Bugün" dışındaysa dönüş rozeti çıkar.
class _FruitStage extends StatefulWidget {
  /// Bugünkü gebelik yaşı (gün cinsinden, 0–280).
  final int daysPregnant;
  /// Hafta verisi (API/cache/gömülü) — boyut sahnesi buradan okunur.
  final PregnancyWeeksData data;
  const _FruitStage({required this.daysPregnant, required this.data});

  @override
  State<_FruitStage> createState() => _FruitStageState();
}

class _FruitStageState extends State<_FruitStage> {
  // Görselleri olan hafta aralığı (API media/fetus/4..40.png).
  static const int _minWeek = 4;
  static const int _maxWeek = 40;
  // Bugünden en fazla kaç gün ileri/geri gidilebilir.
  static const int _maxDayOffset = 5;

  /// Bugüne göre gün kaydırması (oklarla değişir, ±5). 0 = bugün.
  int _dayOffset = 0;

  int get _viewedDays => (widget.daysPregnant + _dayOffset).clamp(0, 287);
  // Tamamlanan gebelik haftası = obstetrik "X hafta Y gün"in haftası (LMP'den).
  // Görsel/ölçü/etiket hepsi BUNA dayanır (badge ile veri tutarlı olsun diye).
  int get _displayWeek => _viewedDays ~/ 7;
  // Haftanın günü (1–7) — "39. Hafta 1. gün" = 39 hafta 0 gün (39w0d).
  int get _dayInWeek => (_viewedDays % 7) + 1;
  // Görsel haftası — mevcut görsel aralığına kıstırılır.
  int get _imageWeek => _displayWeek.clamp(_minWeek, _maxWeek);

  bool get _isToday => _dayOffset == 0;
  bool get _canPrev => _dayOffset > -_maxDayOffset && _viewedDays > 0;
  bool get _canNext => _dayOffset < _maxDayOffset && _viewedDays < 287;

  void _step(int delta) => setState(
      () => _dayOffset = (_dayOffset + delta).clamp(-_maxDayOffset, _maxDayOffset));

  void _reset() => setState(() => _dayOffset = 0);

  @override
  Widget build(BuildContext context) {
    // Görsel, ölçü ve etiket aynı haftaya (tamamlanan hafta) dayanır.
    final stage = widget.data.stageFor(_displayWeek);
    final imageUrl = '${AppConfig.mediaBaseUrl}/media/fetus/$_imageWeek.png';

    return Column(
      children: [
        // Büyük 9:16 görsel; rozetler ve oklar görselin ÜZERİNDE (overlay).
        LayoutBuilder(
          builder: (context, c) {
            // Yuvarlatılmış köşeli 9:16 hero; yüksekliği makul bir tavanla sınırla.
            var w = c.maxWidth.clamp(0.0, 300.0);
            var h = w * 16 / 9;
            const maxH = 500.0;
            if (h > maxH) {
              h = maxH;
              w = h * 9 / 16;
            }
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: Stack(
                  children: [
                    // Görsel — yuvarlak köşe + yumuşak gölge.
                    Positioned.fill(
                      child: _FetusImage(
                        url: imageUrl,
                        weekKey: _imageWeek,
                        fallbackEmoji: stage.emoji,
                      ),
                    ),

                    // Üst sol: "X. Hafta Y. gün" rozeti.
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _overlayBadge(
                        trp('{w}. Hafta {d}. gün',
                            {'w': _displayWeek, 'd': _dayInWeek}),
                        color: AppColors.coralDd,
                      ),
                    ),

                    // Üst sağ: bugün değilse "Bugüne dön".
                    if (!_isToday)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: GestureDetector(
                          onTap: _reset,
                          child: _overlayBadge(tr('Bugüne dön'),
                              color: AppColors.coralDark),
                        ),
                      ),

                    // Sol/sağ ortada: gün gezinme okları.
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _NavArrow(
                          icon: 'chevL',
                          enabled: _canPrev,
                          onTap: () => _step(-1),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _NavArrow(
                          icon: 'chevR',
                          enabled: _canNext,
                          onTap: () => _step(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
            children: [
              TextSpan(text: tr('Bebeğiniz bir ')),
              TextSpan(
                  text: stage.fruit,
                  style: const TextStyle(color: AppColors.coralDd)),
              TextSpan(text: tr(' büyüklüğünde')),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(stage.size,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
            ),
            const SizedBox(width: 6),
            AdInfoDot(
              title: tr('Boy ve kilo'),
              body: tr(
                  'Buradaki boy ve kilo, o haftadaki bebeklerin ortalamasıdır; '
                  'yalnızca fikir vermek içindir. Her bebek kendine özgüdür ve '
                  'sağlıklı bebekler arasında bile belirgin farklar olabilir; '
                  'gerçek ölçüler bundan az ya da çok olabilir, bu normaldir.\n\n'
                  'İlk haftalarda uzunluk baş–popo (CRL) ölçülür; yaklaşık 20. '
                  'haftadan sonra baş–topuk ölçülür, bu yüzden 20. haftada boyda '
                  'doğal bir sıçrama görürsünüz.\n\n'
                  'Bebeğinizin kendi gelişimini doktorunuzla ve doğumdan sonra '
                  'Grafikler bölümünden takip edebilirsiniz.'),
            ),
          ],
        ),
      ],
    );
  }

  /// Görsel üzerine binen okunaklı rozet — yarı saydam beyaz zemin + küçük gölge.
  Widget _overlayBadge(String text, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: AppColors.smallShadow,
      ),
      child: Text(text,
          style: TextStyle(
              fontWeight: FontWeight.w900, fontSize: 12, color: color)),
    );
  }
}

/// Haftalık fetus görseli — 9:16 dikey oran, yuvarlatılmış köşeler + yumuşak
/// gölge. Hafta değişince çapraz-solma ile geçer. Yüklenemezse emojiye düşer.
class _FetusImage extends StatelessWidget {
  final String url;
  final int weekKey;
  final String fallbackEmoji;
  const _FetusImage(
      {required this.url, required this.weekKey, required this.fallbackEmoji});

  static const double _radius = 26;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: AppColors.softShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: Image.network(
            url,
            key: ValueKey(weekKey),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return ColoredBox(
                color: AppColors.peachLight,
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.coralDd),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stack) => ColoredBox(
              color: AppColors.peachLight,
              child: Center(
                child: Text(fallbackEmoji, style: const TextStyle(fontSize: 72)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gün gezinme oku (±1 gün). Devre dışıyken soluk.
class _NavArrow extends StatelessWidget {
  final String icon;
  final bool enabled;
  final VoidCallback onTap;
  const _NavArrow(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.25,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: AppColors.softShadow,
              color: Theme.of(context).colorScheme.surface,
            ),
            alignment: Alignment.center,
            child: AdenaIcon(icon, size: 18, color: AppColors.coralDark),
          ),
        ),
      ),
    );
  }
}

/// Tahmini doğum tarihi yoksa: nazik bekleme + düzenle CTA.
class _NoDue extends StatelessWidget {
  final VoidCallback onEdit;
  const _NoDue({required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🤰', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(tr('Bebeğinizi bekliyoruz 💛'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              tr('Hafta sayacı ve gelişim takibi için tahmini doğum tarihini ekle.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onEdit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.coral,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              child: Text(tr('Tarihi ekle'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anne takibi hızlı ekleme butonu (design .ad-qbtn).
class _MomQuickBtn extends StatelessWidget {
  final String icon;
  final Color color;
  final Color bg;
  final String label;
  final VoidCallback onTap;
  const _MomQuickBtn(
      {required this.icon,
      required this.color,
      required this.bg,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppColors.softShadow,
          ),
          child: Column(
            children: [
              AdIconChip(icon, color: color, bg: bg, size: 48),
              const SizedBox(height: 9),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bölüm başlığı (design .ad-sec).
Widget _sec(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 20, 3, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: AppColors.muted,
          letterSpacing: 0.7,
        ),
      ),
    );
