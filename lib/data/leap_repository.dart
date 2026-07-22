import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import 'leap_weeks.dart';

/// Gelişim atağı (leap) verisini sunucudan (salt-okunur) çeker ve diske
/// önbellekler. Offline-first: API erişilemezse cache, o da yoksa uygulamaya
/// gömülü liste (`kEmbeddedLeaps`) kullanılır. Desen `PregnancyRepository`
/// ile birebir aynı.
class LeapRepository {
  final ApiClient _api;
  LeapRepository(this._api);

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/leaps.json');
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

  Future<List<LeapInfo>> load() async {
    try {
      final resp = await _api.dio.get('/content/leaps');
      final data = resp.data;
      if (data is List && data.isNotEmpty) {
        await _writeCache(data);
        return _sorted(data.map((e) => LeapInfo.fromApi(e as Map<String, dynamic>)).toList());
      }
    } catch (_) {}
    try {
      final cached = await _readCache();
      if (cached != null && cached.isNotEmpty) {
        return _sorted(
            cached.map((e) => LeapInfo.fromApi(e as Map<String, dynamic>)).toList());
      }
    } catch (_) {}
    return kEmbeddedLeaps;
  }

  List<LeapInfo> _sorted(List<LeapInfo> l) => l..sort((a, b) => a.index.compareTo(b.index));
}

final leapRepositoryProvider =
    Provider<LeapRepository>((ref) => LeapRepository(ref.watch(apiClientProvider)));

/// Gelişim atağı verisi — yüklenirken/çevrimdışıyken gömülüye düşülebilir.
final leapsProvider = FutureProvider<List<LeapInfo>>((ref) async {
  return ref.watch(leapRepositoryProvider).load();
});
