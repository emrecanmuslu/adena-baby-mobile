import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/tour_cache.dart';
import 'coach_tour.dart';
import 'i18n.dart';
import 'modal_gate.dart';

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
List<CoachStep>? tourFor(String key) => switch (key) {
      // Spotlight turu (design/Adena Baby App/Tasarimlar/Tanıtım Turu).
      'home' => [
          CoachStep(tr('Tek dokunuşla kaydet'),
              tr('Beslenme, bez ya da uyku: karta dokun, saati ayarla, kaydet.'),
              [CoachKeys.quick]),
          CoachStep(tr('Tüm kayıtlar burada'),
              tr('Ölçüm, ateş, ilaç, anı… Ortadaki + ile her türü ekleyebilirsin.'),
              [CoachKeys.plus]),
          CoachStep(tr('Gününü bir bakışta gör'),
              tr('Son aktiviteler ve sıradaki beslenme tahmini burada güncellenir.'),
              [CoachKeys.summary]),
          CoachStep(tr('İstediğin gibi düzenle'),
              tr('Kartların yerini kalemle değiştir; ayarlar ve aile paylaşımı profilinde.'),
              [CoachKeys.pencil, CoachKeys.profile]),
        ],
      'timeline' => [
          CoachStep(tr('Günlük Akış'),
              tr('Tüm kayıtlar zaman sırasıyla burada listelenir. Güne göre '
                  'gruplanır; geçmişi kolayca tararsın.')),
          CoachStep(tr('Düzenle & sil'),
              tr('Bir kayda dokununca kimin, ne zaman eklediğini görür; '
                  'düzenleyebilir ya da silebilirsin.')),
        ],
      'charts' => [
          CoachStep(tr('Persentil ne demek?'),
              tr('Renkli bantlar WHO büyüme standartlarıdır; tek nokta değil, '
                  'bebeğin kendi eğrisi önemlidir.'),
              [CoachKeys.chart]),
          CoachStep(tr('Endişelenmeli miyim?'),
              tr('Yüksek ya da düşük persentil tek başına sorun değildir; her bebek '
                  'farklı büyür. Ani sıçrama/düşüşte doktoruna danış. Bu ekran '
                  'rehberdir, tıbbi tanı değildir.'),
              [CoachKeys.chart]),
        ],
      'expecting' => [
          CoachStep(tr('Hafta hafta bebeğin'),
              tr('Görselin üstündeki oklarla günler arasında gez; boyut ve gelişim değişir.'),
              [CoachKeys.fetus]),
          CoachStep(tr('Bu hafta neler oluyor?'),
              tr('Her hafta yeni bir gelişim notu seni bekliyor.'),
              [CoachKeys.week]),
          CoachStep(tr('Doğum günü geldiğinde'),
              tr('Bebeğin doğunca buraya dokun; takip moduna tek adımda geçersin.'),
              [CoachKeys.born]),
        ],
      'milestones' => [
          CoachStep(tr('Gelişim'),
              tr('Yaşa göre beklenen gelişim basamakları. Bebeğin başardıkça '
                  'işaretle; ilerlemeyi gör.')),
          CoachStep(tr('Rehberdir, yarış değil'),
              tr('Bir basamağa dokununca ne anlama geldiğini ve nasıl '
                  'destekleyebileceğini görürsün. Her bebek kendi temposunda gelişir.')),
        ],
      'community' => [
          CoachStep(tr('Topluluk'),
              tr('Diğer ebeveynlere soru sor, deneyim paylaş. Sorular anonim '
                  'sorulabilir; saygılı ol.')),
          CoachStep(tr('Tıbbi tavsiye değil'),
              tr('Topluluk paylaşımları kişisel deneyimdir, tıbbi tavsiye yerine '
                  'geçmez. Sağlık kaygılarında doktoruna danış.')),
        ],
      'vaccines' => [
          CoachStep(tr('Aşı Takvimi'),
              tr('Sağlık Bakanlığı çocukluk dönemi aşı şemasına göre, bebeğinin '
                  'doğum tarihinden otomatik oluşturulur.')),
          CoachStep(tr('Yapıldıkça işaretle'),
              tr('Olan aşıları tarihiyle işaretle; yaklaşanları kaçırmamak için '
                  'hatırlatıcı kurabilirsin. Kesin program için doktoruna danış.')),
        ],
      _ => null,
    };

/// Bir ekranı sarmalayıp ilk açılışta (görülmemişse) turunu gösteren widget.
/// Kullanım: `TourMount(tourKey: 'charts', child: ChartsView(...))`.
class TourMount extends ConsumerStatefulWidget {
  final String tourKey;
  final Widget child;

  /// Son adımın ana butonu (varsayılan "Bitti") ve ona basılınca yapılacak iş.
  final String? finalLabel;
  final VoidCallback? onFinal;
  const TourMount(
      {super.key,
      required this.tourKey,
      required this.child,
      this.finalLabel,
      this.onFinal});

  @override
  ConsumerState<TourMount> createState() => _TourMountState();
}

class _TourMountState extends ConsumerState<TourMount> {
  bool _showing = false; // dialog açık mı (çift tetiklemeyi önler)

  @override
  void initState() {
    super.initState();
    // Öncelikli modal (karşılama paywall'ı) kapıyı bırakınca turu tekrar dene.
    ModalGate.listenable.addListener(_onGateChanged);
  }

  @override
  void dispose() {
    ModalGate.listenable.removeListener(_onGateChanged);
    super.dispose();
  }

  void _onGateChanged() {
    if (!mounted || ModalGate.isBlocked) return;
    // Kapı çoğu zaman bir ekranın dispose'unda bırakılır (Premium Karşılama
    // kapanınca) — o an widget ağacı kilitli, setState etkisiz kalır ve tur o
    // oturumda hiç açılmazdı. Yeniden çizimi bir sonraki mikro-göreve ertele.
    scheduleMicrotask(() {
      if (mounted && !ModalGate.isBlocked) setState(() {});
    });
  }

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
    // ModalGate: öncelikli bir modal (karşılama paywall'ı) sırada/açıkken tur
    // ERTELENİR — markSeen çağrılmaz, kapı açılınca _onGateChanged tekrar dener.
    if (!seen && !_showing && !ModalGate.isBlocked && steps != null && steps.isNotEmpty) {
      _showing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Kapı build ile bu kare arasında tutulmuş olabilir → son bir kontrol.
        if (!mounted || ModalGate.isBlocked) {
          if (mounted) setState(() => _showing = false);
          return;
        }
        await _showTour(context, ref, widget.tourKey, steps,
            finalLabel: widget.finalLabel, onFinal: widget.onFinal);
        if (mounted) _showing = false;
      });
    }
    return widget.child;
  }
}

Future<void> _showTour(
    BuildContext context, WidgetRef ref, String key, List<CoachStep> steps,
    {String? finalLabel, VoidCallback? onFinal}) async {
  // Tur açıkken kapıyı tut: ertelenen sistem izin penceresi (bildirim) turun
  // üstüne açılmasın, tur kapanınca sırası gelsin.
  ModalGate.acquire();
  try {
    await showCoachTour(context,
        steps: steps, finalLabel: finalLabel, onFinal: onFinal);
    // Her kapanış yolunda (Bitti / Geç / geri tuşu) görüldü işaretle.
    await ref.read(tourControllerProvider.notifier).markSeen(key);
  } finally {
    ModalGate.release();
  }
}
