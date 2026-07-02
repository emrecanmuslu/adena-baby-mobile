import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/api_client.dart';
import '../core/json_cache.dart';
import '../core/providers.dart';
import '../core/revenuecat_service.dart';
import '../features/auth/auth_controller.dart';
import '../models/pricing.dart';
import '../models/subscription.dart';
import 'local_session.dart';
import 'subscription_cache.dart';

/// Abonelik + AI dışa aktarım uçları (API §9).
class SubscriptionRepository {
  final ApiClient _api;
  final SubscriptionCache _cache = SubscriptionCache();
  SubscriptionRepository(this._api);

  /// Her başarılı yanıtta premium durumunu kalıcı cache'e yaz (açılış flaş'ını önler).
  Subscription _store(Subscription s) {
    unawaited(_cache.write(s.isPremium));
    // Cloud verisi SADECE gerçekten silindiyse (manuel "buluttan sil" ya da grace sonu
    // cron purge → sunucu cloud_purged_at damgası) "tam yüklendi" bayrağını temizle →
    // yeniden abonelikte migrasyon tam yeniden-yükleme yapsın. Grace içinde (cloud hâlâ
    // dolu, purge YOK) bayrak korunur → yeniden abonelikte zaten cloud'da olan veri
    // TEKRAR YÜKLENMEZ (veri/maliyet/bekleme tasarrufu). Damga "işlenen"den yeni mi
    // diye karşılaştırılır (aynı purge iki kez tetiklemesin).
    final acct = LocalSession.activeAccountId;
    final purged = s.cloudPurgedAt;
    if (acct != null && purged != null) {
      final handled = LocalSession.lastPurgeHandled(acct);
      if (handled == null || purged.isAfter(handled)) {
        unawaited(LocalSession.clearPremiumSyncedForAccount(acct));
        unawaited(LocalSession.setPurgeHandled(acct, purged));
      }
    }
    return s;
  }

  Future<Subscription> get() async {
    final resp = await _api.dio.get('/auth/me/subscription');
    return _store(Subscription.fromJson(resp.data as Map<String, dynamic>));
  }

  /// Satın alma sonrası backend'i RevenueCat'ten taze durumla senkronla.
  /// Webhook gecikmesini atlar; sunucu REST anahtarı yoksa mevcut durumu döner.
  Future<Subscription> refresh() async {
    final resp = await _api.dio.post('/auth/me/subscription/refresh');
    return _store(Subscription.fromJson(resp.data as Map<String, dynamic>));
  }

  /// Tek-kullanımlık premium kodunu kullan (aylık/yıllık/lifetime → backend belirler).
  Future<Subscription> redeem(String code) async {
    final resp = await _api.dio.post('/auth/me/subscription/redeem', data: {'code': code});
    return _store(Subscription.fromJson(resp.data as Map<String, dynamic>));
  }

  /// Premium bitince (lapsed/free): kullanıcının kendi CLOUD verisini hemen kalıcı
  /// siler (60 günü beklemeden) → abonelik free'ye düşer. Yerel/telefon verisi
  /// etkilenmez. Çağırmadan ÖNCE `InitialImportService.forceImport()` ile
  /// cloud→yerel indirilmeli (kayıp olmasın).
  Future<Subscription> purgeCloudData() async {
    final resp = await _api.dio.post('/auth/me/cloud-data/purge');
    return _store(Subscription.fromJson(resp.data as Map<String, dynamic>));
  }

  /// GELİŞTİRME (yalnız backend DEBUG): RevenueCat anahtarı gelene kadar
  /// "satın alınmış gibi" premium aç/kapa. Prod'da backend 403 döner.
  Future<Subscription> devActivate({String plan = 'lifetime', bool active = true}) async {
    final resp = await _api.dio
        .post('/auth/me/subscription/dev-activate', data: {'plan': plan, 'active': active});
    return _store(Subscription.fromJson(resp.data as Map<String, dynamic>));
  }

