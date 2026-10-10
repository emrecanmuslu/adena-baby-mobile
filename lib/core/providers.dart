import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/app_database.dart';
import 'api_client.dart';
import 'token_storage.dart';

/// Güvenli token deposu (tek örnek).
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Dio tabanlı API istemcisi (JWT interceptor + 401 refresh).
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(tokenStorageProvider)),
);

/// Bu container bir ARKA PLAN isolate'inde mi çalışıyor (workmanager/BGTask,
/// FCM arka plan işleyicisi)? Arka plan container'ları bunu `true` ile
/// override eder; ön plan varsayılanı `false`. `true` iken uzun süreli/ön plana
/// ait yan işler (AuthController'ın `/auth/me` tazelemesi + ilk import,
/// RevenueCat identify, exitGuest) HİÇ başlatılmaz — bkz. BULGULAR.md K9.
final runningInBackgroundProvider = Provider<bool>((_) => false);

/// Yerel drift veritabanı (offline-first kayıt deposu).
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
