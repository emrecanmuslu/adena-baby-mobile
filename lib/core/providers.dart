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

/// Yerel drift veritabanı (offline-first kayıt deposu).
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
