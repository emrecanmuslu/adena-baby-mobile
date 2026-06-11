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
  21: FruitStage('havuç', '🥕', '~26.7 cm · ~360 g'),
  22: FruitStage('kabak', '🥒', '~27.8 cm · ~430 g'),
  23: FruitStage('greyfurt', '🍊', '~28.9 cm · ~500 g'),
  24: FruitStage('mısır koçanı', '🌽', '~30 cm · ~600 g'),
  25: FruitStage('karnabahar', '🥬', '~34.6 cm · ~660 g'),
  26: FruitStage('marul', '🥬', '~35.6 cm · ~760 g'),
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

/// Verilen hafta için boyut sahnesi. Aralık dışında en yakın haftaya düşer.
FruitStage fruitStageFor(int week) {
  final w = week.clamp(4, 40);
  for (var i = w; i >= 4; i--) {
    final f = _fruitByWeek[i];
    if (f != null) return f;
  }
  return _fruitByWeek[4]!;
}

/// Milestone haftalar için kısa gelişim notu; yoksa trimester geneli.
const Map<int, String> _weekNotes = {
  8: 'Minik kollar ve bacaklar belirmeye başladı, kalbi düzenli atıyor. 💛',
  12: 'Tüm temel organlar oluştu; artık hızla büyüme ve olgunlaşma dönemi başlıyor.',
  16: 'Bebeğiniz sesleri duymaya başlıyor ve yüz kasları hareketleniyor.',
  20: 'Yarı yoldasınız! İlk tekmeleri yakında hissedebilirsiniz.',
  24: 'Akciğerler gelişiyor, işitme keskinleşiyor; sesinize tepki verebilir.',
  28: 'Gözleri artık açılıp kapanabiliyor ve ışığa tepki veriyor. Akciğerleri hızla gelişiyor. 💛',
  32: 'Bebeğiniz kilo alıyor, cildi pürüzsüzleşiyor ve uyku-uyanıklık ritmi oturuyor.',
  36: 'Bebeğiniz doğuma hazırlanıyor; çoğu organ olgun, başını aşağı çevirebilir.',
  40: 'Bebeğiniz doğuma tam hazır. Her an kucağınızda olabilir! 🎉',
};

String weeklyNote(int week) {
  for (var i = week; i >= 4; i--) {
    final n = _weekNotes[i];
    if (n != null) return n;
  }
  if (week <= 13) return 'Bebeğiniz hızla gelişiyor; organları ve temel yapıları oluşuyor. 💛';
  if (week <= 27) return 'Bebeğiniz büyüyor ve hareketleniyor; duyuları gelişmeye devam ediyor. 💛';
  return 'Bebeğiniz doğuma hazırlanıyor; her geçen gün güçleniyor. 💛';
}
