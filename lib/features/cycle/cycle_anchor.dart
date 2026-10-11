import '../../models/cycle.dart';

/// İlk-adet çapası (`CycleSettings.firstPeriodDate`) kuralları — SAF, birim testli
/// (BULGULAR.md K6 + D33).
///
/// Politika: çapa `settings`'te saklanan değerdir ve esastır (kurulum sihirbazı
/// kayıt olmadan da verir; motor `computeStatus` onu başlangıç kümesine koyar).
/// Kayıtlar çapayı yalnız iki durumda oynatır, ikisi de aynı adayı kullanır:
///  • düzenleme takviminden kaydederken ([anchorPatchForAdjust]),
///  • çapa gününün adet işareti kalkınca (silme / akış kaldırma / senkronla
///    silinme — `CycleRepository` çağırır).
/// Aday = son sıfırlama olayından (doğum/kayıp) SONRAKİ en eski adet günü;
/// sıfırlama öncesi günler asla çapa olamaz; aday yoksa çapa DEĞİŞTİRİLMEZ.

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Verilen gün, son sıfırlama olayının (doğum/kayıp) gününden SONRA mı?
/// Olay yoksa her gün geçerlidir. Olay günü dahil öncesi geçersizdir (o günkü
/// kanama doğum/kayıp kanamasıdır, adet değil).
bool afterLatestReset(DateTime day, CycleSettings s) {
  final resets = [
    if (s.birthDate != null) _dayOnly(s.birthDate!),
    if (s.lastLossDate != null) _dayOnly(s.lastLossDate!),
  ];
  if (resets.isEmpty) return true;
  final latest = resets.reduce((a, b) => b.isAfter(a) ? b : a);
  return _dayOnly(day).isAfter(latest);
}

/// Adet günleri kümesinden çapa adayı: sıfırlama sonrası en eski gün; yoksa null.
DateTime? anchorCandidate(Iterable<DateTime> periodDays, CycleSettings s) {
  DateTime? best;
  for (final d in periodDays) {
    final day = _dayOnly(d);
    if (!afterLatestReset(day, s)) continue;
    if (best == null || day.isBefore(best)) best = day;
  }
  return best;
}

/// Düzenleme takviminden kaydederken uygulanacak ayar yaması; null → yama yok.
/// `lifecycle_mode` AÇIKÇA mevcut değerle geçirilir: `patchSettings`'in
/// "postpartum/loss'ta çapa null→dolu olunca otomatik tracking" kuralı yalnız
/// mode alanı yamada YOKSA çalışır (saveEntry'nin meşru ilk-adet geçişi bu
/// yüzden etkilenmez); takvimden düzenleme ise mod değiştirmemelidir.
Map<String, dynamic>? anchorPatchForAdjust({
  required Set<DateTime> marked,
  required CycleSettings settings,
}) {
  final candidate = anchorCandidate(marked, settings);
  if (candidate == null) return null;
  final cur = settings.firstPeriodDate;
  if (cur != null && _dayOnly(cur) == candidate) return null;
  return {
    'first_period_date': _iso(candidate),
    'lifecycle_mode': settings.lifecycleMode.name,
  };
}
