import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Basit JSON disk cache. Son kullanıcıyı etkileyen sunucu verilerini (diller,
/// ülkeler, fiyatlar...) çevrimdışı/ağ-hatasında ve sonraki açılışlarda kullanmak
/// için write-through saklarız → boş ekran/flaş olmaz.
class JsonCache {
  static Future<File> _file(String key) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/cache_$key.json');
  }

  static Future<void> write(String key, Object data) async {
    try {
      await (await _file(key)).writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  static Future<dynamic> read(String key) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }
}
