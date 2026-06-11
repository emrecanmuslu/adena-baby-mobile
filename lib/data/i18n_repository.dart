import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/providers.dart';

/// Çeviri bundle'larını sunucudan çeker, yerelde (JSON dosyası) cache'ler ve
/// bilinmeyen TR metinleri panele raporlar. TR locale için ağ gerekmez.
class I18nRepository {
  final ApiClient _api;
  I18nRepository(this._api);

  Future<File> _cacheFile(String locale) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/i18n_$locale.json');
  }

  Future<(int, Map<String, String>)> readCache(String locale) async {
    try {
      final f = await _cacheFile(locale);
      if (!await f.exists()) return (0, <String, String>{});
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final version = (m['version'] as num?)?.toInt() ?? 0;
      final raw = m['strings'] as Map?;
      final strings = raw == null
          ? <String, String>{}
          : raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      return (version, strings);
    } catch (_) {
      return (0, <String, String>{});
    }
  }

  Future<void> _writeCache(String locale, int version, Map<String, String> s) async {
    try {
      final f = await _cacheFile(locale);
      await f.writeAsString(jsonEncode({'version': version, 'strings': s}));
    } catch (_) {}
  }

  /// Sunucudan dili eşitle (cache sürümüyle). Değişmemişse cache döner; ağ
  /// hatasında da cache'e düşer. Yeni bundle geldiyse cache'i günceller.
  Future<Map<String, String>> sync(String locale) async {
    if (locale == 'tr') return const {};
    final (cachedV, cached) = await readCache(locale);
    try {
      final resp = await _api.dio.get('/i18n/$locale', queryParameters: {'v': cachedV});
      final data = resp.data as Map<String, dynamic>;
      if (data['unchanged'] == true) return cached;
      final version = (data['version'] as num?)?.toInt() ?? 0;
      final raw = data['strings'] as Map?;
      final strings = raw == null
          ? <String, String>{}
          : raw.map((k, v) => MapEntry(k.toString(), v.toString()));
      await _writeCache(locale, version, strings);
      return strings;
    } catch (_) {
      return cached;
    }
  }

  Future<void> report(List<String> sources) async {
    try {
      await _api.dio.post('/i18n/report', data: {'sources': sources});
    } catch (_) {}
  }
}

final i18nRepositoryProvider = Provider<I18nRepository>(
  (ref) => I18nRepository(ref.watch(apiClientProvider)),
);
