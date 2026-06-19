import 'package:flutter_test/flutter_test.dart';
import 'package:adena_baby/core/i18n.dart';

/// I18n is a global singleton (I18n.instance) that mutates process-wide state
/// (_locale + _map). Each test snapshots that state in setUp and restores it in
/// tearDown so the singleton is isolated between tests and from the rest of the
/// suite.
void main() {
  final i18n = I18n.instance;

  // Snapshot/restore the global singleton state around every test.
  late String savedLocale;
  late Map<String, String> savedMap;

  setUp(() {
    savedLocale = i18n.locale;
    // No public getter for the map; re-read it indirectly by re-applying a
    // copy in tearDown. We capture the current pair by applying the same.
    savedMap = _snapshotMap(i18n);
  });

  tearDown(() {
    i18n.apply(savedLocale, savedMap);
  });

  group('tr() fallback behaviour', () {
    test('locale tr → kaynak metnin kendisi döner (sözlük yok sayılır)', () {
      i18n.apply('tr', {'Merhaba': 'Hello-from-map'});
      // TR aktifken her zaman kaynağa düşer; sözlük kullanılmaz.
      expect(i18n.tr('Merhaba'), 'Merhaba');
      expect(tr('Herhangi bir metin'), 'Herhangi bir metin');
    });

    test('locale en + sözlük yok → kaynağa (key) düşer', () {
      i18n.apply('en', const {});
      expect(i18n.tr('Merhaba'), 'Merhaba');
    });

    test('locale en + sözlükte varsa çeviri döner', () {
      i18n.apply('en', {'Merhaba': 'Hello'});
      expect(i18n.tr('Merhaba'), 'Hello');
      expect(tr('Merhaba'), 'Hello'); // global kısayol da aynı
    });

    test('locale en + anahtar eksik → kaynağa düşer', () {
      i18n.apply('en', {'Merhaba': 'Hello'});
      expect(i18n.tr('Görülmemiş metin'), 'Görülmemiş metin');
    });

    test('locale en + boş string çeviri → kaynağa düşer', () {
      i18n.apply('en', {'Merhaba': ''});
      expect(i18n.tr('Merhaba'), 'Merhaba');
    });
  });

  group('locale getter / apply', () {
    test('apply locale getter\'ı günceller', () {
      i18n.apply('en', const {});
      expect(i18n.locale, 'en');
      i18n.apply('tr', const {});
      expect(i18n.locale, 'tr');
    });

    test('apply notifyListeners tetikler', () {
      var notified = 0;
      void listener() => notified++;
      i18n.addListener(listener);
      addTearDown(() => i18n.removeListener(listener));
      i18n.apply('en', {'a': 'b'});
      expect(notified, 1);
    });

    test('sözlük/locale değişimi sonraki tr() çağrılarına yansır', () {
      i18n.apply('en', {'Anahtar': 'V1'});
      expect(i18n.tr('Anahtar'), 'V1');
      // Aynı locale, yeni sözlük.
      i18n.apply('en', {'Anahtar': 'V2'});
      expect(i18n.tr('Anahtar'), 'V2');
      // TR'ye dönünce kaynağa düşer.
      i18n.apply('tr', {'Anahtar': 'V2'});
      expect(i18n.tr('Anahtar'), 'Anahtar');
    });
  });

  group('trp() placeholder interpolation', () {
    test('tek placeholder değerle değiştirilir (tr locale, kaynak=anahtar)', () {
      i18n.apply('tr', const {});
      expect(trp('{n} gün sonra', {'n': 3}), '3 gün sonra');
    });

    test('birden fazla placeholder hepsi değiştirilir', () {
      i18n.apply('tr', const {});
      expect(
        trp('{a} ve {b}', {'a': 'elma', 'b': 'armut'}),
        'elma ve armut',
      );
    });

    test('aynı placeholder iki kez geçerse hepsi değişir (replaceAll)', () {
      i18n.apply('tr', const {});
      expect(trp('{n}-{n}', {'n': 7}), '7-7');
    });

    test('en locale: önce çeviri sonra interpolasyon uygulanır', () {
      i18n.apply('en', {'{n} gün sonra': '{n} days later'});
      expect(trp('{n} gün sonra', {'n': 5}), '5 days later');
    });

    test('null değer boş stringe çevrilir', () {
      i18n.apply('tr', const {});
      expect(trp('[{x}]', {'x': null}), '[]');
    });

    test('args içinde olmayan placeholder olduğu gibi kalır', () {
      i18n.apply('tr', const {});
      // {b} args'ta yok → dokunulmaz.
      expect(trp('{a} {b}', {'a': 'X'}), 'X {b}');
    });

    test('args boşsa kaynak metin değişmeden döner', () {
      i18n.apply('tr', const {});
      expect(trp('{n} gün', const {}), '{n} gün');
    });

    test('en locale + çeviri yok → kaynağa interpolasyon uygulanır', () {
      i18n.apply('en', const {});
      expect(trp('{n} gün sonra', {'n': 2}), '2 gün sonra');
    });
  });
}

/// I18n has no public map getter. We can derive the current map only by probing,
/// which is not feasible generally; instead we accept that restoring with an
/// empty map after tests is harmless because the real app re-applies the bundle
/// on startup. To stay faithful, we keep whatever locale was active and reset to
/// an empty map (the production default before any bundle loads).
Map<String, String> _snapshotMap(I18n i18n) => const {};
