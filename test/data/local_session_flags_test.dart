import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/data/local_prefs.dart';
import 'package:adena_baby/data/local_session.dart';

/// O35 (BULGULAR.md): LocalSession'ın set/map bayrakları bellek-içi yapıdan
/// `join` ile diske yazılıyordu. Bellek yüklenmemişken (bg isolate, 8 sn
/// güvenlik ağı) ya da başka isolate diske yazmışken yapılan yazım diğer
/// hesapların bayraklarını eziyordu. Artık her yazım "reload → diskle birleştir
/// → yaz", yükleme de "diskle birleştir".
const _kImported = 'cloud_imported_accounts_v1';
const _kPremium = 'premium_synced_accounts_v1';
const _kPurge = 'purge_handled_v1';

Future<String?> disk(String key) async =>
    (await SharedPreferences.getInstance()).getString(key);

Set<String> csv(String? s) =>
    (s ?? '').split(',').where((e) => e.isNotEmpty).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Keychain göçü (LocalPrefs.migrateString) testte platform kanalı bulamaz;
    // sessizce "okunamadı" döner. Bayrak testleri bundan etkilenmez.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
    LocalPrefs.resetForTests();
    LocalSession.resetForTests();
  });

  group('O35 — yazım diskle birleştirir', () {
    test('bellek yüklenmemişken mark(B): diskteki A korunur', () async {
      SharedPreferences.setMockInitialValues({_kImported: 'A'});
      await LocalSession.markImportedForAccount('B');
      expect(csv(await disk(_kImported)), {'A', 'B'});
      expect(LocalSession.importedForAccount('A'), isTrue);
      expect(LocalSession.importedForAccount('B'), isTrue);
    });

    test('mark(B) sonra ensureLoaded (disk yalnız A): yükleme de birleştirir', () async {
      SharedPreferences.setMockInitialValues({_kImported: 'A'});
      await LocalSession.markImportedForAccount('B'); // disk: A,B
      // Başka isolate/eski kopya diski yalnız "A" bıraktı (bayat) → yükleme
      // bellekteki B'yi atmamalı.
      SharedPreferences.setMockInitialValues({_kImported: 'A'});
      await LocalSession.ensureLoaded();
      expect(LocalSession.importedForAccount('A'), isTrue);
      expect(LocalSession.importedForAccount('B'), isTrue);
    });

    test('ensureLoaded sonrası başka isolate C yazdı; mark(B) → A,B,C', () async {
      SharedPreferences.setMockInitialValues({_kPremium: 'A'});
      await LocalSession.ensureLoaded();
      SharedPreferences.setMockInitialValues({_kPremium: 'A,C'}); // "diğer isolate"
      await LocalSession.markPremiumSyncedForAccount('B');
      expect(csv(await disk(_kPremium)), {'A', 'B', 'C'});
      expect(LocalSession.premiumSyncedForAccount('C'), isTrue);
    });

    test('clearPremiumSyncedForAccount(A): diskteki diğerleri korunur', () async {
      SharedPreferences.setMockInitialValues({_kPremium: 'A'});
      await LocalSession.ensureLoaded();
      SharedPreferences.setMockInitialValues({_kPremium: 'A,C'});
      await LocalSession.clearPremiumSyncedForAccount('A');
      expect(csv(await disk(_kPremium)), {'C'});
      expect(LocalSession.premiumSyncedForAccount('A'), isFalse);
    });

    test('setPurgeHandled: diskteki başka hesabın damgası korunur; çakışmada yeni damga',
        () async {
      SharedPreferences.setMockInitialValues({
        _kPurge: 'acct1=2026-05-01T00:00:00.000Z;acct2=2026-01-01T00:00:00.000Z',
      });
      // Bellekte acct2 için daha ESKİ bir damga olsun (yüklenmemiş kopya).
      await LocalSession.setPurgeHandled('acct2', DateTime.utc(2025, 1, 1));
      // disk acct2=2026-01 (daha yeni) vs bellek 2025-01 → 2026-01 kalmalı;
      // acct1 dokunulmamalı.
      expect(LocalSession.lastPurgeHandled('acct1'), DateTime.utc(2026, 5, 1));
      expect(LocalSession.lastPurgeHandled('acct2'), DateTime.utc(2026, 1, 1));
      final d = await disk(_kPurge);
      expect(d, contains('acct1=2026-05-01'));
      expect(d, contains('acct2=2026-01-01'));

      await LocalSession.setPurgeHandled('acct2', DateTime.utc(2026, 6, 1));
      expect(LocalSession.lastPurgeHandled('acct2'), DateTime.utc(2026, 6, 1));
      expect(await disk(_kPurge), contains('acct1=2026-05-01'));
    });
  });

  group('clearLocalProfile bilinçli sıfırlama (regresyon)', () {
    test('disk + bellek dolu → her ikisi de boşalır; ensureLoaded boş döner', () async {
      SharedPreferences.setMockInitialValues({
        _kImported: 'A,B',
        _kPremium: 'A',
        _kPurge: 'A=2026-05-01T00:00:00.000Z',
      });
      await LocalSession.ensureLoaded();
      expect(LocalSession.importedForAccount('A'), isTrue);

      await LocalSession.clearLocalProfile();

      expect(LocalSession.importedForAccount('A'), isFalse);
      expect(LocalSession.premiumSyncedForAccount('A'), isFalse);
      expect(LocalSession.lastPurgeHandled('A'), isNull);
      expect(await disk(_kImported), isNull);
      expect(await disk(_kPremium), isNull);
      expect(await disk(_kPurge), isNull);
      await LocalSession.ensureLoaded();
      expect(LocalSession.importedForAccount('A'), isFalse);
    });
  });
}
