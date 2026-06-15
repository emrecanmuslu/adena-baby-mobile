import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tour_cache.dart';
import 'ad_widgets.dart';
import 'i18n.dart';
import 'theme.dart';

/// Tek tanıtım kartı (emoji + başlık + kısa açıklama).
class TourStep {
  final String emoji;
  final String title;
  final String body;
  const TourStep(this.emoji, this.title, this.body);
}

/// Ekran turlarının "görüldü" kümesi (kalıcı). null/loading iken tur açılmaz.
class TourController extends AsyncNotifier<Set<String>> {
  final _cache = TourCache();

  @override
  Future<Set<String>> build() => _cache.read();

  bool seen(String key) => state.asData?.value.contains(key) ?? true;

  Future<void> markSeen(String key) async {
    state = AsyncData({...?state.asData?.value, key});
    await _cache.add(key);
  }

  /// Tüm turları sıfırla (ayarlardan "tekrar göster").
  Future<void> resetAll() async {
    await _cache.clear();
    state = const AsyncData(<String>{});
  }
}

final tourControllerProvider =
    AsyncNotifierProvider<TourController, Set<String>>(TourController.new);

/// Ekran anahtarı → kart listesi. tr() ile çağrı anında yerelleştirilir.
List<TourStep>? tourFor(String key) => switch (key) {
      'home' => [
          TourStep('🏠', tr('Ana Sayfa'),
              tr('Bebeğinin günü bir bakışta: son aktiviteler, sıradaki beslenme '
                  'tahmini ve günlük özet hep burada.')),
          TourStep('➕', tr('Hızlı kayıt'),
              tr('Ortadaki + düğmesiyle beslenme, uyku, bez ve diğer kayıtları '
                  'saniyeler içinde ekle.')),
          TourStep('🎨', tr('Sana göre'),
              tr('Hangi kartların ve hızlı girişlerin görüneceğini ayarlardan '
                  'kişiselleştirebilirsin.')),
        ],
      'timeline' => [
          TourStep('📋', tr('Günlük Akış'),
              tr('Tüm kayıtlar zaman sırasıyla burada listelenir. Güne göre '
                  'gruplanır; geçmişi kolayca tararsın.')),
          TourStep('👆', tr('Düzenle & sil'),
              tr('Bir kayda dokununca kimin, ne zaman eklediğini görür; '
                  'düzenleyebilir ya da silebilirsin.')),
        ],
      'charts' => [
          TourStep('📈', tr('Büyüme Grafikleri'),
              tr('Bebeğinin kilo, boy ve baş çevresini zaman içinde izle. '
                  'Ölçüm ekledikçe noktalar eğriye yerleşir.')),
          TourStep('📊', tr('Persentil ne demek?'),
              tr('Persentil, bebeğini aynı yaş ve cinsiyetteki 100 bebekle '
                  'kıyaslar. Örneğin %50, tam ortada demektir: 100 bebekten '
                  '~50\'si daha küçük, ~50\'si daha büyük olur.')),
          TourStep('🌍', tr('Eğriler nereden geliyor?'),
              tr('Renkli bantlar Dünya Sağlık Örgütü\'nün (WHO) sağlıklı büyüme '
                  'standartlarıdır. %15–%85 arası çok geniş bir "normal" aralıktır; '
                  'tek bir nokta değil, bebeğin kendi eğrisini takip etmesi önemlidir.')),
          TourStep('💛', tr('Endişelenmeli miyim?'),
              tr('Yüksek ya da düşük persentil tek başına sorun değildir; her bebek '
                  'farklı büyür. Ani sıçrama/düşüşte doktoruna danış. Bu ekran '
                  'rehberdir, tıbbi tanı değildir.')),
        ],
      'expecting' => [
          TourStep('🤰', tr('Bekleme Odası'),
              tr('Doğuma kalan süreyi, bebeğinin bu haftaki boyutunu ve gelişimini '
                  'takip et.')),
          TourStep('📅', tr('Hafta hafta'),
              tr('Her hafta "neler oluyor?" notuyla bebeğinin gelişimini öğren. '
                  'Bebeğin doğunca tek dokunuşla takip moduna geçersin.')),
        ],
      'discover' => [
          TourStep('✨', tr('Keşfet'),
              tr('Sağlık, topluluk, uzman rehberi ve anılar gibi tüm ek bölümlere '
                  'buradan ulaşırsın.')),
        ],
      'health' => [
          TourStep('❤️', tr('Sağlık'),
              tr('Aşı takvimi, gelişim basamakları, diş çıkarma ve hatırlatıcılar '
                  'tek bir yerde toplanır.')),
          TourStep('🔔', tr('Hatırlatıcılar'),
              tr('Aşı, randevu ve özel hatırlatıcılar kurarak önemli anları '
                  'kaçırma.')),
        ],
      'milestones' => [
          TourStep('🎯', tr('Gelişim'),
              tr('Yaşa göre beklenen gelişim basamakları. Bebeğin başardıkça '
                  'işaretle; ilerlemeyi gör.')),
          TourStep('💡', tr('Rehberdir, yarış değil'),
              tr('Bir basamağa dokununca ne anlama geldiğini ve nasıl '
                  'destekleyebileceğini görürsün. Her bebek kendi temposunda gelişir.')),
        ],
      'teeth' => [
          TourStep('🦷', tr('Diş Gelişimi'),
              tr('Ağız haritasında çıkan dişlere dokunup tarihiyle işaretle. '
                  'Şeftali renkli dişler sırada beklenenlerdir.')),
        ],
      'memories' => [
          TourStep('📸', tr('Anılar'),
              tr('Bebeğinin fotoğraflarını ve özel anlarını kaydet; "ilk"leri '
                  'işaretleyip zaman içinde sakla.')),
        ],
      'community' => [
          TourStep('💬', tr('Topluluk'),
              tr('Diğer ebeveynlere soru sor, deneyim paylaş. Sorular anonim '
                  'sorulabilir; saygılı ol.')),
          TourStep('⚠️', tr('Tıbbi tavsiye değil'),
              tr('Topluluk paylaşımları kişisel deneyimdir, tıbbi tavsiye yerine '
                  'geçmez. Sağlık kaygılarında doktoruna danış.')),
        ],
      'content' => [
          TourStep('📚', tr('Uzman Rehberi'),
              tr('Uyku, beslenme, gelişim ve daha fazlası için uzman onaylı '
                  'rehberler. Bebeğinin yaşına uygun öneriler en üstte.')),
        ],
      'mom' => [
          TourStep('🌸', tr('Anne Takibi'),
              tr('Gebelik sürecinde kilonu, randevularını ve notlarını kaydet. '
                  'Bu alan sana özeldir.')),
        ],
      'vaccines' => [
          TourStep('💉', tr('Aşı Takvimi'),
              tr('Sağlık Bakanlığı çocukluk dönemi aşı şemasına göre, bebeğinin '
                  'doğum tarihinden otomatik oluşturulur.')),
          TourStep('✅', tr('Yapıldıkça işaretle'),
              tr('Olan aşıları tarihiyle işaretle; yaklaşanları kaçırmamak için '
                  'hatırlatıcı kurabilirsin. Kesin program için doktoruna danış.')),
        ],
      'reminders' => [
          TourStep('🔔', tr('Hatırlatıcılar'),
              tr('İlaç, vitamin, randevu ya da istediğin her şey için hatırlatıcı '
                  'kur. Tek seferlik veya her gün tekrarlı olabilir.')),
        ],
      'members' => [
          TourStep('👨‍👩‍👧', tr('Aile & Paylaşım'),
              tr('Eşini ya da bakıcını davet koduyla ekle; bebeği birlikte, aynı '
                  'anda takip edin.')),
          TourStep('🔑', tr('Roller'),
              tr('Ebeveyn kayıt ekler ve düzenler; bakıcı yalnız okur (sınırlı '
                  'yazma). Daveti istediğinde iptal edebilirsin.')),
        ],
      'caregiver' => [
          TourStep('👀', tr('Bakıcı Akışı'),
              tr('Ekibin eklediği kayıtların canlı, salt-okunur akışı. Bebeğe ne '
                  'zaman ne yapıldığını tek bakışta gör.')),
        ],
      'premium' => [
          TourStep('⭐', tr('Adena Premium'),
              tr('Reklamsız kullanım, geniş aile paylaşımı, veri dışa aktarma ve '
                  'sınırsız hatırlatıcı. Çekirdek takip her zaman ücretsiz kalır.')),
        ],
      'babyedit' => [
          TourStep('📝', tr('Bebek Bilgileri'),
              tr('Ad, cinsiyet ve tarihi güncelle. Bekleme modundaysan, bebeğin '
                  'doğunca "Bebeğim doğdu" ile takip moduna geçersin.')),
        ],
      'settings' => [
          TourStep('⚙️', tr('Ayarlar'),
              tr('Paylaşım, görünüm, premium ve hesap ayarların burada. Tanıtım '
                  'turlarını da buradan yeniden başlatabilirsin.')),
        ],
      _ => null,
    };

