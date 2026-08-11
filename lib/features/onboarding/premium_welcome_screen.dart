import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/analytics_service.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/legal_links.dart';
import '../../core/revenuecat_service.dart';
import '../../core/theme.dart';
import '../../data/subscription_repository.dart';
import '../../models/baby.dart';
import '../../models/pricing.dart';
import '../babies/baby_controller.dart';

/// **Premium Karşılama Ekranı** (onboarding paywall) — bebek kurulumundan hemen
/// sonra bir kez açılan tam ekran modal. Tasarım: `design/AdenaBaby Mobile-handoff/
/// adenababy-mobile/project/Premium Karşılama Ekranı.html` (+ pw.css); ölçüler
/// oradan birebir (px = dp).
///
/// Profil → Premium sayfasından (PremiumScreen) bilinçli olarak FARKLI: uzun
/// özellik listesi yerine **Ücretsiz / Premium karşılaştırma kartları**, karşılama
/// tonunda başlık ve tek ekrana sığan yerleşim.
///
/// Kurallar (mağaza + ürün): × ilk kareden itibaren aktif, ikinci çıkış olarak
/// "Şimdi değil"; geri sayım/aciliyet dili YOK; kampanya/indirim YOK (normal
/// fiyatlar); geri yükleme + yasal linkler zorunlu olarak altta.
class PremiumWelcomeScreen extends ConsumerStatefulWidget {
  const PremiumWelcomeScreen({super.key});

  @override
  ConsumerState<PremiumWelcomeScreen> createState() =>
      _PremiumWelcomeScreenState();
}

class _PremiumWelcomeScreenState extends ConsumerState<PremiumWelcomeScreen> {
  String _plan = 'yearly'; // monthly|yearly|lifetime — yıllık ön seçili
  bool _busy = false; // satın alma/geri yükleme sürüyor
  String? _error; // CTA üstündeki uyarı şeridi
  Offering? _offering;

  bool get _rc => RevenueCatService.instance.isConfigured;

  @override
  void initState() {
    super.initState();
    _loadOffering();
    unawaited(AnalyticsService.instance.log('onboarding_paywall_shown', const {}));
  }

  Future<void> _loadOffering() async {
    final o = await RevenueCatService.instance.currentOffering();
    if (mounted) setState(() => _offering = o);
  }

  // ── veri yardımcıları ───────────────────────────────────────────────

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

  /// Gösterilecek fiyat: 1) mağaza (RC, bölgeye göre gerçek), 2) backend DB
  /// fiyatı, 3) null → iskelet (shimmer) gösterilir. PremiumScreen ile aynı
  /// öncelik; buradaki fark: son çare placeholder YOK — uydurma fiyat yerine
  /// yükleniyor durumu gösterilir.
  String? _price(String plan, Map<String, PlanPricing> pricing) {
    final store = _packageFor(plan)?.storeProduct.priceString;
    if (store != null && store.isNotEmpty) return store;
    final pp = pricing[plan];
    if (pp != null && pp.price.isNotEmpty) return pp.price;
    return null;
  }

  /// Yıllık planın aylığa bölünmüş yaklaşık karşılığı ("aylık ~₺29").
  /// Yalnız mağaza paketi (gerçek tutar + para birimi kodu) varsa hesaplanır;
  /// biçimlendirme cihaz diline göre yapılır. En ufak sorunda null döner →
  /// çağıran yerine nötr bir açıklama koyar (uydurma fiyat göstermeyiz).
  String? _perMonth() {
    try {
      final p = _packageFor('yearly')?.storeProduct;
      if (p == null || p.price <= 0) return null;
      final f = NumberFormat.simpleCurrency(
          locale: I18n.instance.locale, name: p.currencyCode);
      return trp('aylık ~{p}', {'p': f.format(p.price / 12)});
    } catch (_) {
      return null;
    }
  }

  String _planName(String plan) => switch (plan) {
        'monthly' => tr('Aylık'),
        'lifetime' => tr('Ömürlük'),
        _ => tr('Yıllık'),
      };

  String _planDesc(String plan) => switch (plan) {
        'monthly' => tr('her ay'),
        'lifetime' => tr('tek seferlik'),
        _ => _perMonth() ?? tr('yılda bir'),
      };

  // ── eylemler ────────────────────────────────────────────────────────

  void _close({required String how}) {
    unawaited(
        AnalyticsService.instance.log('onboarding_paywall_dismissed', {'how': how}));
    Navigator.of(context).maybePop();
  }

