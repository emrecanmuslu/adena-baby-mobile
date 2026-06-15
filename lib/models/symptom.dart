import '../core/i18n.dart';

/// Bir belirti (semptom) kataloğu girdisi: kalıcı [key] + emoji + etiket.
/// Record.data['key'] bu anahtarı tutar; etiket tr() ile yerelleştirilir.
class SymptomKind {
  final String key;
  final String emoji;
  const SymptomKind(this.key, this.emoji);

  /// Yerelleştirilmiş okunabilir ad.
  String get label => trSymptom(key);

  /// Evde rahatlatma + ne zaman doktora başvurmalı kısa rehberi (özgün).
  String get info => trSymptomInfo(key);
}

/// Önceden tanımlı bebek/çocuk belirtileri (ateş & ilaç ayrı kayıt tipleridir).
/// Sıra = form ızgarasındaki sıra (en sık görülenler önce).
const kSymptoms = <SymptomKind>[
  SymptomKind('cough', '😷'),
  SymptomKind('runny_nose', '🤧'),
  SymptomKind('congestion', '👃'),
  SymptomKind('sneeze', '💨'),
  SymptomKind('vomit', '🤮'),
  SymptomKind('diarrhea', '💩'),
  SymptomKind('constipation', '🚽'),
  SymptomKind('rash', '🔴'),
  SymptomKind('fussy', '😣'),
  SymptomKind('poor_appetite', '🍽️'),
  SymptomKind('sleep_trouble', '😴'),
  SymptomKind('ear_pain', '👂'),
  SymptomKind('eye_discharge', '👁️'),
  SymptomKind('tummy_ache', '😖'),
];

SymptomKind? symptomByKey(String? key) {
  if (key == null) return null;
  for (final s in kSymptoms) {
    if (s.key == key) return s;
  }
  return null;
}

/// Belirti anahtarının yerelleştirilmiş adı (katalog dışı/eski anahtar → key).
String trSymptom(String key) => switch (key) {
      'cough' => tr('Öksürük'),
      'runny_nose' => tr('Burun akıntısı'),
      'congestion' => tr('Burun tıkanıklığı'),
      'sneeze' => tr('Hapşırma'),
      'vomit' => tr('Kusma'),
      'diarrhea' => tr('İshal'),
      'constipation' => tr('Kabızlık'),
      'rash' => tr('Döküntü / kızarıklık'),
      'fussy' => tr('Huzursuzluk / ağlama'),
      'poor_appetite' => tr('İştahsızlık'),
      'sleep_trouble' => tr('Uyku düzensizliği'),
      'ear_pain' => tr('Kulak ağrısı'),
      'eye_discharge' => tr('Göz akıntısı'),
      'tummy_ache' => tr('Karın ağrısı / gaz'),
      _ => key,
    };

