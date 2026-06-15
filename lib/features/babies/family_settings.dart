import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale_util.dart';
import '../../core/units.dart';
import '../../data/baby_repository.dart';
import '../../data/i18n_repository.dart';
import '../../models/feed_reminder.dart';
import '../../models/quiet_hours.dart';
import '../../models/record.dart';
import 'baby_controller.dart';

/// Cihazın bölge (ülke) kodu — ISO2, büyük harf (ör. 'US', 'TR').
final deviceCountryCodeProvider = Provider<String?>(
    (_) => PlatformDispatcher.instance.locale.countryCode?.toUpperCase());

/// Bölge imperial birim mi — önce sunucu Country tablosundan (cihaz ülkesine
/// göre), yüklenene/eşleşmeyene kadar cihaz heuristiğine (US/LR/MM) düşer.
final regionImperialProvider = Provider<bool>((ref) {
  final cc = ref.watch(deviceCountryCodeProvider);
  final countries = ref.watch(countriesProvider).asData?.value;
  if (countries != null && cc != null) {
    for (final c in countries) {
      if (c.code == cc) return c.usesImperial;
    }
  }
  return deviceUsesImperial();
});


/// Aktif bebeğin aile ayarları (units, enabled_types, …) — sunucudan.
final familySettingsProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, babyId) => ref.watch(babyRepositoryProvider).familySettings(babyId),
);

/// Aktif bebeğin birim tercihleri. Aile birim seçmemişse (boş) bölge (ülke)
/// varsayılanına düşer: Country tablosundan imperial/metrik, o yüklenene kadar
/// cihaz heuristiği. Açık seçilen birimler her zaman korunur.
final activeUnitsProvider = Provider<Units>((ref) {
  final imperial = ref.watch(regionImperialProvider);
  final region = imperial
      ? const Units(volume: 'oz', weight: 'lb', length: 'in', temp: 'F')
      : const Units();
  final baby = ref.watch(activeBabyProvider);
  if (baby == null) return region;
  final fs = ref.watch(familySettingsProvider(baby.id)).asData?.value;
  final m = fs?['units'] as Map<String, dynamic>?;
  return Units(
    volume: m?['volume'] as String? ?? region.volume,
    weight: m?['weight'] as String? ?? region.weight,
    length: m?['length'] as String? ?? region.length,
    temp: m?['temp'] as String? ?? region.temp,
  );
});

/// Birim tercihlerini günceller (tüm units sözlüğünü gönderir) ve önbelleği tazeler.
Future<void> updateUnits(WidgetRef ref, String babyId, Units units) async {
  await ref
      .read(babyRepositoryProvider)
      .updateFamilySettings(babyId, {'units': units.toMap()});
  ref.invalidate(familySettingsProvider(babyId));
}

/// Aktif bebeğin beslenme hatırlatıcı ayarı (yüklenene kadar varsayılan/kapalı).
/// Backend FamilySettings.feed_reminder JSON alanında tutulur.
final feedReminderProvider = Provider.family<FeedReminderConfig, String>((ref, babyId) {
  final fs = ref.watch(familySettingsProvider(babyId)).asData?.value;
  final feed = fs?['feed_reminder'];
  return FeedReminderConfig.fromMap(
      feed is Map ? Map<String, dynamic>.from(feed) : null);
});

/// Beslenme hatırlatıcı ayarını günceller ve önbelleği tazeler.
Future<void> updateFeedReminder(
    WidgetRef ref, String babyId, FeedReminderConfig cfg) async {
  await ref
      .read(babyRepositoryProvider)
      .updateFamilySettings(babyId, {'feed_reminder': cfg.toMap()});
  ref.invalidate(familySettingsProvider(babyId));
}

/// Aktif bebeğin sessiz saat ayarı (yüklenene kadar varsayılan/kapalı).
/// Backend FamilySettings.quiet_hours JSON alanında tutulur.
final quietHoursProvider = Provider.family<QuietHours, String>((ref, babyId) {
  final fs = ref.watch(familySettingsProvider(babyId)).asData?.value;
  final q = fs?['quiet_hours'];
  return QuietHours.fromMap(q is Map ? Map<String, dynamic>.from(q) : null);
});

/// Sessiz saat ayarını günceller ve önbelleği tazeler.
Future<void> updateQuietHours(WidgetRef ref, String babyId, QuietHours q) async {
  await ref
      .read(babyRepositoryProvider)
      .updateFamilySettings(babyId, {'quiet_hours': q.toMap()});
  ref.invalidate(familySettingsProvider(babyId));
}

/// Config + kayıtlardan bir sonraki beslenme zamanını kestirir (null = veri yok).
/// Son (baz türü) beslenmesi + sabit aralık. Süren emzirme çapayı oluşturmaz.
DateTime? nextFeedEstimate(FeedReminderConfig cfg, List<Record> records) {
  bool matches(Record r) {
    if (r.type != RecordType.feed || r.isOngoingBreast) return false;
    return switch (cfg.baseType) {
      'breast' => r.data['sub'] == 'breast',
      'formula' => r.data['sub'] == 'formula',
      _ => true,
    };
  }

  final feeds = records.where(matches).toList()
    ..sort((a, b) => b.ts.compareTo(a.ts));
  if (feeds.isEmpty) return null;
  return feeds.first.ts.add(Duration(minutes: cfg.intervalMin));
}
