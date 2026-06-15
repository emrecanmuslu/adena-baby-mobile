// Gebelik haftası — meyve/sebze boyut karşılaştırması (eğlenceli, yaklaşık) ve
// haftalık gelişim notu. Boyut/ağırlıklar yaygın gebelik rehberi ortalamalarıdır.

class FruitStage {
  final String fruit; // ör. "patlıcan"
  final String emoji;
  final String size; // ör. "~37 cm · ~1.0 kg"
  const FruitStage(this.fruit, this.emoji, this.size);
}

/// Hafta (4–40) → boyut karşılaştırması.
const Map<int, FruitStage> _fruitByWeek = {
  4: FruitStage('haşhaş tohumu', '🌱', '~2 mm'),
  5: FruitStage('susam tohumu', '⚪', '~3 mm'),
  6: FruitStage('mercimek', '🫘', '~5 mm'),
  7: FruitStage('yaban mersini', '🫐', '~1 cm'),
  8: FruitStage('ahududu', '🍓', '~1.6 cm'),
  9: FruitStage('kiraz', '🍒', '~2.3 cm'),
  10: FruitStage('çilek', '🍓', '~3.1 cm'),
  11: FruitStage('incir', '🫛', '~4.1 cm'),
  12: FruitStage('misket limonu', '🍋', '~5.4 cm · ~14 g'),
  13: FruitStage('limon', '🍋', '~7.4 cm · ~23 g'),
  14: FruitStage('şeftali', '🍑', '~8.7 cm · ~43 g'),
  15: FruitStage('elma', '🍎', '~10 cm · ~70 g'),
  16: FruitStage('avokado', '🥑', '~11.6 cm · ~100 g'),
  17: FruitStage('armut', '🍐', '~13 cm · ~140 g'),
  18: FruitStage('dolmalık biber', '🫑', '~14.2 cm · ~190 g'),
  19: FruitStage('mango', '🥭', '~15.3 cm · ~240 g'),
  20: FruitStage('muz', '🍌', '~25.6 cm · ~300 g'),
  21: FruitStage('havuç', '🥕', '~27.4 cm · ~360 g'),
  22: FruitStage('kabak', '🥒', '~29 cm · ~430 g'),
  23: FruitStage('greyfurt', '🍊', '~30.6 cm · ~500 g'),
  24: FruitStage('mısır koçanı', '🌽', '~32.2 cm · ~600 g'),
  25: FruitStage('karnabahar', '🥬', '~33.7 cm · ~660 g'),
  26: FruitStage('marul', '🥬', '~35.1 cm · ~760 g'),
  27: FruitStage('lahana', '🥬', '~36.6 cm · ~875 g'),
  28: FruitStage('patlıcan', '🍆', '~37.6 cm · ~1.0 kg'),
  29: FruitStage('tatlı patates', '🍠', '~38.6 cm · ~1.2 kg'),
  30: FruitStage('lahana', '🥬', '~39.9 cm · ~1.3 kg'),
  31: FruitStage('hindistan cevizi', '🥥', '~41.1 cm · ~1.5 kg'),
  32: FruitStage('balkabağı', '🎃', '~42.4 cm · ~1.7 kg'),
  33: FruitStage('ananas', '🍍', '~43.7 cm · ~1.9 kg'),
  34: FruitStage('kavun', '🍈', '~45 cm · ~2.1 kg'),
  35: FruitStage('bal kavunu', '🍈', '~46.2 cm · ~2.4 kg'),
  36: FruitStage('marul', '🥬', '~47.4 cm · ~2.6 kg'),
  37: FruitStage('pazı', '🥬', '~48.6 cm · ~2.9 kg'),
  38: FruitStage('pırasa', '🥬', '~49.8 cm · ~3.1 kg'),
  39: FruitStage('mini karpuz', '🍉', '~50.7 cm · ~3.3 kg'),
  40: FruitStage('karpuz', '🍉', '~51.2 cm · ~3.5 kg'),
};

/// Gebelik haftası verisi (boyut + not). Gömülü tablo offline fallback'tir;
/// `PregnancyRepository` bunu API'den çekilen/cache'lenen veriyle değiştirir.
class PregnancyWeeksData {
  final Map<int, FruitStage> fruitByWeek;
  final Map<int, String> weekNotes;
  const PregnancyWeeksData(
      {required this.fruitByWeek, required this.weekNotes});

