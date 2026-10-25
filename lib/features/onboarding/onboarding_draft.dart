import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Yarım kalan kurulumun taslağı — uygulama kapatılır ya da sistem arka
/// plandaki süreci öldürürse kullanıcı karşılamaya değil KALDIĞI forma, girdiği
/// bilgilerle döner. Hedef seçilince yazılır, kurulum tamamlanınca silinir.
///
/// Tek JSON değeri: `{route, fields:{...}}`. Alanlar ekrana özgüdür (bebek
/// profili: ad/tarih/cinsiyet…; adet: son adet/döngü süresi).
class OnboardingDraft {
  OnboardingDraft._();

  static const _k = 'onboarding_draft_v1';

  /// clear/start her çağrıda artar: araya giren (önceden başlamış) asenkron
  /// saveFields yazımı, kurulum bitip taslak silindikten SONRA onu geri
  /// yaratmasın (eski bebeğin bilgileriyle dolu form sonraki kurulumda çıkardı).
  static int _gen = 0;

  /// Taslak — yoksa null.
  static Future<({String route, Map<String, dynamic> fields})?> read() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(_k);
      if (s == null) return null;
      final j = jsonDecode(s) as Map<String, dynamic>;
      final route = j['route'] as String?;
      if (route == null || !route.startsWith('/onboarding/')) return null;
      return (
        route: route,
        fields: (j['fields'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }

  /// Hedef seçildi → taslağı başlat (alanlar boş).
  static Future<void> start(String route) {
    _gen++;
    return _write(route, const {});
  }

  /// Form alanlarını güncelle (rota korunur; farklı rotadaysa yazılmaz).
  static Future<void> saveFields(String route, Map<String, dynamic> fields) async {
    final gen = _gen;
    final cur = await read();
    // Taslak yoksa (silinmiş) ya da başka dala aitse ya da arada silindiyse yazma.
    if (cur == null || cur.route != route || gen != _gen) return;
    await _write(route, fields);
  }

  static Future<void> clear() async {
    _gen++;
    try {
      await (await SharedPreferences.getInstance()).remove(_k);
    } catch (_) {}
  }

  static Future<void> _write(String route, Map<String, dynamic> fields) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_k, jsonEncode({'route': route, 'fields': fields}));
    } catch (_) {}
  }

  /// Tarih ↔ JSON (yalnız gün).
  static String? day(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static DateTime? parseDay(Object? s) =>
      s is String ? DateTime.tryParse(s) : null;
}
