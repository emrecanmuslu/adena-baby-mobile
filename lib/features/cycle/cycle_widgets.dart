import 'package:flutter/material.dart';

import '../../core/ad_widgets.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/cycle.dart';
import 'cycle_engine.dart';

// ── Akış (flow) renk + etiket — design ScrCycleEntry swatch'ları ───────────
Color flowColor(FlowLevel f) => switch (f) {
      FlowLevel.none => AppColors.line2,
      FlowLevel.spotting => const Color(0xFFFFB8C8),
      FlowLevel.light => const Color(0xFFE87A9A),
      FlowLevel.medium => AppColors.rose,
      FlowLevel.heavy => AppColors.roseD,
    };

String flowLabel(FlowLevel f) => switch (f) {
      FlowLevel.none => tr('Yok'),
      FlowLevel.spotting => tr('Lekelenme'),
      FlowLevel.light => tr('Hafif'),
      FlowLevel.medium => tr('Orta'),
      FlowLevel.heavy => tr('Yoğun'),
    };

// ── Loşia rengi swatch + etiket — design loşia rehberi ─────────────────────
Color lochiaSwatch(LochiaColor c) => switch (c) {
      LochiaColor.red => const Color(0xFFC0483A),
      LochiaColor.pink => const Color(0xFFD4607A),
      LochiaColor.brown => const Color(0xFF9B6040),
      LochiaColor.yellowWhite => const Color(0xFFD4B07A),
    };

String lochiaLabel(LochiaColor c) => switch (c) {
      LochiaColor.red => tr('Kırmızı'),
      LochiaColor.pink => tr('Pembe'),
      LochiaColor.brown => tr('Kahve'),
      LochiaColor.yellowWhite => tr('Sarı/Beyaz'),
    };

// ── Faz etiketi + kısa açıklama ────────────────────────────────────────────
String phaseLabel(CyclePhase p) => switch (p) {
      CyclePhase.menstrual => tr('Adet Fazı'),
      CyclePhase.follicular => tr('Folliküler Faz'),
      CyclePhase.ovulation => tr('Ovülasyon'),
      CyclePhase.luteal => tr('Luteal Faz'),
    };

// ── Faza göre öz-bakım ipuçları (doğum sonrası bağlamına duyarlı, kısa) ──────
/// Aktif döngü panosundaki "Bu fazda kendine iyi bak" kartı için. Tıbbi tavsiye
/// değil, nazik öz-bakım hatırlatmaları.
({String emoji, String title, List<String> tips}) phaseSelfCare(CyclePhase p) =>
    switch (p) {
      CyclePhase.menstrual => (
          emoji: '🩸',
          title: tr('Adet günleri'),
          tips: [
            tr('Sıcak su torbası ve hafif esneme kramplara iyi gelir.'),
            tr('Demir açısından zengin besinler + bol su.'),
            tr('Dinlenmeye öncelik ver; bebeğin uyuduğunda sen de uzan.'),
          ],
        ),
      CyclePhase.follicular => (
          emoji: '🌱',
          title: tr('Folliküler faz'),
          tips: [
            tr('Enerjin yükselir — kısa bir yürüyüş iyi gelir.'),
            tr('Protein ve sebze ağırlıklı beslen.'),
            tr('Yeni rutinler kurmak için iyi bir dönem.'),
          ],
        ),
      CyclePhase.ovulation => (
          emoji: '🌿',
          title: tr('Ovülasyon dönemi'),
          tips: [
            tr('Doğurganlık penceresindesin — gebelik planın varsa not al.'),
            tr('Bol su iç, hafif tempolu hareket et.'),
          ],
        ),
      CyclePhase.luteal => (
          emoji: '🌙',
          title: tr('Luteal faz'),
          tips: [
            tr('Adet öncesi gerginlik olabilir — kendine şefkatli ol.'),
            tr('Şeker yerine kompleks karbonhidrat tercih et.'),
            tr('Uyku düzenine ve nefes egzersizlerine özen göster.'),
          ],
        ),
    };

// ── Belirti kataloğu (BBT/servikal mukus bilinçli olarak çıkarıldı) ─────────
// Anahtarlar entry.symptoms JSON listesinde saklanır → yeni eklemeler geriye
// dönük uyumludur (şema değişikliği yok).
const List<(String, String)> cycleSymptoms = [
  ('cramp', 'Kramp / ağrı'),
  ('headache', 'Baş ağrısı'),
  ('backache', 'Bel ağrısı'),
  ('bloating', 'Şişkinlik'),
  ('tender', 'Göğüs hassasiyeti'),
  ('acne', 'Akne'),
  ('appetite', 'İştah değişimi'),
  ('nausea', 'Bulantı'),
  ('constipation', 'Kabızlık'),
  ('fatigue', 'Yorgunluk'),
  ('insomnia', 'Uykusuzluk'),
  ('dizziness', 'Baş dönmesi'),
  ('hotflash', 'Ateş basması'),
  ('libido', 'Libido değişimi'),
  ('discharge', 'Akıntı'),
];

/// Doğum sonrası kırmızı bayrak belirtileri (ayrı, vurgulu grup).
const List<(String, String)> cycleRedFlagItems = [
  ('rf_flood', 'Saatte 1+ ped ıslatma'),
  ('rf_clot', 'Büyük pıhtı (limondan büyük)'),
  ('rf_odor_fever', 'Kötü kokulu akıntı + ateş'),
  ('rf_pain', 'Şiddetli karın/kasık ağrısı'),
];

