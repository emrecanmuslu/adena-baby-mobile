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

/// A4 (karar S3) — ACİL kademe: beklemeden acil servis.
const List<(String, String)> cycleRedFlagUrgentItems = [
  ('rf_flood', 'Saatte bir ya da daha sık pedi dolduran kanama'),
  ('rf_clot', 'Büyük pıhtılar'),
  ('rf_faint', 'Yoğun kanamayla birlikte baş dönmesi, bayılma hissi ya da çarpıntı'),
];

/// A4 (karar S3) — AYNI GÜN HEKİM kademesi.
const List<(String, String)> cycleRedFlagSameDayItems = [
  ('rf_fever', '38°C ve üzeri ateş'),
  ('rf_odor', 'Kötü kokulu akıntı'),
  ('rf_pain', 'Şiddetli karın/kasık ağrısı'),
  ('rf_rebleed', 'Azalmış kanamanın yeniden parlak kırmızı ve yoğun hale gelmesi'),
];

/// Kırmızı bayrak belirtileri (kayıt sayfasında ayrı, vurgulu grup).
const List<(String, String)> cycleRedFlagItems = [
  ...cycleRedFlagUrgentItems,
  ...cycleRedFlagSameDayItems,
];

/// Eski sürümlerin anahtarı (yalnız etiket için; yeni girişte sunulmaz).
const List<(String, String)> _legacyRedFlagItems = [
  ('rf_odor_fever', 'Kötü kokulu akıntı + ateş'),
];

String symptomLabel(String key) {
  for (final s in cycleSymptoms) {
    if (s.$1 == key) return tr(s.$2);
  }
  for (final s in [...cycleRedFlagItems, ..._legacyRedFlagItems]) {
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

// ── Sabit sağlık uyarıları (ADET-INCELEME A1) ──────────────────────────────
class CycleTexts {
  /// Olasılık/doğurgan pencere gösterildiği her yerde (A1): tahmin korunma değildir.
  static String get noContraception =>
      tr('Bu bir tahmindir; gebelikten korunma için kullanılamaz.');

  /// Kurulum sonu + Adet ayarları kalıcı satırı (A1).
  static String get notContraceptionMethod => tr(
      'Adet takvimi tahmine dayalıdır ve bir doğum kontrol yöntemi değildir.');

  /// A2: LAM üç koşulu — öneri DEĞİL, bilgilendirme.
  static String get lamConditions => tr(
      'Emzirme, ancak şu üç koşulun hepsi birlikte sağlanıyorsa gebeliğe karşı '
      'geçici koruma sağlayabilir: doğumdan sonraki ilk 6 ay içindesin; bebeğin '
      'yalnız ya da neredeyse yalnız anne sütüyle besleniyor (gece dahil uzun '
      'aralar yok); adetin henüz dönmedi. Koşullardan biri bozulursa bu koruma '
      'kalkar. Korunma yöntemi için doktoruna danış.');

  /// A2: koşullardan biri bozuldu (6 ay / karışık / adet döndü).
  static String get lamNotProtective => tr(
      'Emzirme artık tek başına korunma sağlamaz; korunma gerekiyorsa '
      'doktoruna danış.');

  /// A5 / S4: emzirmeyen lohusa.
  static String get nonBreastfeeding => tr(
      'Emzirmiyorsan adetin genellikle doğumdan sonraki 6–8 hafta içinde döner; '
      'ovülasyon daha erken, 3–4. haftada olabilir. İlk adetini görmeden gebe '
      'kalabilirsin — korunma gerekiyorsa doktoruna danış.');

  /// A5: doğum yapmış herkese (emzirme şartı yok).
  static String get ovulationBeforeFirstPeriod => tr(
      'İlk adetini görmeden de gebe kalabilirsin — ovülasyon adetten önce '
      'olabilir. Korunma gerekiyorsa doktoruna danış.');
}

/// A1 notu — kalkan ikonlu standart kart.
Widget cycNoContraNote(BuildContext context) => cycNoteLite(context,
    icon: Icons.shield_outlined, body: CycleTexts.noContraception);

/// cycle_kit'e bağımlılık yaratmadan sade not kartı (cycNote ile aynı görünüm).
Widget cycNoteLite(BuildContext context,
    {required IconData icon, required String body}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    decoration: BoxDecoration(
        color: AppColors.roseBg, borderRadius: BorderRadius.circular(18)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: AppColors.roseD),
      const SizedBox(width: 11),
      Expanded(
        child: Text(body,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.5,
                color: AppColors.ink2)),
      ),
    ]),
  );
}

// ── M2 — Bilgi rozeti metinleri (AdInfoDot body'leri) ──────────────────────
class CycleInfo {
  static String get lochiaVsPeriod => tr(
      'Doğumdan sonraki kanama loşiadır — iyileşme sürecinin parçası, adet '
      'değildir. Genellikle 4–6 hafta sürer, 8 haftaya uzayabilir. Kanama '
      'kesildikten sonra başlayan ve 4–7 gün süren düzenli bir kanama ilk adetin '
      'olabilir. Yeniden parlak kırmızı ve yoğunlaşan kanamada hekimine başvur.');
  static String get lam => tr(
      'Emzirme yumurtlamayı baskılayıp adeti geciktirebilir. LAM (Laktasyonel '
      'Amenore Yöntemi) ancak şu üç koşul BİRLİKTE varsa gebeliğe karşı geçici '
      'koruma sağlayabilir: doğumdan sonraki ilk 6 ay; yalnız ya da neredeyse '
      'yalnız anne sütü (gece dahil uzun aralar yok); adetin dönmemiş olması. '
      'Biri bozulursa koruma kalkar. Ovülasyon ilk adetten önce olabilir. Korunma '
      'için doktoruna danış.');
  static String get fertileWindow => tr(
      'Doğurganlık penceresi, gebe kalma olasılığının en yüksek olduğu ~6 günlük '
      'dönemdir (ovülasyon ve öncesi). İlk döngülerde — özellikle doğum '
      'sonrasında — tahmindir, kesin değildir.');
  static String get flowAmount => tr(
      'Günlük kanama miktarını seç: Yok · Lekelenme · Hafif · Orta · Yoğun. '
      'Bu, döngü uzunluğunu ve adet süresini hesaplamamızı sağlar.');
  /// A4/C6: kırmızı bayrak kademeleri (kayıt sayfası + loşia ekranı bilgi).
  static String get redFlags => tr(
      'Beklemeden acil servise başvur ya da 112\'yi ara: saatte bir ya da daha '
      'sık pedi dolduran kanama; büyük pıhtılar; yoğun kanamayla birlikte baş '
      'dönmesi, bayılma hissi ya da çarpıntı.\n'
      'Aynı gün bir hekime başvur: 38°C ve üzeri ateş; kötü kokulu akıntı; '
      'şiddetli karın/kasık ağrısı; azalmış kanamanın yeniden parlak kırmızı ve '
      'yoğun hale gelmesi.\n'
      'Bu bir tanı değildir.');
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
  final items = [...cycleRedFlagItems, ..._legacyRedFlagItems]
      .where((e) => triggered.contains(e.$1))
      .map((e) => tr(e.$2))
      .toList();
  // A4 (karar S3): en yüksek kademeye göre yönlendirme.
  final urgent = redFlagLevel(triggered) == RedFlagLevel.urgent;
  final advice = urgent
      ? tr('Beklemeden acil servise başvur ya da 112\'yi ara.')
      : tr('Bugün bir hekime başvurmanı öneririz.');
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
                    Text(urgent ? tr('Acil belirti') : tr('Dikkat'),
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
            Text(advice,
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
