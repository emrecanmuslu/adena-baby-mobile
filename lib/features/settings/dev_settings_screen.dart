import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/api_error.dart';
import '../../core/config.dart';
import '../../core/providers.dart';
import '../../core/restart_widget.dart';
import '../../core/theme.dart';
import '../../data/env_cache.dart';
import '../../data/subscription_repository.dart';
import '../auth/auth_controller.dart';
import '../records/record_controller.dart';

/// YALNIZ debug — Geliştirici ayarları sayfası. Şimdilik tek bölüm: API ortamı
/// (Yerel/Prod) değiştirme. İleride başka geliştirici ayarları buraya eklenir.
/// Release build'lerde bu sayfaya hiç gidilmez (menü öğesi kDebugMode ile gizli).
class DevSettingsScreen extends ConsumerWidget {
  const DevSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isProd = AppConfig.apiBaseUrl == AppConfig.envProdUrl;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Geliştirici'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          adSec('🛠 API Ortamı'),
          AdMenuItem(
            icon: 'home',
            color: AppColors.sleep,
            bg: AppColors.sleepBg,
            title: 'Ortam: Yerel',
            meta: isProd ? 'http://10.0.2.2:8000' : '● Aktif',
            onTap:
                isProd ? () => _switch(context, ref, AppConfig.envLocalUrl, 'Yerel') : () {},
          ),
          AdMenuItem(
            icon: 'compass',
            color: AppColors.coral,
            bg: AppColors.feedBg,
            title: 'Ortam: Prod',
            meta: isProd ? '● Aktif' : 'api.adenababy.com',
            onTap:
                isProd ? () {} : () => _switch(context, ref, AppConfig.envProdUrl, 'Prod'),
          ),
          const SizedBox(height: 12),
          Text(
            'Seçilen ortam cihazda kalıcı saklanır; sen değiştirmedikçe '
            'açılışlar arasında korunur.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),

          const SizedBox(height: 20),
          adSec('💎 Premium (geliştirme)'),
          AdSaveButton(
            label: 'Premium aç (sahte)',
            color: AppColors.coral,
            ghost: true,
            onTap: () => _setPremium(context, ref, true),
          ),
          const SizedBox(height: 8),
          AdSaveButton(
            label: 'Premium kapat (sahte)',
            color: AppColors.muted,
            ghost: true,
            onTap: () => _setPremium(context, ref, false),
          ),
          const SizedBox(height: 12),
          Text(
            'Yalnız test amaçlı: backend dev-activate ile premium aç/kapa '
            '(prod backend 403 döner). Gerçek satın alma premium sayfasındadır.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// GELİŞTİRME: backend dev-activate ile premium'u test için aç/kapa. Gerçek
  /// mağaza satın alması emülatörde çalışmadığından test sürecinde kullanılır.
  /// Prod backend bu ucu 403 ile reddeder.
  Future<void> _setPremium(BuildContext context, WidgetRef ref, bool active) async {
    try {
      await ref
          .read(subscriptionRepositoryProvider)
          .devActivate(active: active);
      ref.invalidate(subscriptionProvider);
      if (context.mounted) {
        showAdToast(context, active ? 'Premium açıldı 🎉' : 'Premium kapatıldı');
      }
    } catch (e) {
      if (context.mounted) showAdError(context, apiErrorText(e));
    }
  }

  /// API ortamını (Yerel/Prod) değiştirir. Değiştirince mevcut ortamda çıkış
  /// yapar + yerel veriyi temizler + uygulamayı yeniden başlatır (ortamlar/oturum
  /// karışmasın, temiz başlangıç).
  Future<void> _switch(
      BuildContext context, WidgetRef ref, String url, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Ortam → $name'),
        content: const Text(
            'Çıkış yapılacak, YEREL VERİ TEMİZLENECEK ve uygulama yeniden '
            'başlatılacak. Yeni ortamda yeniden giriş yapman gerekir. Onaylıyor musun?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('Onayla')),
        ],
      ),
    );
    if (ok != true) return;
    // 1) Mevcut ortamda çıkış (token kaydını eski ortam geçerliyken sil).
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {}
    // 2) Yeni ortamı kalıcı sakla (açılışta AppConfig'e uygulanır).
    await EnvCache().write(url);
    // 3) Bellekteki ortamı da HEMEN güncelle — RestartWidget main()'i yeniden
    //    çalıştırmaz, yalnız widget ağacını sıfırlar; bunu yapmazsak bellek eski
    //    ortamda kalır, seçim ancak soğuk açılışta okunur ve cache ile ayrışır.
    AppConfig.setRuntimeApiBaseUrl(url);
    // 4) Yerel veriyi temizle (ortamlar arası karışmasın).
    try {
      SyncService.wiping = true; // silme sırasında sync re-insert etmesin (yarış)
      await ref.read(databaseProvider).wipeAllData();
    } catch (_) {}
    // 5) Yeniden başlat → ApiClient yeni tabana bağlanır, oturum sıfırlanır.
    if (context.mounted) RestartWidget.restartApp(context);
  }
}