  /// Uygulamaya gömülü varsayılan (her zaman çalışır, internet gerektirmez).
  static const PregnancyWeeksData embedded = PregnancyWeeksData(
      fruitByWeek: _fruitByWeek, weekNotes: _weekNotes);

  /// API yanıtından ([{week, fruit, emoji, size, note}, ...]) veri kur. Eksik
  /// alanlara karşı sağlam; tamamen boşsa gömülüye düşer.
  factory PregnancyWeeksData.fromApi(List<dynamic> items) {
    final fruit = <int, FruitStage>{};
    final notes = <int, String>{};
    for (final e in items) {
      if (e is! Map) continue;
      final w = (e['week'] as num?)?.toInt();
      if (w == null) continue;
      fruit[w] = FruitStage(
        (e['fruit'] as String?) ?? '',
        (e['emoji'] as String?) ?? '',
        (e['size'] as String?) ?? '',
      );
      final note = e['note'] as String?;
      if (note != null && note.isNotEmpty) notes[w] = note;
    }
    return PregnancyWeeksData(
      fruitByWeek: fruit.isEmpty ? _fruitByWeek : fruit,
      weekNotes: notes.isEmpty ? _weekNotes : notes,
    );
  }

  /// Verilen hafta için boyut sahnesi. Aralık dışında en yakın haftaya düşer.
  FruitStage stageFor(int week) {
    final w = week.clamp(4, 40);
    for (var i = w; i >= 4; i--) {
      final f = fruitByWeek[i];
      if (f != null) return f;
    }
    return fruitByWeek[4] ?? _fruitByWeek[4]!;
  }

  /// Verilen hafta için gelişim notu. Eksikse en yakın alttaki nota düşer.
  String noteFor(int week) {
    for (var i = week; i >= 4; i--) {
      final n = weekNotes[i];
      if (n != null) return n;
    }
    if (week <= 13) {
      return 'Bebeğiniz hızla gelişiyor; organları ve temel yapıları oluşuyor. 💛';
    }
    if (week <= 27) {
      return 'Bebeğiniz büyüyor ve hareketleniyor; duyuları gelişmeye devam ediyor. 💛';
    }
    return 'Bebeğiniz doğuma hazırlanıyor; her geçen gün güçleniyor. 💛';
  }
}

/// Verilen hafta için boyut sahnesi (gömülü tablo). Geriye uyumluluk için.
FruitStage fruitStageFor(int week) => PregnancyWeeksData.embedded.stageFor(week);

