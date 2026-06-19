import '../core/i18n.dart';

/// Süt dişi kaydı (diş çıkarma takibi) — katalogdan üretilir (teeth_catalog.py).
/// API §health/teeth. position = merkezden dışa (1=orta kesici … 5=2. azı).
class Tooth {
  final String key;
  final String jaw; // upper | lower
  final String side; // left | right
  final int position; // 1..5
  final String name; // diş tipi adı (katalogtan, locale'e göre)
  final int typicalMonth;
  final bool erupted;
  final DateTime? eruptedDate;

  const Tooth({
    required this.key,
    required this.jaw,
    required this.side,
    required this.position,
    required this.name,
    required this.typicalMonth,
    required this.erupted,
    this.eruptedDate,
  });

  bool get isUpper => jaw == 'upper';

  /// "Üst sağ" gibi konum etiketi.
  String get positionLabel {
    final j = isUpper ? tr('Üst') : tr('Alt');
    final s = side == 'right' ? tr('sağ') : tr('sol');
    return '$j $s';
  }

  /// Tipik çıkış aralığı etiketi ("~10. ay").
  String get typicalLabel => trp('~{n}. ay', {'n': typicalMonth});
}
