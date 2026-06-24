import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

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

          // 🧹 TANI-GEÇİCİ — sorun çözülünce bu bölüm + _NseDiagPanel sınıfı +
          // home_widget import'u silinecek.
          const SizedBox(height: 20),
          adSec('📲 NSE / Widget tanılama'),
          const _NseDiagPanel(),
          const SizedBox(height: 8),
          Text(
            'iOS push geldikten sonra "Yenile"ye bas. nse_last_ts dolu + son push '
            'saatine yakınsa NSE GERÇEKTEN koştu demektir; boşsa iOS NSE\'yi hiç '
            'çalıştırmamış (reload/throttle). next_feed_ms widget\'ın okuduğu değer.',
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

/// 🧹 TANI-GEÇİCİ — sorun çözülünce bu sınıf tümüyle silinecek.
/// App Group'tan NSE tanılama izini + widget'ın okuduğu değerleri gösterir.
/// "Push dolu geldi ama widget güncellenmedi" → NSE koştu mu, ne yazdı: BURADA görülür.
class _NseDiagPanel extends StatefulWidget {
  const _NseDiagPanel();

  @override
  State<_NseDiagPanel> createState() => _NseDiagPanelState();
}

class _NseDiagPanelState extends State<_NseDiagPanel> {
  static const _appGroupId = 'group.com.adenababy.adenaBaby';
  Map<String, String?> _v = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final out = <String, String?>{};
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      for (final k in const [
        'nse_last_ts', 'nse_last_baby', 'nse_active_seen', 'nse_wrote_fallback',
        'nse_next_ms', 'active_id', 'baby_name', 'next_feed_ms', 'last_feed_ms',
      ]) {
        out[k] = await HomeWidget.getWidgetData<String>(k);
      }
      final active = out['active_id'];
      if (active != null && active.isNotEmpty) {
        out['next_<active>'] = await HomeWidget.getWidgetData<String>('next_$active');
      }
    } catch (e) {
      out['hata'] = '$e';
    }
    if (mounted) {
      setState(() {
        _v = out;
        _loading = false;
      });
    }
  }

  /// Epoch ms string → "dd/MM HH:mm" (okunur); değilse ham değeri döndür.
  String _fmt(String key, String? val) {
    if (val == null || val.isEmpty) return '—';
    if (key.contains('ms') || key == 'next_<active>') {
      final ms = int.tryParse(val);
      if (ms != null && ms > 0) {
        final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
        return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
      }
    }
    return val.length > 28 ? '${val.substring(0, 28)}…' : val;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.sleepBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            for (final e in _v.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(e.key,
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: AppColors.muted)),
                    ),
                    Expanded(
                      child: Text(_fmt(e.key, e.value),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          AdSaveButton(
            label: 'Yenile',
            color: AppColors.sleep,
            ghost: true,
            onTap: _loading ? () {} : _load,
          ),
        ],
      ),
    );
  }
}
