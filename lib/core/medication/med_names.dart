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

String medNameKey(String name) {
  final s = name.trim().replaceAll(RegExp(r'\s+'), ' ');
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
  return b.toString().replaceAll('i̇', 'i');
}