  /// Yönetilebilir fiyat planları + indirim (locale'e göre para birimi). Gerçek
  /// satın alma fiyatı mağazadan; bu gösterim/fallback + indirim içindir.
  Future<Map<String, PlanPricing>> pricing() async {
    try {
      final resp = await _api.dio.get('/pricing/plans');
      final list = ((resp.data as Map<String, dynamic>)['plans'] as List)
          .cast<Map<String, dynamic>>();
      await JsonCache.write('pricing', list);
      return {for (final p in list) p['plan'] as String: PlanPricing.fromJson(p)};
    } catch (_) {
      final cached = await JsonCache.read('pricing');
      if (cached is List) {
        final list = cached.cast<Map<String, dynamic>>();
        return {for (final p in list) p['plan'] as String: PlanPricing.fromJson(p)};
      }
      return const <String, PlanPricing>{};
    }
  }

  /// Doktora/AI-hazır 1/3/7 günlük özet (premium; değilse backend 403 döner).
  Future<String> aiExport(String babyId, int days) async {
    final resp = await _api.dio.post('/babies/$babyId/ai-export', data: {'days': days});
    return (resp.data as Map<String, dynamic>)['summary_text'] as String? ?? '';
  }
}

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SubscriptionRepository(ref.watch(apiClientProvider)),
);

/// Açılışta okunan SON BİLİNEN premium durumu (kalıcı cache). main()'de
/// `overrideWithValue` ile gerçek değere set edilir; canlı API gelene kadar
/// kullanılır → premium kullanıcıya rozet/kilit flaş'ı OLMAZ.
final cachedPremiumProvider = Provider<bool>((_) => false);

/// Mevcut abonelik durumu. Satın alma sonrası invalidate edilir.
/// Local-first: hesapsız (oturum yok) kullanıcıda sunucuya HİÇ gitmez → 401 olmaz,
/// doğrudan free döner (free kullanıcı zaten premium değil).
final subscriptionProvider = FutureProvider<Subscription>((ref) {
  final loggedIn = ref.watch(authControllerProvider).asData?.value != null;
  if (!loggedIn) return const Subscription(tier: 'free');
  return ref.watch(subscriptionRepositoryProvider).get();
});

/// Yönetilebilir fiyat planları (DB'den, locale para birimiyle). Paywall okur.
final pricingProvider = FutureProvider<Map<String, PlanPricing>>(
  (ref) => ref.watch(subscriptionRepositoryProvider).pricing(),
);

/// UI gating + gösterim için premium bayrağı. Canlı durum KESİN yüklendiyse onu,
/// yoksa cache'lenmiş son durumu kullanır (flaş'sız). Her yerde bunu kullan.
///
/// Splash penceresi (auth hâlâ /auth/me doğruluyor) için KRİTİK: auth AsyncLoading
/// iken `subscriptionProvider` "oturum yok → free" senkron değerini üretir; bu SAHTE
/// free'ye takılıp cache fallback'ini gölgelemesin diye auth yüklenirken doğrudan
/// cache okunur → premium rozeti açılıştan itibaren flaş'sız görünür. (Auth çıkışa
/// çözülürse cache zaten logout'ta temizlenmiştir → free doğru.)
final isPremiumProvider = Provider<bool>((ref) {
  final cached = ref.watch(cachedPremiumProvider);
  if (ref.watch(authControllerProvider).isLoading) return cached;
  return ref.watch(subscriptionProvider).asData?.value.isPremium ?? cached;
});

/// Premium DEĞİL mi (rozet/upsell/kilit gösterimi için). Cache sayesinde
/// açılıştan itibaren doğru → flaş yok.
final isDefinitelyFreeProvider =
    Provider<bool>((ref) => !ref.watch(isPremiumProvider));

/// RevenueCat entitlement değişimini dinler → backend'i senkronlar → durumu
/// tazeler. AdenaApp kökte watch eder (syncService gibi) ki dinleyici canlı
/// kalsın. RC yapılandırılmamışsa no-op.
final premiumSyncProvider = Provider<void>((ref) {
  Future<void> onUpdate(CustomerInfo _) async {
    try {
      await ref.read(subscriptionRepositoryProvider).refresh();
    } catch (_) {}
    ref.invalidate(subscriptionProvider);
  }

  final svc = RevenueCatService.instance;
  svc.addUpdateListener(onUpdate);
  ref.onDispose(() => svc.removeUpdateListener(onUpdate));
});
