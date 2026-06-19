import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:adena_baby/core/api_client.dart';
import 'package:adena_baby/core/token_storage.dart';
import 'package:adena_baby/data/subscription_repository.dart';

class _FakeTokens implements TokenStorage {
  @override
  Future<String?> get accessToken async => 'fake-access';
  @override
  Future<String?> get refreshToken async => 'fake-refresh';
  @override
  Future<bool> get hasSession async => true;
  @override
  Future<void> saveTokens({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
}

// NOT (RevenueCat SDK): SubscriptionRepository'nin purchases_flutter (RevenueCat)
// doğrudan SDK çağrısı YOKTUR — repository tamamen ApiClient üzerinden çalışır.
// SDK etkileşimi `premiumSyncProvider` (provider, RevenueCatService dinleyicisi)
// içinde; o native SDK'ya bağlı olduğundan unit-test edilmez ve burada atlanır.
// Bu dosya repository'nin tüm API-destekli uçlarını test eder.
//
// _store() her yanıtta SubscriptionCache (FlutterSecureStorage) ve pricing()
// JsonCache (path_provider) platform kanallarına dokunur; ikisi de try/catch +
// unawaited ile sarılı. Yine de gürültüyü engellemek için kanalları stub'larız.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // flutter_secure_storage kanalını sahte yap (SubscriptionCache.write).
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    // path_provider kanalını sahte yap (JsonCache).
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/adena-test',
    );
  });

  late ApiClient api;
  late DioAdapter adapter;
  late SubscriptionRepository repo;

  setUp(() {
    api = ApiClient(_FakeTokens());
    adapter = DioAdapter(dio: api.dio);
    repo = SubscriptionRepository(api);
  });

  Map<String, dynamic> subJson({
    String tier = 'premium',
    bool isPremium = true,
    String? expiresAt = '2099-01-01T00:00:00Z',
  }) =>
      {
        'tier': tier,
        'platform': 'android',
        'store': 'play',
        'product_id': 'adena_yearly',
        'expires_at': expiresAt,
        'will_renew': true,
        'is_premium': isPremium,
      };

  test('get() GET /auth/me/subscription + parse', () async {
    adapter.onGet('/auth/me/subscription', (s) => s.reply(200, subJson()));

    final sub = await repo.get();
    expect(sub.tier, 'premium');
    expect(sub.isPremium, isTrue);
    expect(sub.platform, 'android');
    expect(sub.productId, 'adena_yearly');
    expect(sub.willRenew, isTrue);
  });

  test('get() free tier parse', () async {
    adapter.onGet(
      '/auth/me/subscription',
      (s) => s.reply(200, {'tier': 'free', 'is_premium': false}),
    );

    final sub = await repo.get();
    expect(sub.tier, 'free');
    expect(sub.isPremium, isFalse);
  });

  test('refresh() POST /auth/me/subscription/refresh + parse', () async {
    adapter.onPost('/auth/me/subscription/refresh', (s) => s.reply(200, subJson()));

    final sub = await repo.refresh();
    expect(sub.isPremium, isTrue);
    expect(sub.tier, 'premium');
  });

  test('redeem(code) POST payload + parse', () async {
    adapter.onPost(
      '/auth/me/subscription/redeem',
      (s) => s.reply(200, subJson(tier: 'premium', expiresAt: null)),
      data: {'code': 'GIFT-123'},
    );

    final sub = await repo.redeem('GIFT-123');
    expect(sub.isPremium, isTrue);
    // expires_at null + premium → lifetime.
    expect(sub.isLifetime, isTrue);
  });

  test('purgeCloudData() POST /auth/me/cloud-data/purge + parse', () async {
    adapter.onPost(
      '/auth/me/cloud-data/purge',
      (s) => s.reply(200, {'tier': 'free', 'is_premium': false}),
    );

    final sub = await repo.purgeCloudData();
    expect(sub.tier, 'free');
    expect(sub.isPremium, isFalse);
  });

  test('devActivate() varsayılan payload (lifetime/active) + parse', () async {
    adapter.onPost(
      '/auth/me/subscription/dev-activate',
      (s) => s.reply(200, subJson(tier: 'premium', expiresAt: null)),
      data: {'plan': 'lifetime', 'active': true},
    );

    final sub = await repo.devActivate();
    expect(sub.isPremium, isTrue);
  });

  test('devActivate() özel payload', () async {
    adapter.onPost(
      '/auth/me/subscription/dev-activate',
      (s) => s.reply(200, {'tier': 'free', 'is_premium': false}),
      data: {'plan': 'monthly', 'active': false},
    );

    final sub = await repo.devActivate(plan: 'monthly', active: false);
    expect(sub.isPremium, isFalse);
  });

  test('pricing() GET /pricing/plans → plan→PlanPricing map', () async {
    adapter.onGet(
      '/pricing/plans',
      (s) => s.reply(200, {
        'plans': [
          {
            'plan': 'monthly',
            'price': '₺59',
            'on_sale': false,
            'badge': '',
          },
          {
            'plan': 'yearly',
            'price': '₺590',
            'original_price': '₺708',
            'on_sale': true,
            'discount_percent': 17,
            'badge': '%17 indirim',
          },
        ],
      }),
    );

    final map = await repo.pricing();
    expect(map.keys, containsAll(['monthly', 'yearly']));
    expect(map['monthly']!.price, '₺59');
    expect(map['yearly']!.onSale, isTrue);
    expect(map['yearly']!.discountPercent, 17);
    expect(map['yearly']!.originalPrice, '₺708');
  });

  test('aiExport() POST payload + summary_text parse', () async {
    adapter.onPost(
      '/babies/b1/ai-export',
      (s) => s.reply(200, {'summary_text': 'Özet metni'}),
      data: {'days': 7},
    );

    final out = await repo.aiExport('b1', 7);
    expect(out, 'Özet metni');
  });

  test('aiExport() summary_text yoksa boş string', () async {
    adapter.onPost(
      '/babies/b1/ai-export',
      (s) => s.reply(200, {}),
      data: {'days': 3},
    );

    final out = await repo.aiExport('b1', 3);
    expect(out, '');
  });
}
