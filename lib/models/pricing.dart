/// Backend'den gelen yönetilebilir plan fiyatı + indirim bilgisi (GET /pricing/plans).
/// Gerçek satın alma fiyatı mağazadan (RevenueCat) gelir; bu, gösterim/fallback
/// fiyatı ile indirim rozetini/üstü çizili eski fiyatı taşır.
class PlanPricing {
  final String plan; // monthly|yearly|lifetime
  final String price; // güncel (gösterim) fiyat, locale'e göre biçimli (₺590 / $39.99)
  final String? originalPrice; // indirimdeyse üstü çizili eski fiyat
  final bool onSale;
  final int? discountPercent;
  final String badge; // ör. "%34 indirim" / "Save 34%"

  const PlanPricing({
    required this.plan,
    required this.price,
    this.originalPrice,
    this.onSale = false,
    this.discountPercent,
    this.badge = '',
  });

  factory PlanPricing.fromJson(Map<String, dynamic> j) => PlanPricing(
        plan: j['plan'] as String,
        price: (j['price'] as String?) ?? '',
        originalPrice: j['original_price'] as String?,
        onSale: (j['on_sale'] as bool?) ?? false,
        discountPercent: (j['discount_percent'] as num?)?.toInt(),
        badge: (j['badge'] as String?) ?? '',
      );
}
