import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import 'who_lms.dart';

/// WHO LMS tablolarını sunucudan (salt-okunur) çeker, diske önbellekler ve
/// çalışma-zamanı tabloya ([applyWhoLms]) uygular. Offline-first: API yoksa
/// cache, o da yoksa uygulamaya gömülü tablo kullanılır (dokunulmaz).
class WhoLmsRepository {
  final ApiClient _api;
  WhoLmsRepository(this._api);

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/who_lms.json');
  }

  Future<void> _writeCache(List<dynamic> list) async {
    try {
      final f = await _cacheFile();
      await f.writeAsString(jsonEncode(list));
    } catch (_) {}
  }

  Future<List<dynamic>?> _readCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString());
      return raw is List ? raw : null;
    } catch (_) {
      return null;
    }
  }

  /// API → cache yaz + uygula; başarısızsa cache → uygula; o da yoksa gömülü kalır.
  Future<void> load() async {
    try {
      final resp = await _api.dio.get('/content/who-lms');
      final data = resp.data;
      if (data is List && data.isNotEmpty) {
        await _writeCache(data);
        applyWhoLms(data);
        return;
      }
    } catch (_) {}
    final cached = await _readCache();
    if (cached != null && cached.isNotEmpty) applyWhoLms(cached);
  }
}

final whoLmsRepositoryProvider = Provider<WhoLmsRepository>(
    (ref) => WhoLmsRepository(ref.watch(apiClientProvider)));

/// Büyüme grafiği ekranları bunu izleyerek tabloyu API/cache ile günceller.
/// Tamamlanınca yeniden çizim olur; çevrimdışıyken gömülü tabloyla çalışır.
final whoLmsProvider = FutureProvider<void>((ref) async {
  await ref.watch(whoLmsRepositoryProvider).load();
});
