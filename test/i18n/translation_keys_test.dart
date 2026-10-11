import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// N3 — Çeviri anahtarı bütünlüğü: `lib/` altında `tr('…')` / `trp('…', …)`
/// ile kullanılan HER sabit anahtar, 6 dilin JSON'unda bulunmalı ve
/// `{placeholder}`'lar her dilde korunmalı.
///
/// Kaynak: `../api/apps/translations/data/{en,es,fr,ar,hi,zh}.json` (kardeş
/// repo). Dosyalar yoksa (CI'da api repo'su checkout edilmemiş) test ATLANIR
/// ve uyarı basar — yanlış pozitif vermez.
///
/// Taranmayanlar: `tr(değişken)` / `'$x'` interpolasyonlu dinamik anahtarlar
/// (sayılır, rapora yazılır) ve `lib/` dışı kaynaklar.
const _locales = ['en', 'es', 'fr', 'ar', 'hi', 'zh'];

/// Bu branch'te eklenen anahtarlar — YAYIN-KONTROL.md §2 ile birebir.
const branchAddedKeys = <String>[
  'Toplulukta engellediğin kullanıcıları yönet',
  'Bakıcı rolünde bebek bilgileri salt-okunurdur; düzenlemeyi ebeveyn/sahip yapabilir.',
  'Hesabına başka bir cihazdan giriş yapıldı; bu cihazdaki oturum kapatıldı.',
  'Oturumun sona erdi. Lütfen tekrar giriş yap.',
  'Oturumun sonlandırıldı. Lütfen tekrar giriş yap.',
  '{n} değişiklik sunucuya gönderilemedi',
  'Gönderilemeyen değişiklikler',
  'Değişikliği geri al',
  'Tümünü geri al',
  'Sunucudaki hâli yüklendi',
  'Yerel değişiklik silindi',
  'Silme gönderilemedi',
  'Bu kayıt yalnız bu cihazda kalacak',
  'Bu kayıt sunucuda yok. Yerel değişiklik silinsin mi?',
  'Sunucuya ulaşılamadı',
  'Adet ayarları',
  'Aşı',
  'Diş',
  'Bitiş zamanı başlangıçtan önce olamaz',
  'Verilen dozlar ve plan listesi ailenle paylaşılır.',
  'Bakıcı rolünde planları ebeveyn/sahip düzenler; sen dozları işaretleyebilirsin.',
  'Tam zamanında bildirim',
  'Daha sonra',
  'İzin ver',
  'İzin verildi',
  'İzin yok — hatırlatıcılar birkaç dakika gecikebilir',
  'Bu plan yalnız bu cihazda; ailenle paylaşılmadı',
];

// Tek/çift tırnaklı Dart string literal'i (kaçışlı karakterler dahil).
const _sq = r"'((?:[^'\\]|\\.)*)'";
const _dq = r'"((?:[^"\\]|\\.)*)"';
final _litSrc = '($_sq|$_dq)';
// tr( ... ) / trp( ... ): ilk argüman = bir ya da bitişik birkaç literal.
final _call =
    RegExp(r'\btrp?\(\s*(' + _litSrc + r'(?:\s*' + _litSrc + r')*)', multiLine: true);
final _lit = RegExp(_litSrc);
final _ph = RegExp(r'\{(\w+)\}');

String _unescape(String s) => s
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\\', r'\');

/// Kodda kullanılan sabit anahtarlar (+ atlanan dinamik çağrı sayısı).
({Set<String> keys, int dynamicCalls}) scanKeys(Directory lib) {
  final keys = <String>{};
  var dynamicCalls = 0;
  for (final f in lib.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    for (final m in _call.allMatches(src)) {
      final parts =
          _lit.allMatches(m.group(1)!).map((l) => l.group(2) ?? l.group(3) ?? '');
      final key = _unescape(parts.join());
      if (key.contains(r'$')) {
        dynamicCalls++;
        continue;
      }
      if (key.isNotEmpty) keys.add(key);
    }
  }
  return (keys: keys, dynamicCalls: dynamicCalls);
}

void main() {
  final root = Directory.current.path;
  final dataDir = Directory('$root/../api/apps/translations/data');
  final lib = Directory('$root/lib');

  test('kodda kullanılan her tr()/trp() anahtarı 6 dilde var; placeholder korunur', () {
    if (!dataDir.existsSync()) {
      // ignore: avoid_print
      print('UYARI: ${dataDir.path} yok — çeviri bütünlüğü kontrolü atlandı.');
      return;
    }
    final scan = scanKeys(lib);
    expect(scan.keys, isNotEmpty);
    final problems = <String>[];
    for (final loc in _locales) {
      final f = File('${dataDir.path}/$loc.json');
      expect(f.existsSync(), isTrue, reason: '$loc.json yok');
      final map = (jsonDecode(f.readAsStringSync()) as Map).cast<String, dynamic>();
      for (final k in scan.keys) {
        final v = map[k];
        if (v is! String || v.isEmpty) {
          problems.add('[$loc] EKSİK: $k');
          continue;
        }
        final want = _ph.allMatches(k).map((m) => m.group(1)).toSet();
        final got = _ph.allMatches(v).map((m) => m.group(1)).toSet();
        if (want.isNotEmpty && !want.every(got.contains)) {
          problems.add('[$loc] PLACEHOLDER: "$k" → "$v"');
        }
      }
      for (final k in branchAddedKeys) {
        if (map[k] is! String) problems.add('[$loc] BRANCH ANAHTARI EKSİK: $k');
      }
    }
    // ignore: avoid_print
    print('i18n: ${scan.keys.length} sabit anahtar, ${scan.dynamicCalls} dinamik çağrı atlandı');
    expect(problems, isEmpty, reason: problems.take(60).join('\n'));
  });
}