/// Bir ekranı sarmalayıp ilk açılışta (görülmemişse) turunu gösteren widget.
/// Kullanım: `TourMount(tourKey: 'charts', child: ChartsView(...))`.
class TourMount extends ConsumerStatefulWidget {
  final String tourKey;
  final Widget child;
  const TourMount({super.key, required this.tourKey, required this.child});

  @override
  ConsumerState<TourMount> createState() => _TourMountState();
}

class _TourMountState extends ConsumerState<TourMount> {
  bool _showing = false; // dialog açık mı (çift tetiklemeyi önler)

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(tourControllerProvider).maybeWhen(
          data: (s) => s.contains(widget.tourKey),
          orElse: () => true, // yüklenene kadar açma
        );
    final steps = tourFor(widget.tourKey);
    // Kalıcı latch YOK: sıfırlama sonrası (seen tekrar false) yeniden gösterilebilsin.
    // `seen` markSeen ile true olunca tekrar tetiklenmez; `_showing` aradaki
    // rebuild'lerde ikinci dialogu engeller.
    if (!seen && !_showing && steps != null && steps.isNotEmpty) {
      _showing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showTour(context, ref, widget.tourKey, steps);
        if (mounted) _showing = false;
      });
    }
    return widget.child;
  }
}

Future<void> _showTour(BuildContext context, WidgetRef ref, String key,
    List<TourStep> steps) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => _TourDialog(steps: steps),
  );
  // Her kapanış yolunda (Bitti / Geç / dışarı dokunma) görüldü işaretle.
  await ref.read(tourControllerProvider.notifier).markSeen(key);
}

