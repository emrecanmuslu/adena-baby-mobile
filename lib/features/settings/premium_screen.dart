import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/pricing.dart';
import '../../models/subscription.dart';

import '../auth/auth_controller.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/analytics_service.dart';
import '../../core/api_error.dart';
import '../../core/dates.dart';
import '../../core/i18n.dart';
import '../../core/revenuecat_service.dart';
import '../../core/theme.dart';
import '../../data/migration_service.dart';
import '../../data/subscription_repository.dart';

/// Premium / paywall (design ScrPremium): özellik listesi + planlar + CTA + kod.
///
/// Satın alma RevenueCat üzerinden gerçek mağaza (App Store / Google Play) ile
/// yapılır; offerings paketleri gösterilir. Tek-kullanımlık "kod" da çalışır.
/// (Geliştirme/test için sahte premium aç-kapa artık Geliştirici sayfasındadır.)
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  String _plan = 'yearly'; // monthly|yearly|lifetime
  bool _saving = false;
  Offering? _offering;

  bool get _rc => RevenueCatService.instance.isConfigured;

  @override
  void initState() {
    super.initState();
    _loadOffering();
    unawaited(AnalyticsService.instance.log('paywall_shown', {'plan': _plan}));
  }

  Future<void> _loadOffering() async {
    final o = await RevenueCatService.instance.currentOffering();
    if (mounted) setState(() => _offering = o);
  }

  // NOT: getter — `static final` tr()'yi dondurur (dil değişince eski kalır).
  List<(String, String)> get _feats => [
        (tr('Reklamsız, kesintisiz'), tr('Tek bir reklam yok — dikkatin hep bebeğinde')),
        (tr('Sınırsız aile & bakıcı'),
            tr('Eş, anneanne, bakıcı — herkes aynı bebekte, gerçek zamanlı')),
        (tr('Bulut yedekleme'),
            tr('Tüm verin ve fotoğrafların buluta otomatik, cihazlar arası güvende')),
        (tr('Doktora hazır PDF rapor'),
            tr('Büyüme, WHO persentil ve beslenme/uyku özeti tek dokunuşta')),
        (tr('Sınırsız hatırlatıcı'), tr('Aşı, randevu, beslenme — hiçbirini kaçırma')),
      ];

  Package? _packageFor(String plan) {
    final o = _offering;
    if (o == null) return null;
    final type = switch (plan) {
      'monthly' => PackageType.monthly,
      'lifetime' => PackageType.lifetime,
      _ => PackageType.annual,
    };
    for (final p in o.availablePackages) {
      if (p.packageType == type) return p;
    }
    return null;
  }

  /// Gösterilecek güncel fiyat: 1) RC mağaza fiyatı (gerçek, bölgeye göre $/₺),
  /// 2) backend DB fiyatı (yönetilebilir), 3) dile göre son çare placeholder.
  String _price(String plan, PlanPricing? pp, String tryFallback, String usdFallback) =>
      _packageFor(plan)?.storeProduct.priceString ??
      (pp?.price.isNotEmpty == true ? pp!.price : null) ??
      (I18n.instance.locale == 'en' ? usdFallback : tryFallback);

  /// İndirimdeyse üstü çizili eski fiyat (yoksa null).
  String? _orig(PlanPricing? pp) => (pp?.onSale == true) ? pp!.originalPrice : null;

  /// Backend kampanya rozeti (yoksa null → çağıran varsa kendi etiketini kullanır).
  String? _badge(PlanPricing? pp) =>
      (pp != null && pp.badge.isNotEmpty) ? pp.badge : null;

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider).asData?.value;
    final isPremium = sub?.isPremium ?? false;
    // Yönetilebilir fiyatlar (DB) — RC fiyatı yoksa fallback + indirim gösterimi.
    final pricing = ref.watch(pricingProvider).asData?.value ??
        const <String, PlanPricing>{};

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Column(
            children: [
              Container(
                width: 56,
                height: 56,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.premiumGoldLight, AppColors.premiumGold],
                  ),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x59FFB43C), blurRadius: 24, offset: Offset(0, 10)),
                  ],
                ),
                alignment: Alignment.center,
                child: const AdenaIcon('star', size: 28, color: Colors.white, sw: 2.2),
              ),
              Text(tr('Adena Premium'),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                  tr('Bebeğinin her anına tam odaklan — reklamsız, sınırsız ve tüm aile bir arada.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 16),

          // Özellik listesi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.softShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < _feats.length; i++)
                  _FeatureRow(
                    title: _feats[i].$1,
                    desc: _feats[i].$2,
                    last: i == _feats.length - 1,
                  ),
              ],
            ),
          ),

          // Destek notu — premium aynı zamanda geliştirmeye destek olur.
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.peachLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const AdenaIcon('heart', size: 18, color: AppColors.coralDd, sw: 2.2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Premium\'a geçerek küçük ekibimizin Adena Baby\'yi '
                        'geliştirmeye devam etmesine de destek olursun 💛'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w800,
                        color: AppColors.coralDd),
                  ),
                ),
              ],
            ),
          ),

          if (isPremium) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.premiumBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const AdenaIcon('check', size: 20, color: AppColors.premiumInk, sw: 2.4),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Premium aktif — teşekkürler 💛'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: AppColors.premiumInk)),
                        if (sub != null) ...[
                          const SizedBox(height: 2),
                          Text(_planLabel(sub),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                  color: AppColors.premiumInk)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Abonelik iptali mağaza (App Store / Google Play) üzerinden olur —
            // uygulama içinden programatik iptal mümkün değil; mağaza yönetim
            // sayfasını açan buton sunulur (Apple Guideline 3.1.2 gereği de zorunlu).
            if (sub?.willRenew ?? false) ...[
              _InfoCard(tr('Aboneliğini istediğin zaman telefonunun App Store / '
                  'Google Play hesabından iptal edebilirsin. İptal etsen bile mevcut '
                  'dönemin sonuna kadar Premium açık kalır.')),
              const SizedBox(height: 8),
              AdSaveButton(
                label: tr('Aboneliği yönet / iptal et'),
                color: AppColors.muted,
                ghost: true,
                onTap: _manageSubscription,
              ),
            ] else if (sub?.isLifetime ?? false)
              _InfoCard(tr('Ömür boyu premium — yenileme yok, iptal gerekmez 💛'))
            // Mağazadan İPTAL EDİLMİŞ ama süresi dolmamış abonelik: kod/deneme
            // değildir (store=play_store/app_store; kod/dev ise store=code/dev).
            // Dönem sonuna kadar premium sürer; fikir değiştirilirse mağazadan
            // yeniden açılabilsin diye yönetim butonu görünür kalır.
            else if (sub != null &&
                sub.store != null &&
                sub.store != 'code' &&
                sub.store != 'dev') ...[
              _InfoCard(sub.expiresAt != null
                  ? trp(
                      'Aboneliğin iptal edildi — {d} tarihine kadar Premium açık '
                      'kalır. Fikrini değiştirirsen mağazadan yeniden '
                      'başlatabilirsin.',
                      {'d': fmtDayMonthYear(sub.expiresAt!)})
                  : tr('Aboneliğin iptal edildi — mevcut dönemin sonuna kadar '
                      'Premium açık kalır. Fikrini değiştirirsen mağazadan '
                      'yeniden başlatabilirsin.')),
              const SizedBox(height: 8),
              AdSaveButton(
                label: tr('Aboneliği yönet'),
                color: AppColors.muted,
                ghost: true,
                onTap: _manageSubscription,
              ),
            ] else
              _InfoCard(tr('Bu premium bir kod/deneme ile verildi; süresi dolunca '
                  'otomatik olarak ücretsiz katmana döner.')),
          ] else ...[
            if (sub?.isLapsed ?? false) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.peachLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const AdenaIcon('star',
                        size: 18, color: AppColors.coralDd, sw: 2.2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Premium\'un sona erdi'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13.5,
                                  color: AppColors.coralDd)),
                          const SizedBox(height: 2),
                          Text(
                            (sub!.graceDaysLeft() > 0)
                                ? trp(
                                    'Tüm verilerin telefonunda güvende — kaybolmaz. '
                                    'Bulut yedeğin {n} gün daha saklanıyor; bu süre '
                                    'içinde yeniden abone olursan kaldığın yerden '
                                    'kesintisiz devam edersin.',
                                    {'n': sub.graceDaysLeft()})
                                : tr('Tüm verilerin telefonunda güvende. Bulut yedeğin '
                                    'silindi; yeniden abone olduğunda verilerin tekrar '
                                    'buluta yüklenir.'),
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                fontWeight: FontWeight.w700,
                                color: AppColors.coralDd),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              AdSaveButton(
                label: _saving
                    ? tr('İşleniyor…')
                    : tr('Verilerimi indir, bulut yedeğini sil'),
                color: AppColors.muted,
                ghost: true,
                onTap: _saving ? () {} : _purgeCloud,
              ),
            ],
            const SizedBox(height: 14),
            // Aylık + Yıllık yan yana
            Row(
              children: [
                Expanded(
                  child: _PlanCard(
                    selected: _plan == 'monthly',
                    period: tr('Aylık'),
                    price: _price('monthly', pricing['monthly'], '₺79', '\$4.99'),
                    originalPrice: _orig(pricing['monthly']),
                    tag: _badge(pricing['monthly']),
                    sub: tr('/ay'),
                    onTap: () => setState(() => _plan = 'monthly'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlanCard(
                    selected: _plan == 'yearly',
                    period: tr('Yıllık'),
                    price: _price('yearly', pricing['yearly'], '₺590', '\$39.99'),
                    originalPrice: _orig(pricing['yearly']),
                    sub: tr('/yıl'),
                    tag: _badge(pricing['yearly']),
                    onTap: () => setState(() => _plan = 'yearly'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Lifetime tam genişlik
            _PlanCard(
              selected: _plan == 'lifetime',
              period: tr('Ömür boyu'),
              price: _price('lifetime', pricing['lifetime'], '₺1.490', '\$79.99'),
              originalPrice: _orig(pricing['lifetime']),
              tag: _badge(pricing['lifetime']),
              sub: tr('tek seferlik'),
              wide: true,
              onTap: () => setState(() => _plan = 'lifetime'),
            ),
            const SizedBox(height: 16),
            AdSaveButton(
              label: _saving ? tr('İşleniyor…') : tr('Premium ol'),
              color: AppColors.coral,
              onTap: _saving ? () {} : _subscribe,
            ),
            const SizedBox(height: 12),
            // Güven rozetleri — satın alma kararını destekleyen gerçek sinyaller.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _TrustBadge(tr('İstediğin zaman iptal')),
                _TrustBadge(tr('KVKK & GDPR uyumlu')),
                _TrustBadge(tr('Verini asla satmayız')),
              ],
            ),
            const SizedBox(height: 10),
            // Kod kullan + (RC varsa) geri yükle
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _saving ? null : _redeem,
                  child: Text(tr('Kodum var'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                if (_rc)
                  TextButton(
                    onPressed: _saving ? null : _restore,
                    child: Text(tr('Satın alımları geri yükle'),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(tr('İstediğin zaman iptal et · baskı yok 💛'),
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.muted)),
            ),
          ],
        ],
      ),
    );
  }

  /// Premium işlemleri hesap gerektirir (RevenueCat entitlement + cloud yedek).
  /// Misafir kullanıcıyı girişe/kayıta yönlendir.
  bool _ensureLoggedIn() {
    if (ref.read(authControllerProvider).asData?.value != null) return true;
    showAdToast(context, tr('Premium için önce giriş yap / hesap oluştur'));
    context.push('/login');
    return false;
  }

  Future<void> _subscribe() async {
    if (!_ensureLoggedIn()) return;
    // Gerçek satın alma için RevenueCat + seçili plana ait mağaza paketi şart.
    // Paket gelmediyse (offerings yüklenmedi / o plan mağazada tanımsız) satın
    // almayı başlatmadan kullanıcıyı bilgilendir.
    final pkg = _packageFor(_plan);
    if (!_rc || pkg == null) {
      showAdError(context,
          tr('Satın alma şu anda kullanılamıyor. Lütfen biraz sonra tekrar dene.'));
      return;
    }
    setState(() => _saving = true);
    try {
      final ok = await RevenueCatService.instance.purchase(pkg);
      if (ok) {
        unawaited(AnalyticsService.instance.log('purchase_completed', {'plan': _plan}));
        await ref.read(subscriptionRepositoryProvider).refresh();
        ref.invalidate(subscriptionProvider);
        if (mounted) {
          showAdToast(context, tr('Premium etkinleştirildi 🎉'));
          Navigator.maybePop(context);
        }
      } else if (mounted) {
        // Satın alma tamamlandı ama entitlement doğrulanamadı → yine de bilgilendir.
        setState(() => _saving = false);
        showAdError(context, tr('Satın alma doğrulanamadı. Satın alımları geri '
            'yüklemeyi dene veya destekle iletişime geç.'));
      }
    } on PlatformException catch (e) {
      // Kullanıcı satın almayı iptal ettiyse hata gösterme.
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (mounted) {
        setState(() => _saving = false);
        if (code != PurchasesErrorCode.purchaseCancelledError) {
          showAdError(context, tr('İşlem tamamlanamadı'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  String _planLabel(Subscription sub) {
    if (sub.isLifetime) return tr('Ömür boyu');
    if (sub.store == 'code') return tr('Kod ile etkinleştirildi');
    if (sub.store == 'dev') return tr('Geliştirme premium');
    final exp = sub.expiresAt;
    if (exp != null) {
      final d = fmtDayMonYear(exp.toLocal());
      return sub.willRenew
          ? trp('{d} tarihinde yenilenir', {'d': d})
          : trp('{d} tarihine kadar', {'d': d});
    }
    return tr('Premium');
  }

  /// Son kullanıcı aboneliğini iptal/yönet: cihazın mağaza abonelik sayfasını
  /// harici tarayıcıda/uygulamada açar (uygulama içinden iptal mümkün değildir —
  /// satın alma mağazada tutulur). Apple 3.1.2 / Google önerisi.
  Future<void> _manageSubscription() async {
    final uri = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse('https://play.google.com/store/account/subscriptions');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  /// Premium bitince kullanıcı-tetikli: önce cloud'u yerele indir (güvenlik),
  /// sonra bulut yedeğini kalıcı sil → abonelik free'ye düşer. Yerel veri kalır.
  Future<void> _purgeCloud() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bulut yedeğini sil')),
        content: Text(tr('Buluttaki yedeğin kalıcı olarak silinecek. Verilerin '
            'telefonunda kalmaya devam eder. Devam edilsin mi?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Vazgeç'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.coral, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('İndir ve sil')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // İndirme (tam sayfalama) + bulut silme süreci, yükleme ekranıyla aynı
    // tam-ekran overlay'de adım-adım gösterilir → kullanıcı boş spinner yerine
    // ne olduğunu görür (işlem yükleme kadar uzun sürebilir). Hata yönetimi ve
    // premiumSynced bayrağı runPurge/purgeCloudData içinde ele alınır.
    await ref.read(migrationControllerProvider.notifier).runPurge();
  }

  Future<void> _restore() async {
    setState(() => _saving = true);
    try {
      final ok = await RevenueCatService.instance.restore();
      if (ok) await ref.read(subscriptionRepositoryProvider).refresh();
      ref.invalidate(subscriptionProvider);
      if (mounted) {
        setState(() => _saving = false);
        showAdToast(context,
            ok ? tr('Satın alımlar geri yüklendi') : tr('Geri yüklenecek satın alma yok'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
  }

  Future<void> _redeem() async {
    if (!_ensureLoggedIn()) return;
    final code = await _showRedeemSheet(context);
    if (code == null || code.trim().isEmpty) return;
    try {
      await ref.read(subscriptionRepositoryProvider).redeem(code.trim());
      ref.invalidate(subscriptionProvider);
      if (mounted) {
        showAdToast(context, tr('Premium etkinleştirildi 🎉'));
        Navigator.maybePop(context);
      }
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  Future<String?> _showRedeemSheet(BuildContext context) async {
    final controller = TextEditingController();
    try {
      return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Premium kodu'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(tr('Sana verilen tek-kullanımlık kodu gir.'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3),
              decoration: InputDecoration(
                hintText: 'A1B2C3D4',
                filled: true,
                fillColor: AppColors.feedBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.coral,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: Text(tr('Kullan'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _TrustBadge extends StatelessWidget {
  final String text;
  const _TrustBadge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.growthBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdenaIcon('check', size: 12, color: Color(0xFF349970), sw: 2.6),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F8A5B))),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  const _InfoCard(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.feedBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.muted)),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String title;
  final String desc;
  final bool last;
  const _FeatureRow({required this.title, required this.desc, required this.last});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppColors.growthBg),
            alignment: Alignment.center,
            child: const AdenaIcon('check', size: 14, color: Color(0xFF349970), sw: 2.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.muted,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool selected;
  final String period;
  final String price;
  final String? originalPrice; // indirimdeyse üstü çizili eski fiyat
  final String sub;
  final String? tag;
  final bool wide;
  final VoidCallback onTap;
  const _PlanCard({
    required this.selected,
    required this.period,
    required this.price,
    required this.sub,
    required this.onTap,
    this.originalPrice,
    this.tag,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.feedBg : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: selected ? AppColors.coral : AppColors.line, width: 2),
      ),
      child: wide
          ? Row(
              children: [
                Text(period.toUpperCaseTr(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                        letterSpacing: 0.3)),
                const Spacer(),
                _priceText(),
              ],
            )
          : Column(
              children: [
                Text(period.toUpperCaseTr(),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                        letterSpacing: 0.3)),
                const SizedBox(height: 3),
                _priceText(),
              ],
            ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          if (tag != null)
            Positioned(
              top: -9,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                        colors: [AppColors.premiumGoldLight, AppColors.premiumGold]),
                  ),
                  child: Text(tag!,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.premiumInk)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _priceText() => Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          children: [
            if (originalPrice != null)
              TextSpan(
                  text: '$originalPrice ',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.lineThrough)),
            TextSpan(text: price),
            TextSpan(
                text: ' $sub',
                style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      );
}
