import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/cycle.dart';

const _uuid = Uuid();

/// Adet Takvimi uçları (API §13 /cycle/...) — kullanıcıya özel, online CRUD.
/// Bebek paylaşımından bağımsız: backend yalnız oturum sahibinin verisini döner.
class CycleRepository {
  final ApiClient _api;
  CycleRepository(this._api);

  Future<CycleSettings> getSettings() async {
    final resp = await _api.dio.get('/cycle/settings');
    return CycleSettings.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<CycleSettings> patchSettings(Map<String, dynamic> fields) async {
    final resp = await _api.dio.patch('/cycle/settings', data: fields);
    return CycleSettings.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<CycleEntry>> listEntries({DateTime? from, DateTime? to}) async {
    final resp = await _api.dio.get('/cycle/entries', queryParameters: {
      if (from != null) 'from': _d(from),
      if (to != null) 'to': _d(to),
    });
    return (resp.data as List<dynamic>)
        .map((e) => CycleEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Gün başına tek kayıt — backend aynı tarih varsa upsert eder.
  Future<CycleEntry> saveEntry(CycleEntry entry) async {
    final data = entry.id.isEmpty
        ? (entry.toJson()..['id'] = _uuid.v4())
        : entry.toJson();
    final resp = await _api.dio.post('/cycle/entries', data: data);
    return CycleEntry.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteEntry(String id) => _api.dio.delete('/cycle/entries/$id');

  static String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final cycleRepositoryProvider =
    Provider<CycleRepository>((ref) => CycleRepository(ref.watch(apiClientProvider)));

/// Kullanıcının adet modülü ayarı (ilk erişimde backend otomatik oluşturur).
final cycleSettingsProvider = FutureProvider<CycleSettings>(
    (ref) => ref.watch(cycleRepositoryProvider).getSettings());

/// Tüm adet kayıtları (yeni→eski). Liste seyrek olduğu için aralıksız çekilir;
/// takvim/istatistik tek kaynaktan beslenir.
final cycleEntriesProvider = FutureProvider<List<CycleEntry>>(
    (ref) => ref.watch(cycleRepositoryProvider).listEntries());
