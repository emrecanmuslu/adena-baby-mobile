import 'dart:convert';

import 'package:adena_baby/data/feed_reminder_store.dart';
import 'package:adena_baby/features/babies/family_settings.dart';
import 'package:adena_baby/models/feed_reminder.dart';
import 'package:adena_baby/models/record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Beslenme hatırlatıcı aralığı CİHAZ-YERELdir; sunucudaki eski PAYLAŞIMLI değer
/// yalnız "yerelde hiç kayıt yoksa" bir kereye mahsus tohum olarak kullanılır.
///
/// REGRESYON: tohum kontrolü eskiden çağıran tarafta (`_BabyNotifSync.build`)
/// `state.containsKey` ile yapılıyordu. `FeedReminderNotifier.build()` state'i boş
/// `{}` ile döndürüp yerel yüklemeyi ASENKRON yaptığı için ilk build'de kontrol her
/// zaman "yerelde kayıt yok" diyordu → cihazın kendi ayarı sunucudaki bayat değerle
/// DİSKTE eziliyordu. Bellekteki değer doğru kaldığından hata ancak bir sonraki
/// açılışta görünüyordu (uygulama 3 saat gösterirken widget/hatırlatıcı 2 saate
/// kayıyordu). Kontrol artık yüklemeyi bekleyen `seedIfMissing` içinde.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _knownProviderTests();
  _anchorRecordTests();

  String cfgJson({required int intervalMin, String baseType = 'all'}) =>
      jsonEncode(FeedReminderConfig(
              enabled: true, intervalMin: intervalMin, baseType: baseType)
          .toMap());

  group('FeedReminderNotifier.seedIfMissing', () {
    test('yerelde kayıt VAR → tohum ne belleği ne DİSKİ ezer', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.feed_reminder_cfg_baby1':
            cfgJson(intervalMin: 180, baseType: 'formula'),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      // İlk build ile aynı an: store henüz yüklenmemişken tohum denemesi.
      final seeding = c.read(feedReminderStoreProvider.notifier).seedIfMissing(
          'baby1', const FeedReminderConfig(enabled: true, intervalMin: 120));
      await seeding;

      expect(c.read(feedReminderStoreProvider)['baby1']?.intervalMin, 180,
          reason: 'bellekteki cihaz-yerel ayar korunmalı');
      expect(c.read(feedReminderProvider('baby1')).baseType, 'formula');
      final onDisk = await FeedReminderStore().readAll();
      expect(onDisk['baby1']?.intervalMin, 180,
          reason: 'DİSKTEKİ cihaz-yerel ayar sunucu tohumuyla EZİLMEMELİ');
    });

    test('yerelde kayıt YOK → sunucu değeri bir kez tohumlanır', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);

      await c.read(feedReminderStoreProvider.notifier).seedIfMissing(
          'baby2',
          const FeedReminderConfig(
              enabled: true, intervalMin: 240, baseType: 'breast'));

      expect(c.read(feedReminderStoreProvider)['baby2']?.intervalMin, 240);
      final onDisk = await FeedReminderStore().readAll();
      expect(onDisk['baby2']?.intervalMin, 240);
      expect(onDisk['baby2']?.baseType, 'breast');
    });

    test('tekrarlanan tohum çağrıları ilk yereli değiştirmez (idempotent)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(feedReminderStoreProvider.notifier);

      // build() her rebuild'de tohum dener; ilk yazımdan sonrakiler no-op olmalı.
      await n.seedIfMissing(
          'baby3', const FeedReminderConfig(enabled: true, intervalMin: 240));
      await n.seedIfMissing(
          'baby3', const FeedReminderConfig(enabled: true, intervalMin: 120));

      expect(c.read(feedReminderStoreProvider)['baby3']?.intervalMin, 240);
      expect((await FeedReminderStore().readAll())['baby3']?.intervalMin, 240);
    });

    test('kullanıcının kaydettiği ayar tohumu her zaman yener', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(feedReminderStoreProvider.notifier);

      await n.set('baby4',
          const FeedReminderConfig(enabled: true, intervalMin: 180));
      await n.seedIfMissing(
          'baby4', const FeedReminderConfig(enabled: true, intervalMin: 120));

      expect(c.read(feedReminderStoreProvider)['baby4']?.intervalMin, 180);
      expect((await FeedReminderStore().readAll())['baby4']?.intervalMin, 180);
    });
  });
}


