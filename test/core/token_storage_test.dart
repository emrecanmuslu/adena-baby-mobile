import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adena_baby/core/token_storage.dart';

/// TokenStorage, flutter_secure_storage üzerinden JWT access/refresh saklar.
/// secure_storage bir platform method channel kullanır; testte o kanalı
/// in-memory bir Map ile taklit ediyoruz (gerçek anahtar adlarını
/// 'access_token' / 'refresh_token' doğrularız).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  // secure_storage'ın simüle edilmiş arka deposu.
  late Map<String, String> store;
  // Gözlem için kanaldan geçen çağrılar.
  late List<MethodCall> calls;

  /// secure_storage çağrısının argümanlarından mantıksal anahtarı çeker.
  /// Plugin gerçek anahtarı `key` argümanında string olarak geçirir.
  String? keyOf(MethodCall call) {
    final args = call.arguments as Map?;
    return args?['key'] as String?;
  }

  setUp(() {
    store = {};
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'containsKey':
          return store.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('TokenStorage.saveTokens — yazma ve anahtar adları', () {
    test('access + refresh verilince ikisi de gerçek anahtarlarla yazılır',
        () async {
      final ts = TokenStorage();
      await ts.saveTokens(access: 'A1', refresh: 'R1');

      expect(store['access_token'], 'A1');
      expect(store['refresh_token'], 'R1');

      // Yazılan anahtar adları tam olarak kontrol edilir.
      final writeKeys = calls
          .where((c) => c.method == 'write')
          .map(keyOf)
          .toList();
      expect(writeKeys, containsAll(<String>['access_token', 'refresh_token']));
    });

    test('refresh verilmezse yalnız access yazılır (refresh write çağrısı yok)',
        () async {
      final ts = TokenStorage();
      await ts.saveTokens(access: 'A1');

      expect(store['access_token'], 'A1');
      expect(store.containsKey('refresh_token'), isFalse);

      final writeKeys = calls
          .where((c) => c.method == 'write')
          .map(keyOf)
          .toList();
      expect(writeKeys, ['access_token']);
      expect(writeKeys, isNot(contains('refresh_token')));
    });

    test('refresh null olunca mevcut refresh dokunulmadan kalır (kontrat)',
        () async {
      final ts = TokenStorage();
      // Önce ikisini de yaz.
      await ts.saveTokens(access: 'A1', refresh: 'R1');
      // Sadece access güncelle (refresh null → yazılmamalı).
      await ts.saveTokens(access: 'A2');

      expect(store['access_token'], 'A2');
      // Eski refresh korunur.
      expect(store['refresh_token'], 'R1');
    });
  });

  group('TokenStorage — okuma', () {
    test('accessToken / refreshToken kaydedileni geri okur', () async {
      final ts = TokenStorage();
      await ts.saveTokens(access: 'A1', refresh: 'R1');

      expect(await ts.accessToken, 'A1');
      expect(await ts.refreshToken, 'R1');
    });

    test('anahtar yoksa null döner', () async {
      final ts = TokenStorage();
      expect(await ts.accessToken, isNull);
      expect(await ts.refreshToken, isNull);
    });
  });

  group('TokenStorage.hasSession', () {
    test('access varsa true', () async {
      final ts = TokenStorage();
      await ts.saveTokens(access: 'A1');
      expect(await ts.hasSession, isTrue);
    });

    test('access yoksa false', () async {
      final ts = TokenStorage();
      expect(await ts.hasSession, isFalse);
    });
  });

  group('TokenStorage.clear', () {
    test('hem access hem refresh silinir', () async {
      final ts = TokenStorage();
      await ts.saveTokens(access: 'A1', refresh: 'R1');

      await ts.clear();

      expect(store.containsKey('access_token'), isFalse);
      expect(store.containsKey('refresh_token'), isFalse);
      expect(await ts.accessToken, isNull);
      expect(await ts.refreshToken, isNull);

      // Doğru anahtarlarda delete çağrıldı.
      final deleteKeys = calls
          .where((c) => c.method == 'delete')
          .map(keyOf)
          .toList();
      expect(deleteKeys, containsAll(<String>['access_token', 'refresh_token']));
    });

    test('depo zaten boşken clear hata vermez', () async {
      final ts = TokenStorage();
      await ts.clear();
      expect(store, isEmpty);
    });
  });
}