  Future<void> _subscribe() async {
    final pkg = _packageFor(_plan);
    if (!_rc || pkg == null) {
      setState(() => _error =
          tr('Satın alma şu anda kullanılamıyor. Lütfen biraz sonra tekrar dene.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await RevenueCatService.instance.purchase(pkg);
      if (ok) {
        unawaited(AnalyticsService.instance
            .log('purchase_completed', {'plan': _plan, 'source': 'onboarding'}));
        await ref.read(subscriptionRepositoryProvider).refresh();
        ref.invalidate(subscriptionProvider);
        if (mounted) {
          showAdToast(context, tr('Premium etkinleştirildi 🎉'));
          Navigator.of(context).maybePop();
        }
        return;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('Satın alma doğrulanamadı. Satın alımları geri yüklemeyi '
              'dene veya destekle iletişime geç.');
        });
      }
    } on PlatformException catch (e) {
      // Kullanıcı vazgeçtiyse hata gösterme — sessizce normale dön.
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = code == PurchasesErrorCode.purchaseCancelledError
              ? null
              : tr('Satın alma tamamlanamadı, tekrar dene.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorText(e);
        });
      }
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await RevenueCatService.instance.restore();
      if (ok) await ref.read(subscriptionRepositoryProvider).refresh();
      ref.invalidate(subscriptionProvider);
      if (!mounted) return;
      setState(() => _busy = false);
      showAdToast(
          context,
          ok
              ? tr('Satın alımlar geri yüklendi')
              : tr('Geri yüklenecek satın alma yok'));
      if (ok) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiErrorText(e);
        });
      }
    }
  }

  // ── yerleşim ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(activeBabyProvider);
    final pricing =
        ref.watch(pricingProvider).asData?.value ?? const <String, PlanPricing>{};
    final dark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // Sistem geri tuşu da "kapat" sayılır (tek-kez bayrağı zaten tüketildi).
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    children: [
                      _hero(baby),
                      _comparison(dark),
                      const SizedBox(height: 12),
                      _coreFreeNote(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _plans(pricing, dark),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: _footer(dark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Üst bar: yalnız × (44×44 dokunma alanı, ilk kareden itibaren aktif).
  Widget _topBar() => SizedBox(
        height: 44,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Opacity(
              opacity: _busy ? .45 : 1,
              child: InkResponse(
                radius: 26,
                onTap: _busy ? null : () => _close(how: 'x'),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.ink.withValues(alpha: .055),
                  ),
                  alignment: Alignment.center,
                  child: AdenaIcon('close',
                      size: 19, color: AppColors.muted, sw: 2.2),
                ),
              ),
            ),
          ),
        ),
      );

  /// Hero: altın rozet + kişiselleştirilmiş başlık (bebeğin adı vurgulu).
  Widget _hero(Baby? baby) {
    final expecting = baby?.isExpecting ?? false;
    final name = (baby?.name ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 16),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
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
            child: const AdenaIcon('star', size: 29, color: Colors.white, sw: 2),
          ),
          const SizedBox(height: 13),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: _title(expecting: expecting, name: name),
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 296),
            child: Text(
              expecting
                  ? tr('Adena Premium ile hazırlıklarını tek yerde topla, doğduğu '
                      'an her şey hazır olsun.')
                  : tr('Adena Premium ile her anı reklamsız kaydet, tüm aile aynı '
                      'yerde olsun.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.42,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// Başlık — takip modunda bebeğin adı mercan renkli vurgulanır; ad yoksa
  /// nötr varyant. Uzun ad 2 satıra sarar, 3. satırda kesilir.
  Widget _title({required bool expecting, required String name}) {
    const style = TextStyle(
        fontSize: 22, fontWeight: FontWeight.w900, height: 1.22, letterSpacing: -.4);
    if (expecting) {
      return Text(tr('Bebeğin gelmeden hazır ol'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: AppColors.ink));
    }
    if (name.isEmpty) {
      return Text(tr('Bebeğin için en iyisi'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(color: AppColors.ink));
    }
    // "{ad} için en iyisi" — ad vurgulu. Yer tutucu, çeviride cümlenin
    // başında/sonunda olabilir (ör. Arapça'da sonda), o yüzden metni bölerek
    // kuruyoruz.
    final full = trp('{name} için en iyisi', {'name': name});
    final i = full.indexOf(name);
    final spans = i < 0
        ? [TextSpan(text: full)]
        : [
            if (i > 0) TextSpan(text: full.substring(0, i)),
            TextSpan(
                text: name,
                style: const TextStyle(color: AppColors.coralDd)),
            if (i + name.length < full.length)
              TextSpan(text: full.substring(i + name.length)),
          ];
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(color: AppColors.ink),
    );
  }

  /// Karşılaştırma: solda beyaz "Ücretsiz" kartı, sağda 10 dp yukarı taşan
  /// altın "Premium" kartı. Satır yükseklikleri (46) iki kartta da aynı →
  /// satırlar birbirini tutar.
  Widget _comparison(bool dark) {
    final rows = _rows;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
              boxShadow: dark ? null : AppColors.softShadow,
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 38,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(tr('ÜCRETSİZ'),
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                            color: AppColors.muted)),
                  ),
                ),
                for (var i = 0; i < rows.length; i++)
                  _FreeRow(row: rows[i], last: i == rows.length - 1),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Transform.translate(
          offset: const Offset(0, -10),
          child: Container(
            width: 100,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? [
                        AppColors.premiumGold.withValues(alpha: .15),
                        AppColors.premiumGold.withValues(alpha: .06),
                      ]
                    : const [Color(0xFFFFF9EA), AppColors.premiumBg],
              ),
              border: Border.all(
                color: dark
                    ? AppColors.premiumGold.withValues(alpha: .3)
                    : AppColors.premiumGoldLight,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: dark
                      ? const Color(0x66000000)
                      : const Color(0xFFFFB43C).withValues(alpha: .28),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  child: Center(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.premiumGoldLight,
                            AppColors.premiumGold
                          ],
                        ),
                      ),
                      // Rozet kartın (100 dp) içine sığmak zorunda; "Premium"
                      // karşılığı uzun olan dillerde (ör. Arapça "بريميوم")
                      // metin küçülerek sığar, kırpılmaz.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AdenaIcon('star',
                              size: 11, color: AppColors.premiumInk, sw: 2.4),
                          const SizedBox(width: 4),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(tr('Premium'),
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.premiumInk)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (var i = 0; i < rows.length; i++)
                  _PremiumRow(
                      label: rows[i].premium,
                      last: i == rows.length - 1,
                      dark: dark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Tablonun altındaki güvence şeridi: yukarıdaki satırlar premium'a ÖZEL
  /// olanlar; uygulamanın çekirdeği (kayıt tutma, günlük akış, grafikler)
  /// ücretsizde de sınırsız. Bu not olmadan tablo "ücretsizde neredeyse hiçbir
  /// şey yok" gibi okunuyordu — hem yanıltıcı hem caydırıcı.
  Widget _coreFreeNote() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.peachLight,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            const AdenaIcon('heart', size: 16, color: AppColors.coralDd, sw: 2.2),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                tr('Kayıt tutma, günlük akış ve grafikler ücretsizde de '
                    'sınırsız — Premium bunların üstüne ekler.'),
                style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: AppColors.coralDd),
              ),
            ),
          ],
        ),
      );

  /// Karşılaştırma satırları — hepsi kodda doğrulanmış gerçek kısıtlar:
  /// reklam (ad_banner), aile paylaşımı + PDF rapor (premium_gate), bulut
  /// yedekleme (sync_gate), özel hatırlatıcı limiti (reminders_screen).
  List<_Row> get _rows => [
        _Row('shield', tr('Reklamsız kullanım'), tr('Reklamlı'), tr('Reklamsız')),
        _Row('family', tr('Aile & bakıcı paylaşımı'), null, tr('Sınırsız')),
        _Row('cloud', tr('Bulut yedekleme'), null, tr('Otomatik')),
        _Row('doc', tr('Doktora hazır PDF rapor'), null, null),
        _Row('bell', tr('Hatırlatıcılar'), tr('2 tane'), tr('Sınırsız')),
      ];

  /// Plan seçimi: 3 kart, yıllık ön seçili + "En popüler" rozeti.
  Widget _plans(Map<String, PlanPricing> pricing, bool dark) {
    const plans = ['monthly', 'yearly', 'lifetime'];
    // IntrinsicHeight: üç kart en uzunun boyuna eşitlenir (fiyat metinleri
    // farklı satır sayısına düşse bile hizalı kalır). Row + stretch tek başına
    // sonsuz yükseklik ister → Column içinde patlar.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in plans) ...[
            if (p != plans.first) const SizedBox(width: 8),
            Expanded(
              child: _PlanCard(
                name: _planName(p),
                price: _price(p, pricing),
                desc: _planDesc(p),
                selected: _plan == p,
                badge: p == 'yearly' ? tr('En popüler') : null,
                onTap: _busy ? null : () => setState(() => _plan = p),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Alt bölge: (hata şeridi) + CTA + mikro metin + "Şimdi değil" + yasal.
  Widget _footer(bool dark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF3A2622) : const Color(0xFFFFEEE6),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                  color: dark ? const Color(0xFF513127) : const Color(0xFFF7D6C6)),
            ),
            child: Row(
              children: [
                AdenaIcon('shieldAlert',
                    size: 16,
                    color: dark ? const Color(0xFFFFB69E) : const Color(0xFFC25236),
                    sw: 2.2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                          color: dark
                              ? const Color(0xFFFFB69E)
                              : const Color(0xFFC25236))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Opacity(
          opacity: _busy ? .62 : 1,
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.coral, AppColors.coralDark],
                ),
                boxShadow: _busy
                    ? null
                    : const [
                        BoxShadow(
                            color: Color(0x47E2553F),
                            blurRadius: 20,
                            offset: Offset(0, 8)),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _busy ? null : _subscribe,
                  child: Center(
                    child: _busy
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white),
                          )
                        : Text(tr("Premium'a Geç"),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          tr('İstediğin zaman iptal edebilirsin. Ömürlük plan tek seferlik '
              'ödemedir.'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: AppColors.muted),
        ),
        TextButton(
          onPressed: _busy ? null : () => _close(how: 'not_now'),
          child: Text(tr('Şimdi değil'),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted)),
        ),
        // Mağaza zorunluları: geri yükleme + EULA + gizlilik (Apple 3.1.2(c)).
        Opacity(
          opacity: _busy ? .45 : 1,
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 7,
            children: [
              if (_rc || Platform.isIOS)
                _MicroLink(
                    label: tr('Satın alımları geri yükle'),
                    onTap: _busy ? null : _restore),
              const _MicroDot(),
              _MicroLink(
                  label: tr('Kullanım Koşulları'),
                  onTap:
                      _busy ? null : () => openLegalDoc(context, LegalDoc.terms)),
              const _MicroDot(),
              _MicroLink(
                  label: tr('Gizlilik'),
                  onTap: _busy
                      ? null
                      : () => openLegalDoc(context, LegalDoc.privacy)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tablo satırı verisi. [free]/[premium] null ise: ücretsizde "—", premium'da
/// yalnız ✓ gösterilir.
class _Row {
  final String icon;
  final String feature;
  final String? free;
  final String? premium;
  const _Row(this.icon, this.feature, this.free, this.premium);
}

class _FreeRow extends StatelessWidget {
  const _FreeRow({required this.row, required this.last});

  final _Row row;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: AppColors.peachLight,
            ),
            alignment: Alignment.center,
            child: AdenaIcon(row.icon,
                size: 15, color: AppColors.coralDd, sw: 2.2),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(row.feature,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
          ),
          SizedBox(
            width: 52,
            child: Center(
              child: row.free == null
                  ? Text('—',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.muted2))
                  : Text(row.free!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink2)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumRow extends StatelessWidget {
  const _PremiumRow(
      {required this.label, required this.last, required this.dark});

  final String? label;
  final bool last;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFFFD98A) : AppColors.premiumInk;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                    color: dark
                        ? AppColors.premiumGold.withValues(alpha: .14)
                        : AppColors.premiumInk.withValues(alpha: .12),
                    width: 1),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const AdenaIcon('check',
              size: 14, color: AppColors.premiumGold, sw: 2.6),
          if (label != null) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w900, color: ink)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Plan kartı. [price] null ise fiyat/açıklama yerine iskelet (shimmer) çizilir
/// — mağaza fiyatı gelene kadar uydurma tutar göstermeyiz.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.desc,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String name;
  final String? price;
  final String desc;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      // passthrough: kart, IntrinsicHeight'ın verdiği ortak yüksekliği doldurur
      // (üç kartın kenarlıkları hizalı kalır).
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: selected ? 5 : 6, vertical: selected ? 10 : 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected ? AppColors.peachLight : Colors.transparent,
              border: Border.all(
                color: selected ? AppColors.coral : AppColors.line2,
                width: selected ? 2 : 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name.toUpperCaseTr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                        color: selected ? AppColors.coralDd : AppColors.muted)),
                const SizedBox(height: 2),
                if (price == null)
                  const _Skeleton(width: 58, height: 15)
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(price!,
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 16,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                            color: AppColors.ink)),
                  ),
                const SizedBox(height: 2),
                if (price == null)
                  const _Skeleton(width: 40, height: 9)
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(desc,
                        maxLines: 1,
                        style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted)),
                  ),
              ],
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            top: -9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.premiumGoldLight, AppColors.premiumGold],
                ),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.premiumInk)),
            ),
          ),
      ],
    );
  }
}

/// Fiyat iskeleti (mağaza yanıtı beklenirken).
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.line,
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

class _MicroLink extends StatelessWidget {
  const _MicroLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted2)),
      );
}

class _MicroDot extends StatelessWidget {
  const _MicroDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.muted2.withValues(alpha: .6),
        ),
      );
}
