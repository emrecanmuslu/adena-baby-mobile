import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale_util.dart';
import '../../core/units.dart';
import '../../data/baby_repository.dart';
import '../../data/feed_reminder_store.dart';
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

/// Beslenme hatırlatıcı ayarlarının CİHAZ-YEREL durumu (bebek başına). Açılışta
/// yerelden yüklenir; güncelleme YALNIZ yerele yazılır (sunucuya gitmez) → her
/// cihaz kendi hatırlatıcı tercihini tutar (anne 3 saat, baba 2 saat bağımsız).
/// Eskiden bu ayar sunucuda PAYLAŞIMLI tutuluyordu; son yazan herkesinkini ezerdi.
final feedReminderStoreProvider =
    NotifierProvider<FeedReminderNotifier, Map<String, FeedReminderConfig>>(
        FeedReminderNotifier.new);

class FeedReminderNotifier extends Notifier<Map<String, FeedReminderConfig>> {
  /// Yerel depodan ilk yükleme — [seedIfMissing] bunu BEKLER (bkz. aşağıdaki not).
  Future<void>? _loading;

  @override
  Map<String, FeedReminderConfig> build() {
    _loading = _load();
    return const {};
  }

  Future<void> _load() async {
    state = await FeedReminderStore().readAll();
  }

  Future<void> set(String babyId, FeedReminderConfig cfg) async {
    state = {...state, babyId: cfg};
    await FeedReminderStore().write(babyId, cfg);
  }

  /// Eski PAYLAŞIMLI sunucu değerini yerele BİR KEZ tohumlar — yalnız bu bebek
  /// için yerelde gerçekten kayıt yoksa.
  ///
  /// ⚠️ Çağıran taraf `state.containsKey` ile kontrol EDEMEZ: `build()` sırasında
  /// state boş `{}` olur ve `_load()` asenkron biter. Çağıran ilk build'de kontrol
  /// edince "yerelde kayıt yok" sanıp tohumu yazıyor ve **cihazın kendi ayarını
  /// sunucudaki bayat değerle diskte eziyordu** (bellekteki değer doğru kaldığı
  /// için sorun ancak bir sonraki açılışta ortaya çıkıyordu). Kontrol bu yüzden
  /// yüklemeyi bekleyerek BURADA yapılır.
  Future<void> seedIfMissing(String babyId, FeedReminderConfig fromServer) async {
    await _loading;
    if (state.containsKey(babyId)) return;
    await set(babyId, fromServer);
  }
}

/// Aktif bebeğin beslenme hatırlatıcı ayarı — CİHAZ-YEREL. Yerelde kayıt yoksa
/// (yeni kurulum veya bu özelliği güncellemeden önceki kullanıcı) eski PAYLAŞIMLI
/// sunucu değerinden bir kereye mahsus tohumlanır → mevcut kullanıcılar sıfırlanmaz.
/// Kullanıcı ayarı bir kez kaydedince yerel değer kalıcılaşır ve cihaza özel olur.
final feedReminderProvider = Provider.family<FeedReminderConfig, String>((ref, babyId) {
  final local = ref.watch(feedReminderStoreProvider);
  final cur = local[babyId];
  if (cur != null) return cur;
  // Geçiş tohumu: eski sunucu (paylaşımlı) değeri — yalnız yerel kayıt oluşana dek.
  final fs = ref.watch(familySettingsProvider(babyId)).asData?.value;
  final feed = fs?['feed_reminder'];
  return FeedReminderConfig.fromMap(
      feed is Map ? Map<String, dynamic>.from(feed) : null);
});

/// Beslenme hatırlatıcı ayarını CİHAZA-YEREL kaydeder (sunucuya gitmez).
Future<void> updateFeedReminder(
    WidgetRef ref, String babyId, FeedReminderConfig cfg) async {
  await ref.read(feedReminderStoreProvider.notifier).set(babyId, cfg);
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

/// Son (baz türü) beslenme kaydının zamanı (null = veri yok). nextFeedEstimate'in
/// çapası; widget "son besleme" göstergesi bununla tutarlı olsun diye paylaşılır.
/// Süren emzirme çapa oluşturmaz. CİDDİ şekilde gelecek tarihli kayıt (yanlış
/// girilmiş ya da saat değişimi artefaktı) çapa OLMAZ — yoksa hatırlatıcı günler
/// sonraya kurulur (BULGU-9). Ufak sapmalar (kayıt formunda dakikalar sürebilen
/// manuel saat girişi, cihaz saat farkı) tolere edilir — yoksa "az önce, biraz
/// ileri saatle" eklenen normal bir kayıt çapa OLMAZ ve "sonraki beslenme"
/// eski (artık geçmiş) tahminde donup kalır.
DateTime? lastFeedAt(FeedReminderConfig cfg, List<Record> records) {
  final now = DateTime.now();
  final cutoff = now.add(const Duration(hours: 1));
  bool matches(Record r) {
    if (r.type != RecordType.feed || r.isOngoingBreast) return false;
    if (r.ts.isAfter(cutoff)) return false; // ciddi gelecek tarihli kayıt baz alınmaz
    // Baz türü filtresi TEK yerde ([FeedReminderConfig.matchesBase]): push
    // işleyicisi, arka plan sync ve iOS NSE de aynı kuralı kullanır. Kopyalanan
    // filtreler ayrışınca widget her push'ta ileri, her bg turunda geri zıplıyordu.
    return cfg.matchesBase(r.data['sub'] as String?);
  }

  final feeds = records.where(matches).toList()
    ..sort((a, b) => b.ts.compareTo(a.ts));
  return feeds.isEmpty ? null : feeds.first.ts;
}

/// Config + kayıtlardan bir sonraki beslenme zamanını kestirir (null = veri yok).
/// Son (baz türü) beslenmesi + sabit aralık.
DateTime? nextFeedEstimate(FeedReminderConfig cfg, List<Record> records) {
  final last = lastFeedAt(cfg, records);
  return last?.add(Duration(minutes: cfg.intervalMin));
}