class _TourDialog extends StatefulWidget {
  final List<TourStep> steps;
  const _TourDialog({required this.steps});

  @override
  State<_TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<_TourDialog> {
  final _pc = PageController();
  int _i = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_i >= widget.steps.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pc.nextPage(
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == widget.steps.length - 1;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppColors.softShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Üst: "Tanıtım" + Geç
            Row(
              children: [
                Text(tr('Tanıtım'),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: AppColors.muted2)),
                const Spacer(),
                if (widget.steps.length > 1)
                  Text('${_i + 1}/${widget.steps.length}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.muted2)),
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(tr('Geç'),
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.coralDark)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 226,
              child: PageView.builder(
                controller: _pc,
                onPageChanged: (v) => setState(() => _i = v),
                itemCount: widget.steps.length,
                itemBuilder: (_, idx) {
                  final s = widget.steps[idx];
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        Text(s.emoji, style: const TextStyle(fontSize: 46)),
                        const SizedBox(height: 14),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 18.5, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 9),
                        Text(s.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                                color: AppColors.muted)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Nokta göstergesi
            if (widget.steps.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var d = 0; d < widget.steps.length; d++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: d == _i ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: d == _i ? AppColors.coral : AppColors.line2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            AdSaveButton(
              label: last ? tr('Anladım 👍') : tr('Devam'),
              color: AppColors.coral,
              onTap: _next,
            ),
          ],
        ),
      ),
    );
  }
}
