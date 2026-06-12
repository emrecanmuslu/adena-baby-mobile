import '../core/i18n.dart';

/// Süt dişi kaydı (diş çıkarma takibi) — katalogdan üretilir (teeth_catalog.py).
/// API §health/teeth. position = merkezden dışa (1=orta kesici … 5=2. azı).
class Tooth {
  final int id;
  final String key;
  final String jaw; // upper | lower
  final String side; // left | right
  final int position; // 1..5
  final String name; // diş tipi TR adı (sunucudan)
  final int typicalMonth;
  final bool erupted;
  final DateTime? eruptedDate;

  const Tooth({
    required this.id,
    required this.key,
    required this.jaw,
    required this.side,
    required this.position,
    required this.name,
    required this.typicalMonth,
    required this.erupted,
    this.eruptedDate,
  });

  factory Tooth.fromJson(Map<String, dynamic> json) => Tooth(
        id: json['id'] as int,
        key: json['key'] as String? ?? '',
        jaw: json['jaw'] as String? ?? 'upper',
        side: json['side'] as String? ?? 'left',
        position: (json['position'] as num?)?.toInt() ?? 1,
        name: json['name'] as String? ?? '',
        typicalMonth: (json['typical_month'] as num?)?.toInt() ?? 0,
        erupted: json['erupted'] as bool? ?? false,
        eruptedDate: json['erupted_date'] != null
            ? DateTime.tryParse(json['erupted_date'] as String)
            : null,
      );

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
