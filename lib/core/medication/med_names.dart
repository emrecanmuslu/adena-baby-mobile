/// İlaç planı adı katlaması — bebek başına ad tekilliği (M7) ve kimliksiz eski
/// kayıtların plana eşlenmesi için ORTAK anahtar. Backend karşılığı:
/// `api/apps/health/med_names.py` (`med_name_key`) — ikisi BİREBİR aynı kural.
///
/// Kural: kırp → boşlukları teke indir → Türkçe/İngilizce i varyantlarını
/// (İ, I, ı, i) tek 'i'ye katla → küçük harf. "İlaç", "ILAÇ", "ılaç" aynı
/// anahtar; "IBUPROFEN" ile "ibuprofen" de aynı.
/// Plan adının en çok uzunluğu — sunucu `MedicationPlan.name` (max_length 120)
/// ile aynı (V8: daha uzun ad sunucuda kesilip ek çakışmasına yol açıyordu).
const kMedPlanNameMax = 120;

/// V26: backend `med_names._WS_CHARS` ile AYNI açık boşluk kümesi (Dart ve
/// Python `\s` tanımları farklı).
final _ws = RegExp('[\t\n\x0B\x0C\r \u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005'
    '\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000\uFEFF]+');

String medNameKey(String name) {
  final s = name.replaceAll(_ws, ' ').trimSpaces();
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (c == 'İ' || c == 'I' || c == 'ı') {
      b.write('i');
    } else {
      b.write(c.toLowerCase());
    }
  }
  // "İ" bazı yollarda i + birleşik nokta (U+0307) olarak gelir.
  return b.toString().replaceAll('i\u0307', 'i');
}

extension on String {
  /// Yalnız düz boşluğu kırpar (String.trim'in Unicode kümesi değil).
  String trimSpaces() {
    var a = 0, z = length;
    while (a < z && codeUnitAt(a) == 0x20) {
      a++;
    }
    while (z > a && codeUnitAt(z - 1) == 0x20) {
      z--;
    }
    return substring(a, z);
  }
}
