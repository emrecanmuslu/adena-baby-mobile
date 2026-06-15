import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n.dart';
import '../../core/locale_util.dart';
import '../../data/auth_repository.dart';
import '../../data/i18n_repository.dart';
import '../../data/locale_cache.dart';
import '../auth/auth_controller.dart';

/// Dil (locale) — UserSettings.language'den yüklenir, değişince sunucuya kaydedilir
/// ve çeviri bundle'ı eşitlenip [I18n]'e uygulanır. Değerler: 'tr' | 'en'.
/// Kullanıcı henüz seçmemişse (sunucu boş) cihaz diline düşülür ve kaydedilir.
class LocaleController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final device = deviceDefaultLanguage();
    // Yerel seçim varsa ANINDA onu kullan — dil değişiminde uygulama yeniden
    // başlatıldığı için doğru dil restart sonrasında buradan gelir (çevrimdışı
    // güvenli; sunucu beklemez).
    final cached = await LocaleCache().read();
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) {
      final locale = cached ?? device;
      await _activate(locale);
      return locale;
    }
    var locale = cached ?? device;
    var unset = cached == null;
    // Yerel seçim yoksa sunucudaki kayıtlı dile bak.
    if (cached == null) {
      try {
        final s = await ref.read(authRepositoryProvider).settings();
        final saved = (s['language'] as String?)?.trim();
        if (saved != null && saved.isNotEmpty) {
          locale = saved;
          unset = false;
        }
      } catch (_) {}
    }
    await _activate(locale);
    // Kullanıcının kayıtlı dili yoksa cihaz dilini sunucuya + cache'e yaz
    // (sonraki cihazlarda/oturumlarda tutarlı; hata olursa yerel seçim kalır).
    if (unset) {
      try {
        await ref.read(authRepositoryProvider).updateSettings({'language': locale});
      } catch (_) {}
    }
    await LocaleCache().write(locale);
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
    // Önce kalıcıya yaz — çağıran genelde uygulamayı yeniden başlatır; restart
    // sonrası build() bu cache'ten doğru dili okur (çevrimdışı olsa bile).
    await LocaleCache().write(locale);
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
