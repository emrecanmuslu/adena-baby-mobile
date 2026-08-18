import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:adena_baby/data/local_prefs.dart';

/// Eski (legacy) Keychain'i temsil eden bellek-içi depo + okuma sayacı.
/// LocalPrefs.migrateString'in asıl işi: prefs'te olmayan anahtarı BİR KEZ
/// Keychain'den göç ettirmek — ve bir daha oraya dönmemek. Sayaç bunu kanıtlar.
final Map<String, String> _kc = {};
int _reads = 0;
bool _throwOnRead = false;

void _installSecureStorageMock() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'read':
        _reads++;
        if (_throwOnRead) {
          throw PlatformException(code: 'kc_locked', message: 'unavailable');
        }
        return _kc[args['key'] as String];
      case 'write':
        _kc[args['key'] as String] = args['value'] as String;
        return null;
      case 'delete':
        _kc.remove(args['key'] as String);
        return null;
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  setUp(() {
    _kc.clear();
    _reads = 0;
    _throwOnRead = false;
    _installSecureStorageMock();
    SharedPreferences.setMockInitialValues({});
    LocalPrefs.resetForTests();
  });

  test('prefs değeri varsa Keychain hiç okunmaz', () async {
    final p = await prefs();
    await p.setString('k', 'v');
    expect(await LocalPrefs.migrateString(p, 'k'), ('v', false));
    expect(_reads, 0);
  });

  test('eski Keychain değeri prefs\'e göç eder ve Keychain temizlenir', () async {
    _kc['k'] = 'eski';
    final p = await prefs();
    expect(await LocalPrefs.migrateString(p, 'k'), ('eski', false));
    expect(p.getString('k'), 'eski'); // prefs kanonik depo
    expect(_kc.containsKey('k'), isFalse); // Keychain temizlendi
    expect(_reads, 1);
  });

  test('göç sonrası okumalar prefs\'ten gelir (Keychain\'e dönülmez)', () async {
    _kc['k'] = 'eski';
    final p = await prefs();
    await LocalPrefs.migrateString(p, 'k');
    await LocalPrefs.migrateString(p, 'k');
    expect(_reads, 1);
  });

  test('değer yoksa işaret bırakılır → sonraki açılışlar Keychain\'e DOKUNMAZ',
      () async {
    final p = await prefs();
    expect(await LocalPrefs.migrateString(p, 'yok'), (null, false));
    expect(_reads, 1);
    expect(p.getBool('kcx_yok'), isTrue); // "temiz okundu, değer yok" işareti

    // İşaret varken Keychain'e sonradan değer düşse bile artık bakılmaz:
    // bu, her açılışta tekrarlanan 2 sn'lik göç denemesini ortadan kaldırır.
    _kc['yok'] = 'sonradan';
    expect(await LocalPrefs.migrateString(p, 'yok'), (null, false));
    expect(_reads, 1); // ikinci okuma YOK
  });

  test('işaret, sonradan yazılan GERÇEK prefs değerini gölgelemez', () async {
    final p = await prefs();
    await LocalPrefs.migrateString(p, 'k'); // değer yok → işaret bırakıldı
    expect(p.getBool('kcx_k'), isTrue);
    await p.setString('k', 'yeni'); // uygulama sonradan kendi değerini yazdı
    expect(await LocalPrefs.migrateString(p, 'k'), ('yeni', false));
  });

  test('Keychain hatasında (null, true) döner ve İŞARET BIRAKILMAZ', () async {
    _throwOnRead = true;
    final p = await prefs();
    expect(await LocalPrefs.migrateString(p, 'k'), (null, true));
    expect(p.getBool('kcx_k'), isNull); // sonraki açılış yeniden denesin
  });

  test('bir hata sonrası aynı süreçte diğer anahtarlar beklemeden (null,true) döner',
      () async {
    _throwOnRead = true;
    final p = await prefs();
    await LocalPrefs.migrateString(p, 'a');
    final readsAfterFirst = _reads;
    expect(await LocalPrefs.migrateString(p, 'b'), (null, true));
    expect(_reads, readsAfterFirst); // ikinci anahtar için tekrar beklenmedi
  });

  test('resetForTests sonrası Keychain yeniden denenir', () async {
    _throwOnRead = true;
    final p = await prefs();
    await LocalPrefs.migrateString(p, 'a');
    LocalPrefs.resetForTests();
    _throwOnRead = false;
    _kc['b'] = 'deger';
    expect(await LocalPrefs.migrateString(p, 'b'), ('deger', false));
  });
}