String symptomLabel(String key) {
  for (final s in cycleSymptoms) {
    if (s.$1 == key) return tr(s.$2);
  }
  for (final s in cycleRedFlagItems) {
    if (s.$1 == key) return tr(s.$2);
  }
  return key;
}

// ── Ruh hali skalası (1-5) ─────────────────────────────────────────────────
const moodEmojis = ['😢', '😕', '😐', '🙂', '😊'];
String moodLabel(int m) => switch (m) {
      1 => tr('Çok kötü'),
      2 => tr('Kötü'),
      3 => tr('Normal'),
      4 => tr('İyi'),
      _ => tr('Çok iyi'),
    };

// ── M2 — Bilgi rozeti metinleri (AdInfoDot body'leri) ──────────────────────
class CycleInfo {
  static String get lochiaVsPeriod => tr(
      'Doğumdan sonraki ~6 haftalık kanama loşiadır — iyileşme sürecinin parçası, '
      'adet değildir. Akış zamanla azalırsa loşia; başlayıp koyulaşıp 4–7 gün '
      'sürerse muhtemelen ilk adettir.');
  static String get lam => tr(
      'Düzenli emzirme (LAM — Laktasyonel Amenore) yumurtlamayı baskılayıp adeti '
      'geciktirebilir. Ancak ~%2 başarısızlık riski vardır ve ovülasyon adetten '
      'ÖNCE döner — ilk adeti görmeden gebe kalınabilir.');
  static String get fertileWindow => tr(
      'Doğurganlık penceresi, gebe kalma olasılığının en yüksek olduğu ~6 günlük '
      'dönemdir (ovülasyon ve öncesi). İlk döngülerde — özellikle doğum '
      'sonrasında — tahmindir, kesin değildir.');
  static String get flowAmount => tr(
      'Günlük kanama miktarını seç: Yok · Lekelenme · Hafif · Orta · Yoğun. '
      'Bu, döngü uzunluğunu ve adet süresini hesaplamamızı sağlar.');
  static String get lochiaColorInfo => tr(
      'Lohusalık kanamasının rengi iyileşmenin evresini gösterir: '
      'kırmızı → pembe → kahve → sarı/beyaz. Zamanla açılması beklenir.');
  static String get regularity => tr(
      'İlk döngülerin düzensiz olması — özellikle doğum sonrası dönemde — '
      'tamamen normaldir. 3+ döngü birikince tahminler güvenilirleşir.');
  static String get estimate => tr(
      'Bu bir tahmindir, kesin değildir. Döngüler oturana kadar (özellikle '
      'doğum sonrası) değişkenlik gösterebilir.');
  static String get dialGuide => tr(
      'Halka, döngünü tek bakışta gösterir:\n'
      '• Koyu pembe yay = adet günleri\n'
      '• Yeşil bölge = doğurganlık penceresi\n'
      '• Altın nokta = yumurtlama günü\n'
      '• Beyaz halka = bugünün konumu\n'
      'Ortadaki büyük sayı, döngünün kaçıncı gününde olduğunu söyler. '
      'Tahminler döngülerin biriktikçe güçlenir.');
}

/// "~ Tahmini · değişebilir" rozeti (design EstBadge) — düşük güvenli tahminlerde.
class EstBadge extends StatelessWidget {
  const EstBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.roseBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.rose, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('~ ${tr('Tahmini · değişebilir')}',
              style: TextStyle(
                  fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.roseD)),
        ],
      ),
    );
  }
}

/// M1 — Kırmızı bayrak uyarı modali. Girilen belirtiler riskli eşiklere değince
/// çağrılır. Tanı koymaz; yalnız sağlık profesyoneline yönlendirir.
Future<void> showCycleRedFlag(BuildContext context, List<String> triggered) {
  final items = cycleRedFlagItems
      .where((e) => triggered.contains(e.$1))
      .map((e) => tr(e.$2))
      .toList();
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(20), bottom: Radius.circular(22))),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.coralDd, width: 4)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: AppColors.feverBg,
                      borderRadius: BorderRadius.circular(14)),
                  alignment: Alignment.center,
                  child: const Text('🚨', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Dikkat'),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.coralDd)),
                    Text(tr('Belirti kontrolü'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(tr('Girdiğin bilgiler dikkat gerektiren belirtiler içeriyor:'),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: AppColors.ink2)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                  color: AppColors.feverBg,
                  borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('•  ',
                              style: TextStyle(
                                  color: AppColors.coralDd,
                                  fontWeight: FontWeight.w900)),
                          Expanded(
                            child: Text(s,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    height: 1.4,
                                    color: AppColors.ink2)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(tr('Bir sağlık profesyoneline danışmanı öneririz.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.5,
                    color: AppColors.ink2)),
            const SizedBox(height: 14),
            AdSaveButton(
                label: tr('Anladım'),
                color: AppColors.coralDd,
                onTap: () => Navigator.pop(ctx)),
            const SizedBox(height: 10),
            Center(
              child: Text(tr('Bu bir tanı değil — yalnızca yönlendirmedir.'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
            ),
          ],
        ),
      ),
    ),
  );
}
