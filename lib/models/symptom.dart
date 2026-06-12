import '../core/i18n.dart';

/// Bir belirti (semptom) kataloğu girdisi: kalıcı [key] + emoji + etiket.
/// Record.data['key'] bu anahtarı tutar; etiket tr() ile yerelleştirilir.
class SymptomKind {
  final String key;
  final String emoji;
  const SymptomKind(this.key, this.emoji);

  /// Yerelleştirilmiş okunabilir ad.
  String get label => trSymptom(key);
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
