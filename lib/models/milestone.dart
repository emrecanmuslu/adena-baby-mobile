import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Gelişim / kilometre taşı kaydı (katalogdan üretilir). API §health/milestones.
@immutable
class Milestone {
  final String key;
  final String category; // motor|social|language|cognitive
  final String title;
  final String description; // basamağın nasıl göründüğü (katalogtan)
  final String tip; // nasıl desteklenebileceği (katalogtan)
  final int expectedMonth;
  final bool achieved;
  final DateTime? achievedDate;

  const Milestone({
    required this.key,
    required this.category,
    required this.title,
    this.description = '',
    this.tip = '',
    required this.expectedMonth,
    required this.achieved,
    this.achievedDate,
  });
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