/// Her gebelik haftası (4–40) için kısa, haftaya özel gelişim notu. Yaklaşık
/// ortalamalardır; her gebelik kendine özgüdür. Eksik haftada en yakın alttaki
/// nota düşer (weeklyNote).
const Map<int, String> _weekNotes = {
  4: 'Minicik embriyo rahme tutundu ve gelişmeye başladı. Bu haftalarda çoğu anne henüz bir şey hissetmez. 💛',
  5: 'Kalbini oluşturacak yapı şekilleniyor, sinir sistemi temeli atılıyor. Boyu yaklaşık bir susam tanesi kadar.',
  6: 'Minik kalbi bu hafta atmaya başlıyor. Yüz hatları ve göz noktaları beliriyor.',
  7: 'Beyin hızla gelişiyor; kol ve bacak tomurcukları küçük kürekçikler gibi uzuyor.',
  8: 'Parmaklar ayrışmaya, minik kollar ve bacaklar bükülmeye başladı. Kalbi düzenli atıyor. 💛',
  9: 'Artık resmen "fetüs". Temel organların hepsi yerli yerinde, minik hareketler başlıyor (henüz hissedilmez).',
  10: 'Hayati organlar çalışmaya başladı. Minicik tırnaklar ve tüy benzeri ilk kıllar oluşuyor.',
  11: 'Bebeğiniz esniyor, gerinip kımıldıyor. Kemikleri sertleşmeye başlıyor.',
  12: 'Tüm temel organlar oluştu; artık hızlı büyüme ve olgunlaşma dönemi başlıyor. İlk trimesterin sonundasınız! 🎉',
  13: 'Parmak izleri belirginleşiyor, ses telleri oluşuyor. Çoğu annede bulantılar hafiflemeye başlar.',
  14: 'Yüz kasları çalışıyor; kaş çatma, gülümseme gibi ifadeler prova ediliyor. İncecik tüyler (lanugo) cildi kaplıyor.',
  15: 'Bebeğiniz ışığı algılayabiliyor, kemikleri güçleniyor. Bacaklar kollardan daha uzun artık.',
  16: 'Bebeğiniz sesleri duymaya başlıyor; yüz kasları hareketleniyor ve göz kırpabiliyor.',
  17: 'Yağ depoları oluşmaya başlıyor; kıkırdak yapısı kemiğe dönüşüyor. Hareketleri güçleniyor.',
  18: 'Kulakları yerine oturdu, sesinizi duyabilir. Yakında ilk tekmeleri hissedebilirsiniz.',
  19: 'Cildi koruyan beyaz tabaka (vernix) oluşuyor. Duyuları — tat, koku, işitme — hızla gelişiyor.',
  20: 'Yarı yoldasınız! İlk tekmeleri hissetmeye başlayabilirsiniz. 💛',
  21: 'Bebeğiniz artık yutkunuyor ve amniyon sıvısını tadıyor. Hareketleri giderek belirginleşiyor.',
  22: 'Yüz hatları net; minik kaşlar ve dudaklar oluştu. Dokunma duyusu gelişiyor, eline yüzüne dokunuyor.',
  23: 'İşitmesi keskinleşiyor; yüksek seslere irkilebilir. Cildi hâlâ buruşuk ama yağlanmaya başlıyor.',
  24: 'Akciğerleri gelişiyor, işitme keskinleşiyor; sesinize tepki verebilir. Yaşayabilirlik eşiğine ulaşıyor.',
  25: 'Burun delikleri açılıyor, el kavrama refleksi güçleniyor. Tatlı tatlı kilo almaya devam ediyor.',
  26: 'Gözleri yakında açılacak; akciğerlerde solunum için gerekli madde üretilmeye başlıyor.',
  27: 'Üçüncü trimesterdesiniz! Beyni hızla gelişiyor, uyku-uyanıklık döngüleri belirginleşiyor.',
  28: 'Gözleri artık açılıp kapanabiliyor ve ışığa tepki veriyor. Hıçkırıklarını hissedebilirsiniz. 💛',
  29: 'Kasları ve akciğerleri olgunlaşıyor; kemikleri kalsiyumla güçleniyor. Tekmeler iyice güçlü.',
  30: 'Beynindeki kıvrımlar oluşuyor, lanugo tüyleri dökülmeye başlıyor. Kendi ısısını düzenlemeyi öğreniyor.',
  31: 'Beş duyusu da çalışıyor. Hareketleri artık bir ritme oturdu; aktif ve sakin saatleri var.',
  32: 'Bebeğiniz kilo alıyor, cildi pürüzsüzleşiyor ve uyku-uyanıklık ritmi oturuyor. Çoğu bebek baş aşağı dönüyor.',
  33: 'Bağışıklık sistemi gelişiyor; bebeğiniz sizden gelen antikorlarla güçleniyor. Kafatası yumuşak kalıyor (doğum için).',
  34: 'Akciğerleri neredeyse hazır. Tırnakları parmak ucuna ulaştı, cildi pembeleşip yumuşuyor.',
  35: 'Yer giderek daralıyor; kıvrılarak rahat pozisyon arıyor. Böbrekleri ve karaciğeri olgunlaştı.',
  36: 'Bebeğiniz doğuma hazırlanıyor; çoğu organ olgun, başını aşağı çevirip leğen kemiğine yerleşiyor.',
  37: 'Artık "erken term" sayılıyor. Tutma refleksi güçlü; akciğerleri ve beyni son rötuşları yapıyor.',
  38: 'Vücudundaki tüyler büyük ölçüde döküldü. Organları dış dünyaya hazır; sadece biraz daha kilo alıyor.',
  39: 'Bebeğiniz tam zamanlı (term) artık. Cildini koruyan tabaka inceldi; her şey doğum için hazır.',
  40: 'Bebeğiniz doğuma tam hazır. Her an kucağınızda olabilir! 🎉',
};

String weeklyNote(int week) => PregnancyWeeksData.embedded.noteFor(week);
