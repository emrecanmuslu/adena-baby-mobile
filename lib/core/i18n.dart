import 'dart:async';

import 'package:flutter/foundation.dart';

/// Sunucu-yönetimli çeviri. **Kaynak metin = anahtar** (gettext/OTA mantığı):
/// kodda `tr('Selam Nasılsın?')` yazılır; çeviri yoksa kaynağa (TR) düşülür.
/// Veri burada tutulur; dil/bundle değişince [notifyListeners] ile UI yenilenir.
class I18n extends ChangeNotifier {
  I18n._();
  static final I18n instance = I18n._();

  String _locale = 'tr';
  Map<String, String> _map = const {};

  /// Çevirisi bulunamayan TR metinleri — sunucuya raporlanır (otomatik toplama).
  final Set<String> _missing = {};
  void Function(List<String> sources)? reporter; // veri katmanı set eder
  Timer? _reportTimer;

  String get locale => _locale;

  /// Dil + sözlüğü uygula ve UI'ı yenile.
  void apply(String locale, Map<String, String> map) {
    _locale = locale;
    _map = map;
    notifyListeners();
  }

  /// Çeviri: TR ise kaynağın kendisi; değilse sözlükten, yoksa kaynağa düşer.
  String tr(String source) {
    if (_locale == 'tr') return source;
    final v = _map[source];
    if (v != null && v.isNotEmpty) return v;
    _noteMissing(source);
    return source;
  }

  void _noteMissing(String s) {
    if (reporter == null) return;
    if (_missing.add(s)) {
      _reportTimer?.cancel();
      _reportTimer = Timer(const Duration(seconds: 3), _flush);
    }
  }

  void _flush() {
    if (_missing.isEmpty) return;
    final batch = _missing.toList();
    _missing.clear();
    reporter?.call(batch);
  }
}

/// Global kısayol — her yerden çağrılır.
String tr(String source) => I18n.instance.tr(source);

/// Yer-tutuculu çeviri (interpolasyonlu metinler için). Kaynak anahtarı
/// `'{n} gün sonra'`, args `{'n': n}` → çeviri alınır, sonra `{n}` değerle
/// değiştirilir. (Kaynak=anahtar yöntemi interpolasyonla doğrudan çalışmaz,
/// bu yüzden placeholder konvansiyonu.) İngilizce karşılığı: `'{n} days later'`.
String trp(String source, Map<String, Object?> args) {
  var out = I18n.instance.tr(source);
  args.forEach((k, v) => out = out.replaceAll('{$k}', '${v ?? ''}'));
  return out;
}