/// Belirti için kısa, özgün bakım + "ne zaman doktora" rehberi. Genel
/// bilgilendirmedir; tıbbi tanı yerine geçmez. Endişe varsa daima doktora danış.
String trSymptomInfo(String key) => switch (key) {
      'cough' => tr('Odayı nemli tut, bol sıvı ver, başını hafif yükselt. '
          '3 aydan küçükse, nefes alırken hırıltı/çekilme varsa, morarma ya da '
          'yüksek ateş eşlik ediyorsa vakit kaybetmeden doktora başvur.'),
      'runny_nose' => tr('Burnu tuzlu su (serum fizyolojik) ile nemlendirip '
          'aspiratörle nazikçe temizle, bol sıvı ver. Akıntı sarı-yeşil ve 10 '
          'günden uzun sürüyorsa veya ateş eklenirse doktora danış.'),
      'congestion' => tr('Serum fizyolojik damla ve nazal aspiratör rahatlatır; '
          'odadaki havayı nemlendir. Tıkanıklık beslenmeyi/uykuyu ciddi '
          'engelliyorsa veya nefes alışı zorlaşıyorsa doktora başvur.'),
      'sneeze' => tr('Tek başına hapşırma çoğunlukla normaldir; bebekler burnunu '
          'böyle temizler. Burun akıntısı, öksürük veya ateş eklenirse ya da '
          'sık tekrarlıyorsa belirtileri birlikte izleyip doktora danış.'),
      'vomit' => tr('Az ve sık sıvı vererek susuz kalmasını önle. Fışkırır '
          'tarzda, safralı (yeşil) ya da kanlı kusma, sürekli kusma, halsizlik '
          'veya ıslak bez azalması varsa acilen doktora başvur.'),
      'diarrhea' => tr('Anne sütüne/sıvıya devam et; susuzluğu önlemek en '
          'önemlisi. Kanlı/mukuslu dışkı, günde çok sayıda sulu dışkı, ateş, '
          'ağız kuruluğu veya halsizlik varsa doktora başvur.'),
      'constipation' => tr('Bacaklarını bisiklet çevirir gibi hareket ettir, '
          'karnına nazik masaj yap; 6 ay üstüyse doktor onayıyla biraz su ver. '
          'Kanlı/sert dışkı, şişkin karın veya şiddetli ağrı varsa doktora danış.'),
      'rash' => tr('Bölgeyi temiz ve kuru tut, tahriş edici ürünlerden kaçın. '
          'Bastırınca solmayan (mor-kırmızı) döküntü, ateşle birlikte yayılan '
          'döküntü, kabarcık veya şişlik varsa hemen doktora başvur.'),
      'fussy' => tr('Açlık, bez, ısı, yorgunluk ve gaz gibi nedenleri sırayla '
          'gözden geçir; ten tene temas ve sallama yatıştırır. Saatlerce dinmeyen '
          'ağlama, ateş ya da beslenmeyi reddetme varsa doktora danış.'),
      'poor_appetite' => tr('Sakin ortamda, zorlamadan dene; hastalık dönemi '
          'iştahı geçici azaltabilir. Birkaç öğün üst üste reddetme, ıslak bez '
          'azalması, halsizlik veya kilo kaybı varsa doktora başvur.'),
      'sleep_trouble' => tr('Tutarlı bir uyku rutini ve sakin, loş bir ortam '
          'kur; aşırı yorgunluk uykuya geçişi zorlaştırır. Ani başlayan, ağrı '
          'veya ateşle birlikte olan uyku bozukluğunda doktora danış.'),
      'ear_pain' => tr('Kulağını çekiştirme, huzursuzluk ve ateş kulak '
          'enfeksiyonunu düşündürür. Kulaktan akıntı, yüksek ateş veya şiddetli '
          'ağrı varsa doktora başvur — kulağa hiçbir şey damlatma/sokma.'),
      'eye_discharge' => tr('Gözü içten dışa, temiz ıslak pamukla nazikçe sil '
          '(her göze ayrı). Yoğun sarı-yeşil akıntı, kızarıklık, şişlik veya '
          'gözü açamama varsa doktora başvur.'),
      'tummy_ache' => tr('Karın masajı ve bacak hareketleriyle gazını çıkarmasına '
          'yardım et, geğirtmeyi ihmal etme. Şiddetli/sürekli ağlama, şiş-sert '
          'karın, kusma veya kanlı dışkı varsa acilen doktora başvur.'),
      _ => tr('Belirtiyi ve seyrini izle. Şiddetliyse, uzun sürüyorsa ya da '
          'bebeğin genel durumu bozuluyorsa doktoruna danış.'),
    };

/// Belirti şiddeti — kayıt: data['severity'].
enum SymptomSeverity {
  mild,
  moderate,
  severe;

  static SymptomSeverity fromString(String? s) =>
      SymptomSeverity.values.firstWhere((e) => e.name == s,
          orElse: () => SymptomSeverity.moderate);

  String get label => switch (this) {
        SymptomSeverity.mild => tr('Hafif'),
        SymptomSeverity.moderate => tr('Orta'),
        SymptomSeverity.severe => tr('Şiddetli'),
      };
}
