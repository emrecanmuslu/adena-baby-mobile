class AppConfig {
  /// API taban adresi.
  /// - Android emülatör → host makineye `10.0.2.2` ile erişir.
  /// - Fiziksel cihaz → PC'nin LAN IP'si (ör. http://192.168.1.X:8000/api/v1).
  /// `--dart-define=API_BASE_URL=...` ile override edilebilir.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
}
