import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import 'pregnancy_weeks.dart';

/// Gebelik haftası gelişim verisini sunucudan (salt-okunur) çeker ve diske
/// önbellekler. Offline-first: API erişilemezse cache, o da yoksa uygulamaya
/// gömülü tablo (`PregnancyWeeksData.embedded`) kullanılır.
class PregnancyRepository {
  final ApiClient _api;
  PregnancyRepository(this._api);

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/pregnancy_weeks.json');
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

  /// Önce API → cache yaz; başarısızsa cache → gömülü tablo.
  Future<PregnancyWeeksData> load() async {
    try {
      final resp = await _api.dio.get('/content/pregnancy-weeks');
      final data = resp.data;
      if (data is List && data.isNotEmpty) {
        await _writeCache(data);
        return PregnancyWeeksData.fromApi(data);
      }
    } catch (_) {}
    final cached = await _readCache();
    if (cached != null && cached.isNotEmpty) {
      return PregnancyWeeksData.fromApi(cached);
    }
    return PregnancyWeeksData.embedded;
  }
}

final pregnancyRepositoryProvider = Provider<PregnancyRepository>(
    (ref) => PregnancyRepository(ref.watch(apiClientProvider)));

/// Gebelik haftası verisi — yüklenirken/çevrimdışıyken gömülüye düşülebilir
/// (`asData?.value ?? PregnancyWeeksData.embedded`).
final pregnancyWeeksProvider = FutureProvider<PregnancyWeeksData>((ref) async {
  return ref.watch(pregnancyRepositoryProvider).load();
});
