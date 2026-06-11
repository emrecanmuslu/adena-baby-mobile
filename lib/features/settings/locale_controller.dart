import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../data/auth_repository.dart';
import '../../data/i18n_repository.dart';
import '../auth/auth_controller.dart';

/// Dil (locale) — UserSettings.language'den yüklenir, değişince sunucuya kaydedilir
/// ve çeviri bundle'ı eşitlenip [I18n]'e uygulanır. Değerler: 'tr' | 'en' | …
class LocaleController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) {
      I18n.instance.apply('tr', const {});
      return 'tr';
    }
    var locale = 'tr';
    try {
      final s = await ref.read(authRepositoryProvider).settings();
      locale = (s['language'] as String?) ?? 'tr';
    } catch (_) {}
    await _activate(locale);
    return locale;
  }

  /// Cache'i hemen uygula (anında), sonra sunucudan tazele. Reporter'ı bağla.
  Future<void> _activate(String locale) async {
    final repo = ref.read(i18nRepositoryProvider);
    I18n.instance.reporter ??= (sources) => repo.report(sources);
    if (locale == 'tr') {
      I18n.instance.apply('tr', const {});
      return;
    }
    final (_, cached) = await repo.readCache(locale);
    I18n.instance.apply(locale, cached);
    final fresh = await repo.sync(locale);
    I18n.instance.apply(locale, fresh);
  }

  Future<void> setLocale(String locale) async {
    state = AsyncData(locale);
    await _activate(locale);
    try {
      await ref.read(authRepositoryProvider).updateSettings({'language': locale});
    } catch (_) {
      // Çevrimdışı/hata — yerel seçim korunur, sonraki açılışta sunucudan gelir.
    }
  }

  static String label(String locale) => switch (locale) {
        'en' => 'English',
        _ => 'Türkçe',
      };
}

final localeControllerProvider =
    AsyncNotifierProvider<LocaleController, String>(LocaleController.new);
