import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Gelişim / kilometre taşı kaydı (katalogdan üretilir). API §health/milestones.
@immutable
class Milestone {
  final int id;
  final String key;
  final String category; // motor|social|language|cognitive
  final String title;
  final int expectedMonth;
  final bool achieved;
  final DateTime? achievedDate;

  const Milestone({
    required this.id,
    required this.key,
    required this.category,
    required this.title,
    required this.expectedMonth,
    required this.achieved,
    this.achievedDate,
  });

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
        id: json['id'] as int,
        key: json['key'] as String? ?? '',
        category: json['category'] as String? ?? 'motor',
        title: json['title'] as String? ?? '',
        expectedMonth: (json['expected_month'] as num?)?.toInt() ?? 0,
        achieved: json['achieved'] as bool? ?? false,
        achievedDate: json['achieved_date'] != null
            ? DateTime.tryParse(json['achieved_date'] as String)
            : null,
      );
}

/// Kategori görsel meta (renk + etiket). tr() taze değerlensin diye fonksiyon.
class MilestoneCategory {
  final Color color;
  final Color bg;
  final String Function() label;
  const MilestoneCategory(this.color, this.bg, this.label);
}

MilestoneCategory milestoneCategory(String key) => switch (key) {
      'motor' => MilestoneCategory(AppColors.growth, AppColors.growthBg, () => tr('Motor')),
      'social' => MilestoneCategory(AppColors.coral, AppColors.feedBg, () => tr('Sosyal')),
      'language' => MilestoneCategory(AppColors.pump, AppColors.pumpBg, () => tr('Dil')),
      'cognitive' => MilestoneCategory(AppColors.doctor, AppColors.doctorBg, () => tr('Bilişsel')),
      _ => MilestoneCategory(AppColors.med, AppColors.medBg, () => tr('Diğer')),
    };

/// Beklenen ay → okunur etiket ("2. ay", "1 yaş", "1.5 yaş").
String milestoneAgeLabel(int month) {
  if (month < 12) return trp('{n}. ay', {'n': month});
  if (month % 12 == 0) return trp('{n} yaş', {'n': month ~/ 12});
  return trp('{y}.5 yaş', {'y': month ~/ 12});
}
