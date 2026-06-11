import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../models/subscription.dart';

/// Abonelik + AI dışa aktarım uçları (API §9).
class SubscriptionRepository {
  final ApiClient _api;
  SubscriptionRepository(this._api);

  Future<Subscription> get() async {
    final resp = await _api.dio.get('/me/subscription');
    return Subscription.fromJson(resp.data as Map<String, dynamic>);
  }

  /// IAP makbuz doğrulama (backend şimdilik stub → premium'a yükseltir).
  Future<Subscription> verify({required String platform}) async {
    final resp =
        await _api.dio.post('/me/subscription/verify', data: {'platform': platform});
    return Subscription.fromJson(resp.data as Map<String, dynamic>);
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

/// Mevcut abonelik durumu. Satın alma sonrası invalidate edilir.
final subscriptionProvider = FutureProvider<Subscription>(
  (ref) => ref.watch(subscriptionRepositoryProvider).get(),
);
