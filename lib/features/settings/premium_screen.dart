import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../models/subscription.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/revenuecat_service.dart';
import '../../core/theme.dart';
import '../../data/subscription_repository.dart';

/// Premium / paywall (design ScrPremium): özellik listesi + planlar + CTA + kod.
///
/// İki mod: RevenueCat yapılandırılmışsa gerçek satın alma (offerings paketleri);
/// değilse GELİŞTİRME modu — "satın al" backend dev-activate ile sahte premium
/// verir (token gelene kadar). Her iki modda tek-kullanımlık "kod" da çalışır.
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
  }

  Future<void> _loadOffering() async {
    final o = await RevenueCatService.instance.currentOffering();
    if (mounted) setState(() => _offering = o);
  }

  // NOT: getter — `static final` tr()'yi dondurur (dil değişince eski kalır).
  List<(String, String)> get _feats => [
        (tr('Reklamsız deneyim'), tr('Hiç reklam yok, kesintisiz')),
        (tr('Aile paylaşımı'), tr('Eş + bakıcılar aynı bebeği takip eder')),
        (tr('Gelişmiş grafik + PDF'), tr('Doktora hazır rapor çıktısı')),
        (tr('Sınırsız hatırlatıcı'), tr('İstediğin kadar özel hatırlatıcı')),
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

  /// RC paketi varsa mağaza fiyatı; yoksa geliştirme placeholder fiyatı.
  String _price(String plan, String fallback) =>
      _packageFor(plan)?.storeProduct.priceString ?? fallback;

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider).asData?.value;
    final isPremium = sub?.isPremium ?? false;

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
              Text(tr('Ücretsiz katman zaten cömert — Premium ekstra güç katar.'),
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
            // İptal notu (isteğe bağlı bilgi). Abonelik iptali mağaza üzerinden olur.
            if (sub?.willRenew ?? false)
              _InfoCard(tr('Aboneliğini istediğin zaman telefonunun App Store / '
                  'Google Play hesabından iptal edebilirsin. İptal etsen bile mevcut '
                  'dönemin sonuna kadar Premium açık kalır.'))
            else if (sub?.isLifetime ?? false)
              _InfoCard(tr('Ömür boyu premium — yenileme yok, iptal gerekmez 💛'))
            else
              _InfoCard(tr('Bu premium bir kod/deneme ile verildi; süresi dolunca '
                  'otomatik olarak ücretsiz katmana döner.')),
            // GELİŞTİRME: token yokken premium'u test için kapatma.
            if (!_rc) ...[
              const SizedBox(height: 8),
              AdSaveButton(
                label: _saving ? tr('İşleniyor…') : tr('Premium\'u kapat (geliştirme)'),
                color: AppColors.muted,
                ghost: true,
                onTap: _saving ? () {} : _devDeactivate,
              ),
            ],
          ] else ...[
            const SizedBox(height: 14),
            // Aylık + Yıllık yan yana
            Row(
              children: [
                Expanded(
                  child: _PlanCard(
                    selected: _plan == 'monthly',
                    period: tr('Aylık'),
                    price: _price('monthly', '₺79'),
                    sub: tr('/ay'),
                    onTap: () => setState(() => _plan = 'monthly'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PlanCard(
                    selected: _plan == 'yearly',
                    period: tr('Yıllık'),
                    price: _price('yearly', '₺590'),
                    sub: tr('/yıl'),
                    tag: tr('2 ay bedava'),
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
              price: _price('lifetime', '₺1.490'),
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
            if (!_rc) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  tr('Geliştirme modu · satın alma sahte (mağaza bağlanınca gerçek olur)'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
                ),
              ),
            ],
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

  Future<void> _subscribe() async {
    setState(() => _saving = true);
    try {
      final pkg = _packageFor(_plan);
      if (_rc && pkg != null) {
        final ok = await RevenueCatService.instance.purchase(pkg);
        if (ok) await ref.read(subscriptionRepositoryProvider).refresh();
      } else {
        // Geliştirme modu — backend dev-activate ile sahte premium.
        await ref.read(subscriptionRepositoryProvider).devActivate(plan: _plan);
      }
      ref.invalidate(subscriptionProvider);
      if (mounted) {
        showAdToast(context, tr('Premium etkinleştirildi 🎉'));
        Navigator.maybePop(context);
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
      final d = DateFormat('d MMM yyyy', 'tr_TR').format(exp.toLocal());
      return sub.willRenew
          ? trp('{d} tarihinde yenilenir', {'d': d})
          : trp('{d} tarihine kadar', {'d': d});
    }
    return tr('Premium');
  }

  /// GELİŞTİRME: backend dev-activate(active:false) ile premium'u kapat (test).
  Future<void> _devDeactivate() async {
    setState(() => _saving = true);
    try {
      await ref.read(subscriptionRepositoryProvider).devActivate(active: false);
      ref.invalidate(subscriptionProvider);
      if (mounted) {
        setState(() => _saving = false);
        showAdToast(context, tr('Premium kapatıldı'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showAdError(context, apiErrorText(e));
      }
    }
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

  Future<String?> _showRedeemSheet(BuildContext context) {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
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
                Text(period.toUpperCase(),
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
                Text(period.toUpperCase(),
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
