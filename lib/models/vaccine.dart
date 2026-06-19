import 'package:flutter/foundation.dart';

/// Aşı takvimi kaydı — local-first. Katalog (ad + doğumdan ay) içerikten gelir,
/// `dueDate` doğum tarihinden yerelde hesaplanır, durum (done) yerelde tutulur.
/// `key` = durum eşleştirme anahtarı (= aşı adı). API §content/health-catalog.
@immutable
class Vaccine {
  final String key;
  final String name;
  final DateTime dueDate;
  final bool done;
  final DateTime? doneDate;

  const Vaccine({
    required this.key,
    required this.name,
    required this.dueDate,
    required this.done,
    this.doneDate,
  });

  /// Yapılmadı ve tarihi geçmiş mi?
  bool get isOverdue {
    if (done) return false;
    final now = DateTime.now();
    return dueDate.isBefore(DateTime(now.year, now.month, now.day));
  }
}
