import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/i18n.dart';
import '../core/providers.dart';

/// Aşı kataloğu kalemi (bölgeye göre). `months` = doğumdan itibaren ay (due_date
/// yerelde hesaplanır), `key` = durum eşleştirme anahtarı (= aşı adı).
class VaccineCatalogItem {
  final String key;
  final int months;
  final String name;
  const VaccineCatalogItem(this.key, this.months, this.name);
  factory VaccineCatalogItem.fromJson(Map<String, dynamic> j) => VaccineCatalogItem(
        j['key'] as String? ?? j['name'] as String? ?? '',
        (j['months'] as num?)?.toInt() ?? 0,
        j['name'] as String? ?? '',
      );
}

/// Gelişim/kilometre taşı kataloğu kalemi.
class MilestoneCatalogItem {
  final String key;
  final int month;
  final String category;
  final String title;
  final String description;
  final String tip;
  const MilestoneCatalogItem(
      this.key, this.month, this.category, this.title, this.description, this.tip);
  factory MilestoneCatalogItem.fromJson(Map<String, dynamic> j) => MilestoneCatalogItem(
        j['key'] as String? ?? '',
        (j['month'] as num?)?.toInt() ?? 0,
        j['category'] as String? ?? 'motor',
        j['title'] as String? ?? '',
        j['description'] as String? ?? '',
        j['tip'] as String? ?? '',
      );
}

/// Süt dişi kataloğu kalemi.
class ToothCatalogItem {
  final String key;
  final String jaw;
  final String side;
  final int position;
  final String name;
  final int typicalMonth;
  const ToothCatalogItem(
      this.key, this.jaw, this.side, this.position, this.name, this.typicalMonth);
  factory ToothCatalogItem.fromJson(Map<String, dynamic> j) => ToothCatalogItem(
        j['key'] as String? ?? '',
        j['jaw'] as String? ?? 'upper',
        j['side'] as String? ?? 'left',
        (j['position'] as num?)?.toInt() ?? 1,
        j['name'] as String? ?? '',
        (j['typical_month'] as num?)?.toInt() ?? 0,
      );
}

/// Sağlık kataloğu (aşı/gelişim/diş) — bebeğe bağlı olmayan, deterministik içerik.
class HealthCatalog {
  final List<VaccineCatalogItem> vaccines;
  final List<MilestoneCatalogItem> milestones;
  final List<ToothCatalogItem> teeth;
  const HealthCatalog(this.vaccines, this.milestones, this.teeth);

  factory HealthCatalog.fromJson(Map<String, dynamic> j) => HealthCatalog(
        ((j['vaccines'] as List?) ?? const [])
            .map((e) => VaccineCatalogItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        ((j['milestones'] as List?) ?? const [])
            .map((e) => MilestoneCatalogItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        ((j['teeth'] as List?) ?? const [])
            .map((e) => ToothCatalogItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static const empty = HealthCatalog([], [], []);
}

/// Sağlık kataloğunu yükler: API → disk cache → gömülü asset (offline-first).
/// Bebeğe bağlı değil; tek gerçek kaynak API ama çevrimdışı/ilk-açılışta asset
/// kullanılır. Aşı/gelişim/diş ekranları her durumda dolu gelir (403 olmaz).
class HealthCatalogRepository {
  final ApiClient _api;
  HealthCatalogRepository(this._api);

  String get _locale => I18n.instance.locale == 'en' ? 'en' : 'tr';

  Future<File> _cacheFile(String locale) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/health_catalog_$locale.json');
  }

  Future<void> _writeCache(String locale, Map<String, dynamic> data) async {
    try {
      await (await _cacheFile(locale)).writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readCache(String locale) async {
    try {
      final f = await _cacheFile(locale);
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString());
      return raw is Map<String, dynamic> ? raw : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readAsset(String locale) async {
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/health_catalog_$locale.json'));
      return raw is Map<String, dynamic> ? raw : null;
    } catch (_) {
      return null;
    }
  }

  Future<HealthCatalog> load() async {
    final locale = _locale;
    try {
      final resp = await _api.dio.get('/content/health-catalog');
      final data = resp.data;
      if (data is Map<String, dynamic> &&
          (data['vaccines'] is List || data['milestones'] is List)) {
        await _writeCache(locale, data);
        return HealthCatalog.fromJson(data);
      }
    } catch (_) {}
    final cached = await _readCache(locale);
    if (cached != null) return HealthCatalog.fromJson(cached);
    final asset = await _readAsset(locale) ?? await _readAsset('tr');
    if (asset != null) return HealthCatalog.fromJson(asset);
    return HealthCatalog.empty;
  }
}

final healthCatalogRepositoryProvider = Provider<HealthCatalogRepository>(
    (ref) => HealthCatalogRepository(ref.watch(apiClientProvider)));

/// Sağlık kataloğu (dil değişiminde RestartWidget tüm ağacı sıfırladığı için
/// otomatik yeniden yüklenir).
final healthCatalogProvider = FutureProvider<HealthCatalog>(
    (ref) => ref.watch(healthCatalogRepositoryProvider).load());
