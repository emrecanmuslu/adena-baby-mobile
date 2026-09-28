import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_repository.dart';
import '../../data/home_layout_cache.dart';
import '../../models/record.dart';
import '../auth/auth_controller.dart';

/// Home'da Hızlı Giriş ve Son Aktivite'de hangi kayıt türlerinin görüneceği.
/// UserSettings.quick_actions / home_cards (JSON liste) alanlarından yüklenir,
/// değişince sunucuya kaydedilir. Varsayılan: beslenme · bez · uyku.
const _defaultTypes = [RecordType.feed, RecordType.diaper, RecordType.sleep];

/// Özelleştirmede seçilebilecek türler (editörde bu sırayla listelenir).
const kHomeCardChoices = [
  RecordType.feed,
  RecordType.diaper,
  RecordType.sleep,
  RecordType.pumping,
  RecordType.temperature,
  RecordType.medication,
  RecordType.bath,
  RecordType.growth,
];

class HomeLayout {
  final List<RecordType> quick;
  final List<RecordType> lastActivity;
  const HomeLayout({required this.quick, required this.lastActivity});

  HomeLayout copyWith({List<RecordType>? quick, List<RecordType>? lastActivity}) =>
      HomeLayout(
        quick: quick ?? this.quick,
        lastActivity: lastActivity ?? this.lastActivity,
      );

  static const fallback =
      HomeLayout(quick: _defaultTypes, lastActivity: _defaultTypes);
}

/// API'den gelen değeri (tür adları listesi) RecordType listesine çevirir;
/// geçersiz/boşsa varsayılana düşer. En fazla 4 tür.
List<RecordType> _parse(dynamic v) {
  if (v is List && v.isNotEmpty) {
    final out = <RecordType>[];
    for (final e in v) {
      if (e is String) {
        for (final t in RecordType.values) {
          if (t.name == e && !out.contains(t)) {
            out.add(t);
            break;
          }
        }
      }
    }
    if (out.isNotEmpty) return out.take(4).toList();
  }
  return _defaultTypes;
}

/// Açılışta cache'ten okunan yerleşim (main.dart bu provider'ı override eder).
/// homeLayoutController henüz sunucudan yüklenmeden ilk frame'de kullanıcının
/// SON BİLİNEN özelleştirmesi görünsün diye fallback olarak bunu kullanırız —
/// sabit varsayılan (beslenme·bez·uyku) yerine.
final cachedHomeLayoutProvider = Provider<HomeLayout>((_) => HomeLayout.fallback);

class HomeLayoutController extends AsyncNotifier<HomeLayout> {
  @override
  Future<HomeLayout> build() async {
    // Oturum yoksa/yüklenmeden önce son bilinen yerel yerleşimi kullan (sabit
    // varsayılana düşme → ana sayfa açılışta flaş'lamaz).
    final cached = ref.read(cachedHomeLayoutProvider);
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) return cached;
    try {
      final s = await ref.read(authRepositoryProvider).settings();
      final layout = HomeLayout(
        quick: _parse(s['quick_actions']),
        lastActivity: _parse(s['home_cards']),
      );
      unawaited(HomeLayoutCache().writeQuick(layout.quick));
      unawaited(HomeLayoutCache().writeLastActivity(layout.lastActivity));
      return layout;
    } catch (_) {
      return cached;
    }
  }

  Future<void> setQuick(List<RecordType> types) async {
    final HomeLayout cur = state.asData?.value ?? ref.read(cachedHomeLayoutProvider);
    state = AsyncData(cur.copyWith(quick: types));
    unawaited(HomeLayoutCache().writeQuick(types)); // açılışta flaş'sız okunsun
    try {
      await ref.read(authRepositoryProvider).updateSettings(
          {'quick_actions': types.map((t) => t.name).toList()});
    } catch (_) {
      // Çevrimdışı/hata — yerel seçim korunur, sonraki açılışta sunucudan gelir.
    }
  }

  Future<void> setLastActivity(List<RecordType> types) async {
    final HomeLayout cur = state.asData?.value ?? ref.read(cachedHomeLayoutProvider);
    state = AsyncData(cur.copyWith(lastActivity: types));
    unawaited(HomeLayoutCache().writeLastActivity(types));
    try {
      await ref.read(authRepositoryProvider).updateSettings(
          {'home_cards': types.map((t) => t.name).toList()});
    } catch (_) {}
  }
}

final homeLayoutControllerProvider =
    AsyncNotifierProvider<HomeLayoutController, HomeLayout>(
        HomeLayoutController.new);
