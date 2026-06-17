import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'subscription_repository.dart';

/// Local-first mimarinin merkez bayrağı: **cloud senkron yalnız oturum açık VE
/// premium iken**. Free kullanıcı (hesaplı ya da hesapsız) yerel-önce çalışır,
/// kullanıcı verisi (bebek/kayıt/anı/anne/adet) telefonda kalır, ağa gitmez.
///
/// İstisnalar bu bayrağa tabi DEĞİL (her zaman cloud): topluluk (soru-cevap),
/// içerik/çeviri/medya (haftalık görsel, WHO LMS, makaleler, aşı takvimi).
final cloudSyncEnabledProvider = Provider<bool>((ref) {
  final loggedIn = ref.watch(authControllerProvider).asData?.value != null;
  final premium = ref.watch(isPremiumProvider);
  return loggedIn && premium;
});
