import 'package:flutter/foundation.dart';

/// Aşı takvimi kaydı (TR Sağlık Bakanlığı şemasından üretilir). API §health.
@immutable
class Vaccine {
  final int id;
  final String name;
  final DateTime dueDate;
  final bool done;
  final DateTime? doneDate;

  const Vaccine({
    required this.id,
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

  factory Vaccine.fromJson(Map<String, dynamic> json) => Vaccine(
        id: json['id'] as int,
        name: json['vaccine_name'] as String? ?? '',
        dueDate: DateTime.parse(json['due_date'] as String),
        done: json['status'] == 'done',
        doneDate: json['done_date'] != null
            ? DateTime.tryParse(json['done_date'] as String)
            : null,
      );
}
