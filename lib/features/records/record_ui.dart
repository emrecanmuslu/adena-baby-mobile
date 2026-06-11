import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/adena_icons.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/units.dart';
import '../../models/record.dart';

/// Kayıt tiplerinin görsel kimliği (çizgi-ikon/renk/bg/etiket) ve özet metni.
class RecordUi {
  // NOT: renk/etiket her çağrıda TAZE hesaplanır (switch) — `static final` harita
  // tema-duyarlı bg getter'larını ve tr() etiketlerini ilk açılışta DONDURUR
  // (light/dark ve dil değişimini kaçırır). Bu yüzden cache yok.
  static String iconName(RecordType t) => switch (t) {
        RecordType.diaper => 'diaper',
        RecordType.feed => 'feed',
        RecordType.pumping => 'pump',
        RecordType.sleep => 'sleep',
        RecordType.growth => 'growth',
        RecordType.temperature => 'fever',
        RecordType.medication => 'med',
        RecordType.bath => 'bath',
        RecordType.appointment => 'doctor',
      };

  static Color color(RecordType t) => switch (t) {
        RecordType.diaper => AppColors.diaper,
        RecordType.feed => AppColors.feed,
        RecordType.pumping => AppColors.pump,
        RecordType.sleep => AppColors.sleep,
        RecordType.growth => AppColors.growth,
        RecordType.temperature => AppColors.fever,
        RecordType.medication => AppColors.med,
        RecordType.bath => AppColors.bath,
        RecordType.appointment => AppColors.doctor,
      };

  static Color bg(RecordType t) => switch (t) {
        RecordType.diaper => AppColors.diaperBg,
        RecordType.feed => AppColors.feedBg,
        RecordType.pumping => AppColors.pumpBg,
        RecordType.sleep => AppColors.sleepBg,
        RecordType.growth => AppColors.growthBg,
        RecordType.temperature => AppColors.feverBg,
        RecordType.medication => AppColors.medBg,
        RecordType.bath => AppColors.bathBg,
        RecordType.appointment => AppColors.doctorBg,
      };

  static String label(RecordType t) => switch (t) {
        RecordType.diaper => tr('Bez'),
        RecordType.feed => tr('Beslenme'),
        RecordType.pumping => tr('Süt sağma'),
        RecordType.sleep => tr('Uyku'),
        RecordType.growth => tr('Büyüme'),
        RecordType.temperature => tr('Ateş'),
        RecordType.medication => tr('İlaç'),
        RecordType.bath => tr('Banyo'),
        RecordType.appointment => tr('Randevu'),
      };

  /// Kategori çizgi-ikonu.
  static Widget icon(RecordType t, {double size = 22, Color? color}) =>
      AdenaIcon(iconName(t), size: size, color: color ?? RecordUi.color(t));

  /// Renkli yuvarlak-kare kategori rozeti (design CatIcon).
  static Widget chip(RecordType t, {double size = 46, double radius = 14}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg(t),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: AdenaIcon(iconName(t), size: size * 0.5, color: color(t)),
    );
  }

  /// Saat (14:32) — timeline satırı için.
  static String time(DateTime ts) => DateFormat('HH:mm').format(ts);

  /// Kayıt için kısa, okunabilir Türkçe özet. [units] verilirse hacim/ağırlık/uzunluk
  /// kanonik değerden tercih birimine çevrilir.
  static String summary(Record r, [Units units = const Units()]) {
    final d = r.data;
    switch (r.type) {
      case RecordType.diaper:
        final base = switch (d['sub']) {
          'pee' => tr('Çiş'),
          'poo' => tr('Kaka'),
          'poopee' => tr('Karışık'),
          _ => tr('Bez'),
        };
        final stool = d['stool'];
        return stool is String && stool.isNotEmpty ? '$base · $stool' : base;
      case RecordType.feed:
        switch (d['sub']) {
          case 'breast':
            if (d['end_ts'] == null && d.containsKey('start_ts')) {
              return tr('Emziriyor…');
            }
            final l = d['left_min'] is num ? d['left_min'] as num : 0;
            final rt = d['right_min'] is num ? d['right_min'] as num : 0;
            return trp('Anne sütü · {total} dk · Sol {l} / Sağ {r}', {'total': l + rt, 'l': l, 'r': rt});
          case 'formula':
            return trp('Mama · {vol}', {'vol': _vol(d['ml'], units)});
          case 'pumped':
            return trp('Sağılmış süt · {vol}', {'vol': _vol(d['ml'], units)});
          case 'solid':
            final name = d['food_name'] ?? tr('Ek gıda');
            final amt = d['amount'];
            final amtStr = amt is num ? trp('{n} kaşık', {'n': amt}) : amt?.toString();
            return '$name${amtStr != null && amtStr.isNotEmpty ? ' · $amtStr' : ''}';
          default:
            return tr('Beslenme');
        }
      case RecordType.sleep:
        if (d['end_ts'] == null) return tr('Uyuyor…');
        final mins = d['duration'];
        if (mins is num) {
          final h = mins ~/ 60, m = mins % 60;
          return h > 0 ? trp('Uyku · {h} sa {m} dk', {'h': h, 'm': m}) : trp('Uyku · {m} dk', {'m': m});
        }
        return tr('Uyku');
      case RecordType.pumping:
        return trp('Süt sağma · {vol}', {'vol': _vol(d['ml'], units)});
      case RecordType.temperature:
        return trp('Ateş · {v} °{u}', {'v': d['value'] ?? '?', 'u': d['unit'] ?? 'C'});
      case RecordType.growth:
        final parts = <String>[
          if (d['weight'] is num) units.fmtWeight(d['weight'] as num),
          if (d['height'] is num) units.fmtLength(d['height'] as num),
        ];
        return parts.isEmpty ? tr('Büyüme') : trp('Büyüme · {parts}', {'parts': parts.join(' · ')});
      case RecordType.medication:
        return trp('İlaç · {name}', {'name': d['name'] ?? ''});
      case RecordType.bath:
        return tr('Banyo');
      case RecordType.appointment:
        return d['title'] as String? ?? tr('Randevu');
    }
  }

  static String _vol(dynamic ml, Units units) =>
      ml is num ? units.fmtVolume(ml) : '? ${units.volumeLabel}';
}