/// REGRESYON (2026-09-03): "sonraki beslenme" 3 saat yerine 2 saat.
///
/// Açılışta yerel depo diskten okunana kadar [feedReminderProvider] gerçek ayarı
/// değil VARSAYILANI (kapalı → tahmin 2 saat · tüm türler) döndürüyor. O pencerede
/// ayna yazıcıları (prefs snapshot + App Group `fr_enabled`/`feed_interval`) ve
/// widget publish'i koşarsa, arka plan yolları (FCM push handler, bg sync, iOS NSE)
/// kullanıcının 3 saatlik ayarı yerine 120 dk okur → widget "son beslenme + 2 saat"
/// gösterir. [feedReminderKnownProvider] bu pencereyi kapatır.
void _knownProviderTests() {
  group('feedReminderKnownProvider', () {
    test('yerel yükleme BİTMEDEN ayar "bilinmiyor" sayılır', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.feed_reminder_cfg_baby1':
            jsonEncode(const FeedReminderConfig(
                    enabled: true, intervalMin: 180, baseType: 'formula')
                .toMap()),
      });
      // Geçiş tohumu sunucudan gelir; test drift/ağa gitmesin diye sahtele.
      final c = ProviderContainer(overrides: [
        familySettingsProvider('baby1')
            .overrideWith((ref) async => <String, dynamic>{}),
      ]);
      addTearDown(c.dispose);

      // İlk okuma = ilk build anı: store boş, yükleme asenkron sürüyor.
      expect(c.read(feedReminderKnownProvider('baby1')), isFalse);
      // Bu anda provider VARSAYILANI döndürür — aynaya yazılsaydı 120 dk giderdi.
      expect(c.read(feedReminderProvider('baby1')).intervalMin, 120);

      await c.read(feedReminderStoreProvider.notifier).seedIfMissing(
          'baby1', const FeedReminderConfig());

      expect(c.read(feedReminderKnownProvider('baby1')), isTrue);
      expect(c.read(feedReminderProvider('baby1')).intervalMin, 180,
          reason: 'yükleme bitince cihazın kendi 3 saatlik ayarı');
    });
  });
}

/// REGRESYON: ana sayfa "Sonraki beslenme" kartı `next`'i FİLTRELİ çapadan
/// (son mama) hesaplarken alt satırını/ilerleme çubuğunu FİLTRESİZ son
/// beslenmeden alıyordu → eş anne sütü girince kart "Son 13:00 · 2 saat sonra"
/// diyordu, çapa 12:00'deki mamada olmasına rağmen. [lastFeedRecord] tek kaynak.
void _anchorRecordTests() {
  Record feed(String id, DateTime ts, String sub) => Record(
      id: id, baby: 'b1', type: RecordType.feed, ts: ts, data: {'sub': sub});

  group('lastFeedRecord', () {
    test('baz "mama" iken sonraki ANNE SÜTÜ kaydı çapa olmaz', () {
      final t12 = DateTime.now().subtract(const Duration(hours: 2));
      final t13 = DateTime.now().subtract(const Duration(hours: 1));
      const cfg = FeedReminderConfig(
          enabled: true, intervalMin: 180, baseType: 'formula');
      final recs = [feed('r1', t12, 'formula'), feed('r2', t13, 'breast')];

      final anchor = lastFeedRecord(cfg, recs);
      expect(anchor?.id, 'r1', reason: 'çapa son MAMA kaydı olmalı');
      expect(anchor?.data['sub'], 'formula',
          reason: 'kartın "Son ... (tür)" etiketi de çapadan gelir');
      expect(lastFeedAt(cfg, recs), t12);
      expect(nextFeedEstimate(cfg, recs), t12.add(const Duration(hours: 3)));
    });

    test('baz "hepsi" iken en son beslenme çapadır', () {
      final t12 = DateTime.now().subtract(const Duration(hours: 2));
      final t13 = DateTime.now().subtract(const Duration(hours: 1));
      const cfg = FeedReminderConfig(enabled: true, intervalMin: 180);
      final recs = [feed('r1', t12, 'formula'), feed('r2', t13, 'breast')];
      expect(lastFeedRecord(cfg, recs)?.id, 'r2');
    });
  });
}
