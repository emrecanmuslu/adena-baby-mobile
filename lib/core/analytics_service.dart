import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../data/local_session.dart';

/// İnce Firebase Analytics sarmalayıcı — **consent-gated** ve **içeriksiz**.
///
/// İlke ([[acik-riza-yas-kapisi]]): toplama VARSAYILAN KAPALI; yalnız kullanıcı
/// açık rıza verirse (`LocalSession.analyticsConsent`) açılır. Debug build'de her
/// zaman kapalı (Crashlytics ile aynı yaklaşım) → geliştirme verisi paneli
/// kirletmez. Bölge gerekirse buradan opt-in zorunluya çevrilebilir (AB/AEA).
///
/// **Olaylar İÇERİKSİZDİR:** bebek adı/ölçüm değeri/tarih/not/serbest metin asla
/// parametre olmaz; yalnız düşük-kardinaliteli etiketler (tür, kaynak, sayfa,
/// segment). Tüm metotlar toplama kapalıyken sessiz no-op'tur.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _fa;

  /// Toplama yalnız: Firebase hazır + kullanıcı rıza verdi + release build.
  bool get _enabled =>
      _fa != null && LocalSession.analyticsConsent && !kDebugMode;

  /// main()'de bir kez (Firebase init sonrası). Mevcut rızaya göre toplamayı
  /// ayarlar. Hata uygulamayı engellemez.
  Future<void> init() async {
    try {
      _fa = FirebaseAnalytics.instance;
      await _applyConsent();
    } catch (_) {}
  }

  Future<void> _applyConsent() async {
    final fa = _fa;
    if (fa == null) return;
    final on = LocalSession.analyticsConsent && !kDebugMode;
    try {
      await fa.setAnalyticsCollectionEnabled(on);
    } catch (_) {}
  }

  /// Kullanıcı rızası değişince (onboarding checkbox / ayarlar toggle) çağrılır;
  /// kalıcılaştırır ve toplamayı anında açar/kapatır.
  Future<void> setConsent(bool granted) async {
    await LocalSession.setAnalyticsConsent(granted);
    await _applyConsent();
  }

  /// İçeriksiz olay. [params] yalnız düşük-kardinaliteli etiketler içermeli
  /// (tür/kaynak/sayfa) — değerler String veya num; PII/sağlık verisi GÖNDERME.
  Future<void> log(String name, [Map<String, Object?>? params]) async {
    if (!_enabled) return;
    try {
      await _fa!.logEvent(
        name: name,
        parameters: params == null
            ? null
            : <String, Object>{
                for (final e in params.entries)
                  if (e.value != null) e.key: e.value!,
              },
      );
    } catch (_) {}
  }

  /// Ekran görüntüleme olayı (manuel; `screen_name`).
  Future<void> logScreen(String screen) async {
    if (!_enabled) return;
    try {
      await _fa!.logScreenView(screenName: screen);
    } catch (_) {}
  }

  /// Düşük-kardinaliteli kullanıcı segmenti (region/locale/is_premium/baby_mode/
  /// theme). Kimlik/PII DEĞİL. [value] null → özelliği temizler.
  Future<void> setUserProperty(String name, String? value) async {
    if (!_enabled) return;
    try {
      await _fa!.setUserProperty(name: name, value: value);
    } catch (_) {}
  }
}
