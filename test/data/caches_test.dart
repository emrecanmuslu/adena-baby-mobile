import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/data/locale_cache.dart';
import 'package:adena_baby/data/theme_cache.dart';
import 'package:adena_baby/data/subscription_cache.dart';
import 'package:adena_baby/data/activity_notif_cache.dart';
import 'package:adena_baby/data/feed_reminder_cache.dart';
import 'package:adena_baby/data/feed_input_cache.dart';
import 'package:adena_baby/data/tour_cache.dart';
import 'package:adena_baby/models/quiet_hours.dart';

/// In-memory backing store for the flutter_secure_storage method channel.
/// All cache classes have been migrated to SharedPreferences (NSUserDefaults);
/// `_store` now represents the LEGACY Keychain, so it both (a) backs the
/// one-time Keychain→prefs migration tests and (b) lets us assert nothing new
/// is written to Keychain anymore. Reset in setUp for isolation between tests.
final Map<String, String> _store = {};

void _installSecureStorageMock() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'read':
        return _store[args['key'] as String];
      case 'write':
        _store[args['key'] as String] = args['value'] as String;
        return null;
      case 'delete':
        _store.remove(args['key'] as String);
        return null;
      case 'deleteAll':
        _store.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(_store);
      case 'containsKey':
        return _store.containsKey(args['key'] as String);
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Tüm cache'ler artık SharedPreferences (NSUserDefaults) kullanır; `_store` eski
  // Keychain'i temsil eder → göç (Keychain→prefs) testi de buradan.
  Future<String?> pref(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);
  Future<void> setPref(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  setUp(() {
    _store.clear();
    _installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  group('LocaleCache', () {
    final cache = LocaleCache();

    test('unset → null', () async {
      expect(await cache.read(), isNull);
    });

    test('write → read round-trip', () async {
      await cache.write('tr');
      expect(await cache.read(), 'tr');
      expect(await pref('app_locale'), 'tr');
    });

    test('overwrite replaces value', () async {
      await cache.write('tr');
      await cache.write('en');
      expect(await cache.read(), 'en');
    });

    test('read trims whitespace; whitespace-only → null', () async {
      await setPref('app_locale', '  en  ');
      expect(await cache.read(), 'en');
      await setPref('app_locale', '   ');
      expect(await cache.read(), isNull);
    });

    test('empty string stored → null', () async {
      await setPref('app_locale', '');
      expect(await cache.read(), isNull);
    });

    test('clear removes value', () async {
      await cache.write('en');
      await cache.clear();
      expect(await cache.read(), isNull);
      expect(await pref('app_locale'), isNull);
    });

    test('eski Keychain değeri prefs\'e göç eder ve Keychain temizlenir', () async {
      _store['app_locale'] = 'en'; // eski sürüm Keychain'e yazmıştı
      expect(await cache.read(), 'en'); // göç + okuma
      expect(await pref('app_locale'), 'en'); // prefs'e taşındı
      expect(_store.containsKey('app_locale'), isFalse); // Keychain temizlendi
    });
  });

  // ---------------------------------------------------------------------------
  group('ThemeCache', () {
    final cache = ThemeCache();

    test('unset → ThemeMode.system', () async {
      expect(await cache.read(), ThemeMode.system);
    });

    test('light round-trip (serialized as "light")', () async {
      await cache.write(ThemeMode.light);
      expect(await pref('app_theme_mode'), 'light');
      expect(await cache.read(), ThemeMode.light);
    });

    test('dark round-trip (serialized as "dark")', () async {
      await cache.write(ThemeMode.dark);
      expect(await pref('app_theme_mode'), 'dark');
      expect(await cache.read(), ThemeMode.dark);
    });

    test('system serialized as "auto" and reads back as system', () async {
      await cache.write(ThemeMode.system);
      expect(await pref('app_theme_mode'), 'auto');
      expect(await cache.read(), ThemeMode.system);
    });

    test('unknown stored value → system (default branch)', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'garbage'});
      expect(await cache.read(), ThemeMode.system);
    });

    test('clear removes value → system', () async {
      await cache.write(ThemeMode.dark);
      await cache.clear();
      expect(await cache.read(), ThemeMode.system);
      expect(await pref('app_theme_mode'), isNull);
    });

    test('eski Keychain değeri prefs\'e göç eder ve Keychain temizlenir', () async {
      _store['app_theme_mode'] = 'dark'; // eski sürüm Keychain'e yazmıştı
      expect(await cache.read(), ThemeMode.dark); // göç + okuma
      expect(await pref('app_theme_mode'), 'dark'); // prefs'e taşındı
      expect(_store.containsKey('app_theme_mode'), isFalse); // Keychain temizlendi
    });
  });

  // ---------------------------------------------------------------------------
  group('SubscriptionCache', () {
    final cache = SubscriptionCache();

    test('unset → false', () async {
      expect(await cache.read(), isFalse);
    });

    test('write true → "1" → read true', () async {
      await cache.write(true);
      expect(await pref('sub_is_premium'), '1');
      expect(await cache.read(), isTrue);
    });

    test('write false → "0" → read false', () async {
      await cache.write(false);
      expect(await pref('sub_is_premium'), '0');
      expect(await cache.read(), isFalse);
    });

    test('only exactly "1" reads as true', () async {
      SharedPreferences.setMockInitialValues({'sub_is_premium': 'true'});
      expect(await cache.read(), isFalse);
    });

    test('clear removes value → false', () async {
      await cache.write(true);
      await cache.clear();
      expect(await cache.read(), isFalse);
      expect(await pref('sub_is_premium'), isNull);
    });

    test('eski Keychain "1" prefs\'e göç eder', () async {
      _store['sub_is_premium'] = '1'; // eski sürüm Keychain
      expect(await cache.read(), isTrue);
      expect(await pref('sub_is_premium'), '1');
      expect(_store.containsKey('sub_is_premium'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('ActivityNotifCache', () {
    final cache = ActivityNotifCache();

    test('enabled defaults to true; toggle round-trips', () async {
      // Varsayılan AÇIK: yalnız kullanıcı açıkça kapatınca ('0') kapalı.
      expect(await cache.enabled(), isTrue);
      await cache.setEnabled(true);
      expect(await pref('family_activity_notif_enabled'), '1');
      expect(await cache.enabled(), isTrue);
      await cache.setEnabled(false);
      expect(await pref('family_activity_notif_enabled'), '0');
      expect(await cache.enabled(), isFalse);
    });

    test('lastSeen unset → null', () async {
      expect(await cache.lastSeen('baby1'), isNull);
    });

    test('lastSeen stored as UTC ISO8601 and read back', () async {
      final ts = DateTime(2026, 6, 18, 10, 30); // local
      await cache.setLastSeen('baby1', ts);
      final stored = (await pref('family_activity_seen_baby1'))!;
      // Stored value must be UTC ISO8601.
      expect(stored, ts.toUtc().toIso8601String());
      final back = await cache.lastSeen('baby1');
      expect(back!.toUtc(), ts.toUtc());
    });

    test('lastSeen is per-baby keyed', () async {
      final a = DateTime.utc(2026, 1, 1, 1);
      final b = DateTime.utc(2026, 2, 2, 2);
      await cache.setLastSeen('a', a);
      await cache.setLastSeen('b', b);
      expect((await cache.lastSeen('a'))!.toUtc(), a);
      expect((await cache.lastSeen('b'))!.toUtc(), b);
    });

    test('clearSeen removes only that baby', () async {
      await cache.setLastSeen('a', DateTime.utc(2026, 1, 1));
      await cache.setLastSeen('b', DateTime.utc(2026, 1, 2));
      await cache.clearSeen('a');
      expect(await cache.lastSeen('a'), isNull);
      expect(await cache.lastSeen('b'), isNotNull);
    });

    test('lastSeen with corrupt stored value → null (tryParse)', () async {
      await setPref('family_activity_seen_x', 'not-a-date');
      expect(await cache.lastSeen('x'), isNull);
    });

    test('eski Keychain lastSeen prefs\'e göç eder', () async {
      final ts = DateTime.utc(2026, 3, 3, 3);
      _store['family_activity_seen_m'] = ts.toIso8601String();
      expect((await cache.lastSeen('m'))!.toUtc(), ts);
      expect(await pref('family_activity_seen_m'), ts.toIso8601String());
      expect(_store.containsKey('family_activity_seen_m'), isFalse);
    });

  });

  // ---------------------------------------------------------------------------
  group('FeedReminderCache', () {
    QuietHours quiet() =>
        const QuietHours(enabled: true, startMin: 1320, endMin: 420);

    FeedReminderSnapshot snap({
      int slot = 1,
      bool enabled = true,
      int intervalMin = 180,
      String baseType = 'breast',
      int preMin = 15,
      bool sound = true,
    }) =>
        FeedReminderSnapshot(
          slot: slot,
          enabled: enabled,
          intervalMin: intervalMin,
          baseType: baseType,
          preMin: preMin,
          sound: sound,
          quiet: quiet(),
        );

    // NOTE: FeedReminderCache._lastWritten is a process-static dedup map that
    // cannot be reset without a production hook (none exists). To keep tests
    // isolated we use a UNIQUE babyId per test so no prior write suppresses the
    // current one and no stale storage key collides.
    var n = 0;
    String babyId() => 'baby_${++n}_${DateTime.now().microsecondsSinceEpoch}';

    test('read unset → null', () async {
      final cache = FeedReminderCache();
      expect(await cache.read(babyId()), isNull);
    });

    test('save → read round-trip (all fields incl. nested quiet)', () async {
      final cache = FeedReminderCache();
      final id = babyId();
      await cache.save(id, snap());
      final r = (await cache.read(id))!;
      expect(r.slot, 1);
      expect(r.enabled, isTrue);
      expect(r.intervalMin, 180);
      expect(r.baseType, 'breast');
      expect(r.preMin, 15);
      expect(r.sound, isTrue);
      expect(r.quiet.enabled, isTrue);
      expect(r.quiet.startMin, 1320);
      expect(r.quiet.endMin, 420);
    });

    test('stored value is valid JSON of toJson()', () async {
      final cache = FeedReminderCache();
      final id = babyId();
      final s = snap();
      await cache.save(id, s);
      final raw = (await pref('feed_reminder_snap_$id'))!;
      expect(jsonDecode(raw), s.toJson());
    });

    test('snapshot per-baby keyed', () async {
      final cache = FeedReminderCache();
      final a = babyId(), b = babyId();
      await cache.save(a, snap(slot: 1, baseType: 'breast'));
      await cache.save(b, snap(slot: 2, baseType: 'formula'));
      expect((await cache.read(a))!.slot, 1);
      expect((await cache.read(a))!.baseType, 'breast');
      expect((await cache.read(b))!.slot, 2);
      expect((await cache.read(b))!.baseType, 'formula');
    });

    test('read of corrupt JSON → null', () async {
      final id = babyId();
      await setPref('feed_reminder_snap_$id', '{not json');
      final cache = FeedReminderCache();
      expect(await cache.read(id), isNull);
    });

    test('dedup: identical save twice does not rewrite storage', () async {
      final cache = FeedReminderCache();
      final id = babyId();
      await cache.save(id, snap());
      // Tamper with storage directly; an identical save must NOT overwrite it
      // because content is unchanged (in-memory _lastWritten matches).
      await setPref('feed_reminder_snap_$id', 'TAMPERED');
      await cache.save(id, snap());
      expect(await pref('feed_reminder_snap_$id'), 'TAMPERED');
    });

    test('dedup: changed content does rewrite storage', () async {
      final cache = FeedReminderCache();
      final id = babyId();
      await cache.save(id, snap(intervalMin: 120));
      await cache.save(id, snap(intervalMin: 240));
      expect((await cache.read(id))!.intervalMin, 240);
    });

    test('eski Keychain snapshot prefs\'e göç eder', () async {
      final cache = FeedReminderCache();
      final id = babyId();
      _store['feed_reminder_snap_$id'] = jsonEncode(snap(slot: 7).toJson());
      expect((await cache.read(id))!.slot, 7);
      expect(_store.containsKey('feed_reminder_snap_$id'), isFalse);
    });

    group('FeedReminderSnapshot.fromJson defaults', () {
      test('empty map → documented defaults', () {
        final s = FeedReminderSnapshot.fromJson({});
        expect(s.slot, 0);
        expect(s.enabled, isFalse);
        expect(s.intervalMin, 120);
        expect(s.baseType, 'all');
        expect(s.preMin, 0);
        expect(s.sound, isFalse);
        expect(s.quiet.enabled, isFalse);
      });
    });

    group('FeedReminderSnapshot.matchesBase', () {
      test('breast base only matches breast sub', () {
        final s = snap(baseType: 'breast');
        expect(s.matchesBase('breast'), isTrue);
        expect(s.matchesBase('formula'), isFalse);
        expect(s.matchesBase(null), isFalse);
      });
      test('formula base only matches formula sub', () {
        final s = snap(baseType: 'formula');
        expect(s.matchesBase('formula'), isTrue);
        expect(s.matchesBase('breast'), isFalse);
      });
      test('all base matches anything (incl. null)', () {
        final s = snap(baseType: 'all');
        expect(s.matchesBase('breast'), isTrue);
        expect(s.matchesBase('formula'), isTrue);
        expect(s.matchesBase(null), isTrue);
      });
    });
  });

  // ---------------------------------------------------------------------------
  group('FeedInputCache', () {
    // FeedInputCache keeps a process-static in-memory layer (_mem) and a
    // one-shot _loaded flag, neither resettable without a production hook.
    // clear() wipes _mem and storage, giving us a clean mem layer each test.
    // The _loaded flag stays true after the first ensureLoaded/put in the suite;
    // tests below do not depend on its initial value.
    setUp(() async {
      await FeedInputCache.clear();
    });

    // MUST be the first test in this group: ensureLoaded's storage-read path
    // only runs while the process-static _loaded flag is false (it flips true on
    // the first ensureLoaded/put in the isolate and there is no reset hook). We
    // therefore exercise both hydration (draft recovery from legacy Keychain via
    // migration) and idempotency here, before any other test triggers loading.
    test('ensureLoaded hydrates mem from storage, then is idempotent', () async {
      // Simulate a previous session's persisted draft in legacy Keychain
      // (clear() in setUp wiped _mem but _loaded is still false on this run).
      _store['feed_last_formula'] = jsonEncode({'amount': '120'});
      _store['feed_last_solid'] = jsonEncode({'food': 'avokado'});
      await FeedInputCache.ensureLoaded();
      expect(FeedInputCache.get('formula'), {'amount': '120'});
      expect(FeedInputCache.get('solid'), {'food': 'avokado'});
      expect(FeedInputCache.get('pumped'), isEmpty); // no stored draft

      // Second call must be a no-op: change storage, re-call, mem unchanged.
      _store['feed_last_formula'] = jsonEncode({'amount': '999'});
      await FeedInputCache.ensureLoaded();
      expect(FeedInputCache.get('formula'), {'amount': '120'});
    });

    test('get returns empty for unknown/unset sub', () {
      expect(FeedInputCache.get('formula'), isEmpty);
    });

    test('put → get round-trip (sync read of mem layer)', () async {
      await FeedInputCache.put('formula', {'amount': '90', 'unit': 'ml'});
      expect(FeedInputCache.get('formula'), {'amount': '90', 'unit': 'ml'});
      // Persisted as JSON under feed_last_<sub>.
      expect(jsonDecode((await pref('feed_last_formula'))!),
          {'amount': '90', 'unit': 'ml'});
    });

    test('put ignores breast', () async {
      await FeedInputCache.put('breast', {'side': 'L'});
      expect(FeedInputCache.get('breast'), isEmpty);
      expect(await pref('feed_last_breast'), isNull);
    });

    test('put ignores unknown sub', () async {
      await FeedInputCache.put('bogus', {'x': '1'});
      expect(FeedInputCache.get('bogus'), isEmpty);
      expect(await pref('feed_last_bogus'), isNull);
    });

    test('all three allowed subs persist independently', () async {
      await FeedInputCache.put('formula', {'a': '1'});
      await FeedInputCache.put('pumped', {'b': '2'});
      await FeedInputCache.put('solid', {'c': '3'});
      expect(FeedInputCache.get('formula'), {'a': '1'});
      expect(FeedInputCache.get('pumped'), {'b': '2'});
      expect(FeedInputCache.get('solid'), {'c': '3'});
    });

    test('clear wipes mem and storage for all subs', () async {
      await FeedInputCache.put('formula', {'a': '1'});
      await FeedInputCache.put('pumped', {'b': '2'});
      await FeedInputCache.clear();
      expect(FeedInputCache.get('formula'), isEmpty);
      expect(FeedInputCache.get('pumped'), isEmpty);
      expect(await pref('feed_last_formula'), isNull);
      expect(await pref('feed_last_pumped'), isNull);
      expect(await pref('feed_last_solid'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('TourCache', () {
    final cache = TourCache();

    test('unset → empty set', () async {
      expect(await cache.read(), isEmpty);
    });

    test('add → read round-trip', () async {
      await cache.add('home');
      expect(await cache.read(), {'home'});
      expect(await pref('tour_seen_v1'), 'home');
    });

    test('multiple adds accumulate (CSV)', () async {
      await cache.add('home');
      await cache.add('charts');
      await cache.add('timeline');
      final seen = await cache.read();
      expect(seen, {'home', 'charts', 'timeline'});
    });

    test('adding duplicate keeps set semantics (no dup in storage)', () async {
      await cache.add('home');
      await cache.add('home');
      expect(await cache.read(), {'home'});
      expect(await pref('tour_seen_v1'), 'home');
    });

    test('read filters empty tokens from CSV', () async {
      await setPref('tour_seen_v1', 'home,,charts,');
      expect(await cache.read(), {'home', 'charts'});
    });

    test('clear empties the set', () async {
      await cache.add('home');
      await cache.clear();
      expect(await cache.read(), isEmpty);
      expect(await pref('tour_seen_v1'), isNull);
    });

    test('eski Keychain CSV prefs\'e göç eder', () async {
      _store['tour_seen_v1'] = 'home,charts';
      expect(await cache.read(), {'home', 'charts'});
      expect(await pref('tour_seen_v1'), 'home,charts');
      expect(_store.containsKey('tour_seen_v1'), isFalse);
    });
  });
}
