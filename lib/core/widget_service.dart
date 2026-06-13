import 'package:home_widget/home_widget.dart';

/// Ana ekran (home screen) widget'ı köprüsü — "son beslenme".
///
/// Uygulama, aktif bebeğin son beslenme zamanını paylaşımlı depoya yazar; native
/// widget (Android `FeedWidgetProvider`, iOS `FeedWidget`) bu veriyi okuyup
/// "X önce" diye gösterir. Göreli zamanı native taraf hesaplar (widget kendi
/// başına da yenilenebilsin diye mutlak zaman damgası saklanır).
///
/// Güncelleme tetikleri: uygulama açıkken kayıt değişimi (FamilyNotificationSync,
/// reaktif) ve ileride push (arka plan handler). Widget yoksa/desteklenmiyorsa
/// tüm çağrılar sessizce yutulur.
class WidgetService {
  // iOS App Group — Xcode'da Widget Extension + ana uygulamada aynı grup tanımlı olmalı.
  static const _appGroupId = 'group.com.adenababy.adena_baby';
  static const _qualifiedAndroidName = 'com.adenababy.adena_baby.FeedWidgetProvider';

  static bool _inited = false;

  static Future<void> _ensureInit() async {
    if (_inited) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    _inited = true;
  }

  /// Aktif bebeğin son beslenmesini widget'a yaz ve yenile.
  /// [lastFeed] null ise widget "henüz kayıt yok" gösterir.
  static Future<void> updateLastFeed({
    required String babyName,
    DateTime? lastFeed,
  }) async {
    try {
      await _ensureInit();
      await HomeWidget.saveWidgetData<String>('baby_name', babyName);
      // String olarak sakla → Android/iOS tip belirsizliği olmasın (Kotlin/Swift parse eder).
      await HomeWidget.saveWidgetData<String>(
        'last_feed_ms',
        (lastFeed?.millisecondsSinceEpoch ?? -1).toString(),
      );
      await HomeWidget.updateWidget(
        androidName: 'FeedWidgetProvider',
        qualifiedAndroidName: _qualifiedAndroidName,
        iOSName: 'FeedWidget',
      );
    } catch (_) {
      // Widget eklenmemiş / platform desteklemiyor → yoksay.
    }
  }
}
